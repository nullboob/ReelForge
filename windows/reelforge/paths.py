from __future__ import annotations

import os
import sys
from pathlib import Path


def frozen() -> bool:
    return bool(getattr(sys, "frozen", False))


def package_dir() -> Path:
    if frozen():
        meipass = Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent))
        candidate = meipass / "reelforge"
        return candidate if candidate.is_dir() else meipass
    return Path(__file__).resolve().parent


def windows_dir() -> Path:
    return package_dir().parent if not frozen() else Path(sys.executable).parent


def repo_root() -> Path:
    if frozen():
        meipass = Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent))
        if (meipass / "Sources" / "ReelForgeCore" / "Resources" / "presets").is_dir():
            return meipass
        return meipass
    here = windows_dir()
    if (here.parent / "Sources" / "ReelForgeCore" / "Resources" / "presets").is_dir():
        return here.parent
    return here


def presets_dir() -> Path:
    return repo_root() / "Sources" / "ReelForgeCore" / "Resources" / "presets"


def fonts_dir() -> Path:
    return repo_root() / "Sources" / "ReelForgeCore" / "Resources" / "fonts"


def caption_catalog_path() -> Path:
    return repo_root() / "Sources" / "ReelForgeCore" / "Resources" / "caption-styles" / "catalog.json"


def web_dir() -> Path:
    return package_dir() / "web"


def app_data() -> Path:
    if override := os.environ.get("REELFORGE_DATA_DIR"):
        root = Path(override)
        root.mkdir(parents=True, exist_ok=True)
        return root
    if sys.platform == "darwin":
        root = Path.home() / "Library" / "Application Support" / "ReelForge"
    elif base := os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA"):
        root = Path(base) / "ReelForge"
    else:
        root = Path.home() / ".reelforge"
    root.mkdir(parents=True, exist_ok=True)
    return root


def models_dir() -> Path:
    path = Path(os.environ.get("REELFORGE_MODELS_DIR") or (app_data() / "models"))
    path.mkdir(parents=True, exist_ok=True)
    return path


def bin_dir() -> Path:
    path = app_data() / "bin"
    path.mkdir(parents=True, exist_ok=True)
    return path


def log_path() -> Path:
    return app_data() / "reelforge.log"


def ffmpeg_candidates() -> list[Path]:
    name = "ffmpeg.exe" if os.name == "nt" else "ffmpeg"
    return [
        bin_dir() / name,
        Path(sys.executable).parent / name,
        package_dir() / "vendor" / "ffmpeg" / name,
    ]


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
