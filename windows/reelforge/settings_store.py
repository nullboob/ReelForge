from __future__ import annotations

import json
from typing import Any

from reelforge.paths import settings_path


DEFAULTS: dict[str, Any] = {
    "pexelsKey": "",
    "pixabayKey": "",
    "unsplashKey": "",
    "usePexels": True,
    "usePixabay": True,
    "useUnsplash": False,
    "allowCards": False,
    "captionStyleID": "tiktok-classic-outline",
    "useLocalAI": True,
    "burnCaptions": True,
    "exportSRT": True,
    "voiceIdentifier": None,
    "voiceSpeed": 1.0,
    "modelsDir": "",
    "useLocalModels": True,
    "setupComplete": False,
    "comfyUrl": "http://127.0.0.1:8188",
    "localMode": "stock-first",
    "ltxCkpt": "ltx-2.3-22b-distilled.safetensors",
    "ltxLora": "ltx-2.3-22b-distilled-lora-384.safetensors",
    "ltxFallback": "ltx-video-2b-v0.9.safetensors",
    "qwenCkpt": "qwen_image_fp8_e4m3fn.safetensors",
    "qwenLora": "Qwen-Image-Lightning-8steps-V1.0.safetensors",
    "qwenClip": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
    "qwenVae": "qwen_image_vae.safetensors",
    "qwenEditCkpt": "qwen_image_edit_2511.safetensors",
    "qwenEditLora": "Qwen-Image-Edit-Lightning-4steps-V1.0.safetensors",
    "wanCkpt": "wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors",
    "wanLora": "lightx2v_T2V_14B_cfg_step_distill_v2.safetensors",
    "wanClip": "umt5_xxl_fp8_e4m3fn_scaled.safetensors",
    "wanVae": "wan_2.1_vae.safetensors",
    "ideogramCkpt": "",
    "channel": {
        "name": "",
        "primaryHex": "#FF4D6D",
        "accentHex": "#E8C39A",
        "logoPath": "",
        "outroEnabled": True,
        "defaultVoice": None,
        "defaultPresetID": "viral-hook",
        "defaultAspect": None,
        "musicFolderPath": "",
    },
}


def load() -> dict[str, Any]:
    path = settings_path()
    data = dict(DEFAULTS)
    data["channel"] = dict(DEFAULTS["channel"])
    if path.exists():
        raw = json.loads(path.read_text(encoding="utf-8"))
        channel = raw.pop("channel", {})
        data.update(raw)
        data["channel"] = {**DEFAULTS["channel"], **channel}
    data["useUnsplash"] = False if data.get("useUnsplash") is None else bool(data.get("useUnsplash"))
    from reelforge.caption_styles import resolve_id
    data["captionStyleID"] = resolve_id(data.get("captionStyleID"))
    if data.get("localMode") not in {"stock-first", "local-fast", "local-quality"}:
        data["localMode"] = "stock-first"
    data["comfyUrl"] = (data.get("comfyUrl") or "http://127.0.0.1:8188").rstrip("/")
    return data


def save(payload: dict[str, Any]) -> dict[str, Any]:
    current = load()
    channel = payload.pop("channel", None)
    current.update({k: v for k, v in payload.items() if k in DEFAULTS or k in current})
    if channel:
        current["channel"].update(channel)
    settings_path().write_text(json.dumps(current, indent=2), encoding="utf-8")
    return current
