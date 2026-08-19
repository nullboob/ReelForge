from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from reelforge.paths import caption_catalog_path, fonts_dir


REQUIRED_IDS = [
    "dynamic-minimal", "hormozi-classic", "pill-black", "pill-yellow", "pill-hot", "pill-brand",
    "capcut-classic", "most-readable", "fancy-soft", "checksub-rose", "glow-clean", "boxed-outline",
    "typewriter", "color-switch", "quiet-aesthetic", "bebas-sports", "archivo-hype", "tiktok-native",
    "sunset-fill", "candy-pop", "neon-cyber", "gold-metallic", "fire-sweep", "ice-chrome",
    "rainbow-word", "duotone-sun", "chrome-silver", "ocean-teal", "grape-aurora", "lime-punch",
]


@lru_cache(maxsize=1)
def load_catalog() -> dict[str, Any]:
    return json.loads(caption_catalog_path().read_text(encoding="utf-8"))


def all_styles() -> list[dict[str, Any]]:
    return list(load_catalog().get("styles") or [])


def style_by_id(style_id: str | None) -> dict[str, Any]:
    styles = {item["id"]: item for item in all_styles()}
    if style_id and style_id in styles:
        return styles[style_id]
    return styles[load_catalog().get("defaultStyleID") or "dynamic-minimal"]


def default_for_preset(preset_id: str) -> str:
    mapped = (load_catalog().get("presetDefaults") or {}).get(preset_id)
    return mapped or load_catalog().get("defaultStyleID") or "dynamic-minimal"


def font_path(style: dict[str, Any]) -> Path | None:
    name = style.get("fontFile") or ""
    candidate = fonts_dir() / name
    if candidate.exists():
        return candidate
    for fallback in ("Montserrat-ExtraBold.ttf", "Inter-Bold.ttf"):
        path = fonts_dir() / fallback
        if path.exists():
            return path
    return None


def max_words(style: dict[str, Any], preset_id: str, requested: int) -> int:
    cap = int(style.get("maxWords") or requested or 5)
    if preset_id == "viral-hook":
        return min(max(cap, 3), 6)
    return max(1, cap)
