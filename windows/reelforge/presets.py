from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from reelforge.paths import presets_dir

EXPECTED_IDS = [
    "viral-hook",
    "cinematic-story",
    "product-demo",
    "faceless-facts",
    "luxury-brand",
    "youtube-short-news",
    "travel-vlog",
    "tutorial-steps",
    "listicle",
    "explainer",
    "storytime",
    "motivational",
    "podcast-clip",
    "news-roundup",
]


def load_presets(directory: Path | None = None) -> list[dict[str, Any]]:
    folder = directory or presets_dir()
    files = sorted(folder.glob("*.json"))
    if not files:
        raise FileNotFoundError(f"No presets in {folder}")
    presets = [json.loads(path.read_text(encoding="utf-8")) for path in files]

    def order(preset: dict[str, Any]) -> int:
        try:
            return EXPECTED_IDS.index(preset["id"])
        except ValueError:
            return 99

    return sorted(presets, key=order)


def get_preset(preset_id: str, directory: Path | None = None) -> dict[str, Any]:
    for preset in load_presets(directory):
        if preset["id"] == preset_id:
            return preset
    raise KeyError(preset_id)


def pixel_size(aspect: str) -> tuple[int, int]:
    return {
        "9:16": (1080, 1920),
        "16:9": (1920, 1080),
        "1:1": (1080, 1080),
    }.get(aspect, (1080, 1920))


def clamped_duck_db(preset: dict[str, Any]) -> float:
    raw = float(preset.get("music", {}).get("duckDb", -10))
    return min(-8.0, max(-12.0, raw))


def duck_linear(preset: dict[str, Any]) -> float:
    return 10 ** (clamped_duck_db(preset) / 20.0)


def max_caption_words(preset: dict[str, Any]) -> int:
    requested = int(preset.get("captionStyle", {}).get("maxWordsPerCard", 3))
    return max(1, min(requested, 3))
