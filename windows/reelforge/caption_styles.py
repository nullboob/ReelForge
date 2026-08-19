from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from reelforge.paths import caption_catalog_path, fonts_dir


REQUIRED_IDS = [
    "tiktok-classic-outline", "hormozi-yellow-pop", "karaoke-yellow-sweep", "word-pop-sync",
    "single-word-center", "bounce-fitness", "typewriter-story", "quiet-aesthetic-min",
    "color-switch-strobe", "commentary-telegraph", "kinetic-hook-slide", "neon-glow-pulse",
    "outline-double-stroke", "faceless-stack-highlight", "podcast-split-karaoke", "cinematic-gold-fade",
    "boxed-pill-yellow", "beast-3d-pop", "listicle-number-chip", "boxed-kinetic-bar",
    "cta-urgent-red", "gradient-rainbow-word", "gradient-sunset-fill", "gradient-chrome-metallic",
    "gradient-neon-cyan-magenta", "gradient-gold-metallic", "gradient-fire", "gradient-ice",
    "gradient-candy", "gradient-duotone-yellow-pink",
]


@lru_cache(maxsize=1)
def load_catalog() -> dict[str, Any]:
    return json.loads(caption_catalog_path().read_text(encoding="utf-8"))


def all_styles() -> list[dict[str, Any]]:
    return list(load_catalog().get("styles") or [])


def resolve_id(style_id: str | None) -> str:
    catalog = load_catalog()
    aliases = catalog.get("aliases") or {}
    current = style_id or catalog.get("defaultStyleID") or "tiktok-classic-outline"
    seen: set[str] = set()
    while current in aliases and current not in seen:
        seen.add(current)
        current = aliases[current]
    return current


def style_by_id(style_id: str | None) -> dict[str, Any]:
    styles = {item["id"]: item for item in all_styles()}
    resolved = resolve_id(style_id)
    if resolved in styles:
        return styles[resolved]
    return styles[load_catalog().get("defaultStyleID") or "tiktok-classic-outline"]


def default_for_preset(preset_id: str) -> str:
    mapped = (load_catalog().get("presetDefaults") or {}).get(preset_id)
    return resolve_id(mapped or load_catalog().get("defaultStyleID") or "tiktok-classic-outline")


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
    _ = preset_id
    cap = int(style.get("maxWords") or requested or 3)
    return max(1, min(cap, 3))
