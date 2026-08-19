from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

from reelforge.paths import app_data


SLOTS = (
    {
        "id": "ltx-distilled",
        "name": "LTX-2.3 22B distilled",
        "kind": "video",
        "patterns": (r"ltx-2\.3-22b-distilled", r"ltx.*22b.*distill.*\.safetensors", r"ltx2.*distill.*\.safetensors"),
    },
    {
        "id": "ltx-lora",
        "name": "LTX distilled LoRA",
        "kind": "video",
        "patterns": (r"ltx.*lora", r"distill.*lora.*ltx", r"ltx.*distill.*lora"),
    },
    {
        "id": "gemma-encoder",
        "name": "Gemma text encoder",
        "kind": "video",
        "patterns": (r"gemma",),
    },
    {
        "id": "ltx-gguf",
        "name": "LTX Q5 GGUF",
        "kind": "video",
        "patterns": (r"ltx.*\.gguf", r"q5.*\.gguf", r"\.gguf"),
    },
    {
        "id": "qwen-image",
        "name": "Qwen Image",
        "kind": "image",
        "patterns": (r"qwen.*image", r"qwen_image", r"qwen2.*vl"),
    },
    {
        "id": "qwen-lightning",
        "name": "Qwen Lightning 8-step LoRA",
        "kind": "image",
        "patterns": (r"lightning", r"qwen.*lora"),
    },
    {
        "id": "wan-22",
        "name": "Wan 2.2 (optional later)",
        "kind": "video-quality",
        "patterns": (r"wan2\.2", r"wan-2\.2", r"wan22"),
    },
    {
        "id": "lightx2v",
        "name": "LightX2V 4-step (optional later)",
        "kind": "video-quality",
        "patterns": (r"lightx2v", r"light-x2v"),
    },
)


def default_scan_roots(models_dir: str | None = None) -> list[Path]:
    extra = os.environ.get("REELFORGE_MODEL_SCAN_ROOTS") or ""
    roots: list[Path] = []
    if extra:
        roots.extend(Path(part) for part in extra.split(os.pathsep) if part.strip())
    if models_dir:
        roots.append(Path(models_dir))
    roots.extend([
        app_data() / "models",
        Path(r"E:\ComfyUI_windows_portable_nvidia\ComfyUI\models"),
        Path("D:/"),
    ])
    seen: set[str] = set()
    unique: list[Path] = []
    for root in roots:
        key = str(root)
        if key in seen:
            continue
        seen.add(key)
        unique.append(root)
    return unique


def scan(models_dir: str | None = None, roots: list[Path] | None = None) -> dict[str, Any]:
    files = collect_weight_files(roots or default_scan_roots(models_dir))
    slots = []
    for spec in SLOTS:
        match = first_match(files, spec["patterns"])
        slots.append({
            "id": spec["id"],
            "name": spec["name"],
            "kind": spec["kind"],
            "ready": match is not None,
            "path": str(match) if match else None,
        })
    video_ready = any(item["id"] == "ltx-distilled" and item["ready"] for item in slots)
    image_ready = any(item["id"] == "qwen-image" and item["ready"] for item in slots)
    return {
        "slots": slots,
        "videoReady": video_ready,
        "imageReady": image_ready,
        "anyReady": video_ready or image_ready,
        "scannedFiles": len(files),
        "modelsDir": models_dir or "",
    }


def collect_weight_files(roots: list[Path]) -> list[Path]:
    found: list[Path] = []
    for root in roots:
        if not root.exists() or not root.is_dir():
            continue
        # D:\ is huge — only look at top-level weight files plus one models/ folder.
        if _is_drive_root(root):
            found.extend(p for p in root.glob("*.safetensors") if p.is_file())
            found.extend(p for p in root.glob("*.gguf") if p.is_file())
            nested = root / "models"
            if nested.is_dir():
                found.extend(_walk_weights(nested, depth=4))
            continue
        found.extend(_walk_weights(root, depth=6))
    return found


def _is_drive_root(path: Path) -> bool:
    try:
        return path.resolve() == path.resolve().anchor
    except Exception:
        return False


def _walk_weights(root: Path, depth: int) -> list[Path]:
    out: list[Path] = []
    try:
        for dirpath, dirnames, filenames in os.walk(root):
            rel = Path(dirpath).relative_to(root)
            if len(rel.parts) >= depth:
                dirnames[:] = []
            for name in filenames:
                lower = name.lower()
                if lower.endswith((".safetensors", ".gguf", ".bin", ".pt")):
                    out.append(Path(dirpath) / name)
    except OSError:
        return out
    return out


def first_match(files: list[Path], patterns: tuple[str, ...]) -> Path | None:
    compiled = [re.compile(pattern, re.I) for pattern in patterns]
    for path in files:
        hay = path.name
        if any(rx.search(hay) for rx in compiled):
            return path
    return None


def slot_path(catalog: dict[str, Any], slot_id: str) -> Path | None:
    for item in catalog.get("slots") or []:
        if item.get("id") == slot_id and item.get("path"):
            return Path(item["path"])
    return None
