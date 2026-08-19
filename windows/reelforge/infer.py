from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from reelforge import models
from reelforge.presets import pixel_size

_loaded: dict[str, Any] = {"kind": None, "pipe": None}


def aligned_size(width: int, height: int, multiple: int = 32) -> tuple[int, int]:
    def snap(value: int) -> int:
        return max(multiple, (int(value) // multiple) * multiple)

    return snap(width), snap(height)


def frame_count(seconds: float, fps: int = 24) -> int:
    raw = max(9, int(round(seconds * fps)))
    # LTX wants 8k + 1
    return ((raw + 6) // 8) * 8 + 1


def available(models_dir: str | None = None) -> dict[str, Any]:
    catalog = models.scan(models_dir)
    catalog["torch"] = _have_torch()
    catalog["diffusers"] = _have_module("diffusers")
    catalog["ltxPipelines"] = _have_module("ltx_pipelines")
    return catalog


def generate_video(
    prompt: str,
    dest: Path,
    aspect: str = "9:16",
    seconds: float = 3.0,
    models_dir: str | None = None,
) -> bool:
    if os.environ.get("REELFORGE_SKIP_INFER") == "1":
        return False
    if _comfy_hatch(prompt, dest, "video"):
        return True
    catalog = models.scan(models_dir)
    if not catalog.get("videoReady"):
        return False
    width, height = aligned_size(*pixel_size(aspect))
    frames = frame_count(seconds)
    unload("image")
    try:
        return _ltx_video(prompt, dest, width, height, frames, catalog)
    except Exception:
        return False


def generate_image(
    prompt: str,
    dest: Path,
    aspect: str = "9:16",
    models_dir: str | None = None,
) -> bool:
    if os.environ.get("REELFORGE_SKIP_INFER") == "1":
        return False
    if _comfy_hatch(prompt, dest, "image"):
        return True
    catalog = models.scan(models_dir)
    if not catalog.get("imageReady"):
        return False
    width, height = aligned_size(*pixel_size(aspect))
    unload("video")
    try:
        return _qwen_image(prompt, dest, width, height, catalog)
    except Exception:
        return False


def generate_wan_video(prompt: str, dest: Path, **_: Any) -> bool:
    """Wan 2.2 + LightX2V is a later optional path. Not ComfyUI."""
    return False


def unload(kind: str | None = None) -> None:
    if kind and _loaded.get("kind") != kind:
        return
    pipe = _loaded.get("pipe")
    _loaded["kind"] = None
    _loaded["pipe"] = None
    if pipe is None:
        return
    try:
        import gc
        del pipe
        gc.collect()
        if _have_torch():
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
    except Exception:
        pass


def _ltx_video(prompt: str, dest: Path, width: int, height: int, frames: int, catalog: dict[str, Any]) -> bool:
    weight = models.slot_path(catalog, "ltx-distilled")
    if not weight or not weight.exists():
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    if _have_module("ltx_pipelines"):
        from ltx_pipelines import DistilledPipeline  # type: ignore
        pipe = _loaded["pipe"] if _loaded.get("kind") == "video" else DistilledPipeline(str(weight))
        _loaded.update(kind="video", pipe=pipe)
        pipe(
            prompt=prompt,
            width=width,
            height=height,
            num_frames=frames,
            num_inference_steps=8,
            guidance_scale=1.0,
            output_path=str(dest),
        )
        return dest.exists() and dest.stat().st_size > 400
    if _have_module("diffusers"):
        import diffusers
        cls = getattr(diffusers, "LTX2Pipeline", None) or getattr(diffusers, "LTXPipeline", None)
        if cls is None:
            return False
        pipe = _loaded["pipe"] if _loaded.get("kind") == "video" else cls.from_single_file(str(weight), local_files_only=True)
        _loaded.update(kind="video", pipe=pipe)
        result = pipe(
            prompt=prompt,
            width=width,
            height=height,
            num_frames=frames,
            num_inference_steps=8,
            guidance_scale=1.0,
        )
        frames_out = getattr(result, "frames", None) or getattr(result, "images", None)
        if not frames_out:
            return False
        return _write_video_frames(frames_out[0] if isinstance(frames_out[0], list) else frames_out, dest)
    return False


def _qwen_image(prompt: str, dest: Path, width: int, height: int, catalog: dict[str, Any]) -> bool:
    weight = models.slot_path(catalog, "qwen-image")
    if not weight or not weight.exists() or not _have_module("diffusers"):
        return False
    import diffusers
    cls = getattr(diffusers, "QwenImagePipeline", None)
    if cls is None:
        return False
    pipe = _loaded["pipe"] if _loaded.get("kind") == "image" else cls.from_single_file(str(weight), local_files_only=True)
    lora = models.slot_path(catalog, "qwen-lightning")
    if lora and hasattr(pipe, "load_lora_weights"):
        try:
            pipe.load_lora_weights(str(lora.parent), weight_name=lora.name)
        except Exception:
            pass
    _loaded.update(kind="image", pipe=pipe)
    try:
        result = pipe(
            prompt=prompt,
            width=width,
            height=height,
            num_inference_steps=8,
            true_cfg_scale=1.0,
        )
    except TypeError:
        result = pipe(prompt=prompt, width=width, height=height, num_inference_steps=8)
    image = result.images[0]
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest)
    return dest.exists() and dest.stat().st_size > 400


def _write_video_frames(frames: list, dest: Path) -> bool:
    try:
        import imageio
        imageio.mimsave(dest, frames, fps=24)
        return dest.exists()
    except Exception:
        pass
    first = frames[0]
    path = dest.with_suffix(".png")
    if hasattr(first, "save"):
        first.save(path)
        return path.exists()
    return False


def _have_torch() -> bool:
    return _have_module("torch")


def _have_module(name: str) -> bool:
    try:
        __import__(name)
        return True
    except Exception:
        return False


def _comfy_hatch(prompt: str, dest: Path, kind: str) -> bool:
    """Optional infer.py path into the Comfy sidecar when REELFORGE_COMFY_URL is set."""
    if os.environ.get("REELFORGE_SKIP_COMFY") == "1":
        return False
    if not (os.environ.get("REELFORGE_COMFY_URL") or "").strip():
        return False
    from reelforge import comfy
    if kind == "video":
        return comfy.generate_video(prompt, dest)
    return comfy.generate_image(prompt, dest)
