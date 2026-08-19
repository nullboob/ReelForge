from __future__ import annotations

import os
from pathlib import Path


def package_dir() -> Path:
    return Path(__file__).resolve().parent


def windows_dir() -> Path:
    return package_dir().parent


def repo_root() -> Path:
    here = windows_dir()
    if (here.parent / "Sources" / "ReelForgeCore" / "Resources" / "presets").is_dir():
        return here.parent
    return here


def presets_dir() -> Path:
    return repo_root() / "Sources" / "ReelForgeCore" / "Resources" / "presets"


def web_dir() -> Path:
    return package_dir() / "web"


def app_data() -> Path:
    base = os.environ.get("APPDATA") or os.environ.get("LOCALAPPDATA")
    if base:
        root = Path(base) / "ReelForge"
    else:
        root = Path.home() / ".reelforge"
    root.mkdir(parents=True, exist_ok=True)
    return root


def videos_dir() -> Path:
    videos = Path.home() / "Videos" / "ReelForge"
    videos.mkdir(parents=True, exist_ok=True)
    return videos


def work_dir() -> Path:
    path = app_data() / "work"
    path.mkdir(parents=True, exist_ok=True)
    return path


def settings_path() -> Path:
    return app_data() / "settings.json"


def blacklist_path(channel: str) -> Path:
    slug = "-".join(part for part in "".join(ch.lower() if ch.isalnum() else "-" for ch in channel).split("-") if part)
    name = slug or "default"
    return app_data() / f"pexels-blacklist-{name}.json"
