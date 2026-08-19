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
    return data


def save(payload: dict[str, Any]) -> dict[str, Any]:
    current = load()
    channel = payload.pop("channel", None)
    current.update({k: v for k, v in payload.items() if k in DEFAULTS or k in current})
    if channel:
        current["channel"].update(channel)
    settings_path().write_text(json.dumps(current, indent=2), encoding="utf-8")
    return current
