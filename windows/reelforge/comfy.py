from __future__ import annotations

import json
import os
import random
import time
from pathlib import Path
from typing import Any
from uuid import uuid4

import httpx

from reelforge.paths import app_data, package_dir
from reelforge.presets import pixel_size

DEFAULT_URL = "http://127.0.0.1:8188"
NEGATIVE = "text, words, letters, logo, watermark, caption, subtitle, title card, office, handshake, aerial city, stock footage, generic"

DEFAULT_MODELS = {
    "ltxCkpt": "ltx-2.3-22b-distilled.safetensors",
    "ltxLora": "ltx-2.3-22b-distilled-lora-384.safetensors",
    "ltxFallback": "ltx-video-2b-v0.9.safetensors",
    "qwenCkpt": "qwen_image_fp8_e4m3fn.safetensors",
    "qwenLora": "Qwen-Image-Lightning-8steps-V1.0.safetensors",
    "qwenClip": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
    "qwenVae": "qwen_image_vae.safetensors",
    "wanCkpt": "wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors",
    "wanLora": "lightx2v_T2V_14B_cfg_step_distill_v2.safetensors",
    "wanClip": "umt5_xxl_fp8_e4m3fn_scaled.safetensors",
    "wanVae": "wan_2.1_vae.safetensors",
    "qwenEditCkpt": "qwen_image_edit_2511.safetensors",
    "qwenEditLora": "Qwen-Image-Edit-Lightning-4steps-V1.0.safetensors",
    "ideogramCkpt": "ideogram4_fp8.safetensors",
}

TIMEOUTS = {"ltx": 90.0, "wan": 180.0, "qwen": 20.0}


def base_url(url: str | None = None) -> str:
    raw = url or os.environ.get("REELFORGE_COMFY_URL") or DEFAULT_URL
    return raw.rstrip("/")


def probe(url: str | None = None) -> dict[str, Any]:
    root = base_url(url)
    empty = {"up": False, "ltx": False, "wan": False, "qwen": False, "url": root, "models": []}
    if os.environ.get("REELFORGE_SKIP_COMFY") == "1":
        return empty
    try:
        with httpx.Client(timeout=1.6) as client:
            response = client.get(f"{root}/system_stats")
            if response.status_code >= 500:
                return empty
    except Exception:
        return empty
    names = list_model_names(root)
    blob = " ".join(names).lower()
    ltx = any(token in blob for token in ("ltx-2.3", "ltx2.3", "ltx-2.3-22b", "distilled-lora-384")) or "ltx" in blob
    wan = any(token in blob for token in ("wan2.2", "wan-2.2", "wan22", "lightx2v"))
    qwen = "qwen" in blob
    if not names:
        ltx = wan = qwen = True
    return {"up": True, "ltx": ltx, "wan": wan, "qwen": qwen, "url": root, "models": names[:48]}


def list_model_names(url: str) -> list[str]:
    names: list[str] = []
    for path in (
        "/models/checkpoints",
        "/models/diffusion_models",
        "/models/loras",
        "/models/text_encoders",
        "/models/vae",
        "/models/unet",
    ):
        try:
            with httpx.Client(timeout=2.0) as client:
                response = client.get(f"{url}{path}")
                if response.status_code == 200:
                    payload = response.json()
                    if isinstance(payload, list):
                        names.extend(str(item) for item in payload)
                    elif isinstance(payload, dict):
                        names.extend(str(item) for item in payload.get("models") or payload.keys())
        except Exception:
            continue
    return names


def fill_template(node: Any, mapping: dict[str, Any]) -> Any:
    if isinstance(node, str):
        for key, value in mapping.items():
            token = "{{" + key + "}}"
            if node == token:
                return value
            if token in node:
                node = node.replace(token, str(value))
        return node
    if isinstance(node, list):
        return [fill_template(item, mapping) for item in node]
    if isinstance(node, dict):
        return {key: fill_template(value, mapping) for key, value in node.items()}
    return node


def load_workflow(name: str) -> dict[str, Any]:
    override = app_data() / "workflows" / f"{name}.json"
    bundled = package_dir() / "workflows" / f"{name}.json"
    path = override if override.exists() else bundled
    return json.loads(path.read_text(encoding="utf-8"))


def render_prompt(text: str, style_suffix: str = "", aspect: str = "9:16") -> str:
    from reelforge.footage import specific_query
    cleaned = specific_query(text or "handheld documentary texture")
    suffix = (style_suffix or "").strip()
    return (
        f"{cleaned}, vertical {aspect} photoreal footage, natural light, no text, no captions, "
        f"no logo, no watermark, no title card. {suffix}"
    ).strip()


def generate_video(
    prompt: str,
    dest: Path,
    kind: str = "ltx",
    aspect: str = "9:16",
    seconds: float = 3.0,
    url: str | None = None,
    settings: dict[str, Any] | None = None,
) -> bool:
    if os.environ.get("REELFORGE_SKIP_COMFY") == "1":
        return False
    cfg = settings or {}
    width, height = _aligned(*pixel_size(aspect))
    frames = _frame_count(seconds)
    mapping = {
        "PROMPT": prompt,
        "NEGATIVE": NEGATIVE,
        "WIDTH": width,
        "HEIGHT": height,
        "FRAMES": frames,
        "SEED": int(cfg.get("seed") or random.randint(1, 2_000_000_000)),
        "CKPT": cfg.get("ltxCkpt" if kind == "ltx" else "wanCkpt") or DEFAULT_MODELS["ltxCkpt" if kind == "ltx" else "wanCkpt"],
        "LORA": cfg.get("ltxLora" if kind == "ltx" else "wanLora") or DEFAULT_MODELS["ltxLora" if kind == "ltx" else "wanLora"],
        "CLIP": cfg.get("wanClip") or DEFAULT_MODELS["wanClip"],
        "VAE": cfg.get("wanVae") or DEFAULT_MODELS["wanVae"],
    }
    workflow = fill_template(load_workflow("ltx-fast" if kind == "ltx" else "wan-quality"), mapping)
    return _run(workflow, dest, base_url(url or cfg.get("comfyUrl")), TIMEOUTS[kind])


def generate_image(
    prompt: str,
    dest: Path,
    aspect: str = "9:16",
    url: str | None = None,
    settings: dict[str, Any] | None = None,
) -> bool:
    if os.environ.get("REELFORGE_SKIP_COMFY") == "1":
        return False
    cfg = settings or {}
    width, height = _aligned(*pixel_size(aspect))
    mapping = {
        "PROMPT": prompt,
        "NEGATIVE": NEGATIVE,
        "WIDTH": width,
        "HEIGHT": height,
        "SEED": int(cfg.get("seed") or random.randint(1, 2_000_000_000)),
        "CKPT": cfg.get("qwenCkpt") or DEFAULT_MODELS["qwenCkpt"],
        "LORA": cfg.get("qwenLora") or DEFAULT_MODELS["qwenLora"],
        "CLIP": cfg.get("qwenClip") or DEFAULT_MODELS["qwenClip"],
        "VAE": cfg.get("qwenVae") or DEFAULT_MODELS["qwenVae"],
    }
    workflow = fill_template(load_workflow("qwen-image"), mapping)
    return _run(workflow, dest, base_url(url or cfg.get("comfyUrl")), TIMEOUTS["qwen"])


def _run(workflow: dict[str, Any], dest: Path, url: str, timeout: float) -> bool:
    client_id = str(uuid4())
    try:
        with httpx.Client(timeout=httpx.Timeout(max(timeout, 30.0), connect=4.0)) as client:
            submitted = client.post(f"{url}/prompt", json={"prompt": workflow, "client_id": client_id})
            if submitted.status_code >= 400:
                return False
            payload = submitted.json()
            if payload.get("error") or payload.get("node_errors"):
                return False
            prompt_id = payload.get("prompt_id")
            if not prompt_id:
                return False
            deadline = time.time() + timeout
            outputs = None
            while time.time() < deadline:
                history = client.get(f"{url}/history/{prompt_id}")
                if history.status_code == 200:
                    body = history.json() or {}
                    entry = body.get(prompt_id) or body
                    outputs = (entry or {}).get("outputs")
                    if outputs:
                        break
                time.sleep(0.4)
            if not outputs:
                return False
            asset = _first_asset(outputs)
            if not asset:
                return False
            view = client.get(f"{url}/view", params=asset)
            if view.status_code != 200 or len(view.content) < 400:
                return False
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(view.content)
            return dest.exists()
    except Exception:
        return False


def _first_asset(outputs: dict[str, Any]) -> dict[str, str] | None:
    for node in outputs.values():
        if not isinstance(node, dict):
            continue
        for key in ("gifs", "videos", "images"):
            items = node.get(key) or []
            if items:
                first = items[0]
                return {
                    "filename": first.get("filename") or "",
                    "subfolder": first.get("subfolder") or "",
                    "type": first.get("type") or "output",
                }
    return None


def _aligned(width: int, height: int, multiple: int = 32) -> tuple[int, int]:
    def snap(value: int) -> int:
        return max(multiple, (int(value) // multiple) * multiple)
    return snap(width), snap(height)


def _frame_count(seconds: float, fps: int = 24) -> int:
    raw = max(9, int(round(max(2.0, min(4.0, seconds)) * fps)))
    return ((raw + 6) // 8) * 8 + 1
