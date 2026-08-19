from __future__ import annotations

import os
import shutil
import zipfile
from pathlib import Path

from reelforge.paths import bin_dir, ffmpeg_candidates


def which_ffmpeg() -> str | None:
    for candidate in ffmpeg_candidates():
        if candidate.is_file() and os.access(candidate, os.X_OK if os.name != "nt" else os.F_OK):
            return str(candidate)
    found = shutil.which("ffmpeg")
    return found


def ffmpeg_url() -> str:
    from reelforge.setup import load_manifest
    for item in load_manifest().get("files") or []:
        if item.get("id") == "ffmpeg-win" and item.get("urls"):
            return item["urls"][0]
    return "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl.zip"


def install_from_zip(archive: Path, dest_dir: Path | None = None) -> str:
    dest_dir = dest_dir or bin_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as zipped:
        name = next((item for item in zipped.namelist() if item.endswith("ffmpeg.exe") or item.endswith("/ffmpeg") or item.endswith("ffmpeg")), None)
        if not name:
            raise RuntimeError("The ffmpeg zip did not contain an ffmpeg binary.")
        target = dest_dir / ("ffmpeg.exe" if name.endswith(".exe") else "ffmpeg")
        with zipped.open(name) as src, target.open("wb") as out:
            shutil.copyfileobj(src, out)
        try:
            target.chmod(0o755)
        except OSError:
            pass
    if not target.exists():
        raise RuntimeError("ffmpeg extract failed.")
    return str(target)


def ensure(opener=None) -> dict:
    found = which_ffmpeg()
    if found:
        return {"ok": True, "path": found, "downloaded": False}
    from reelforge.setup import download_file
    archive = bin_dir() / "ffmpeg.zip"
    download_file(ffmpeg_url(), archive, opener=opener)
    path = install_from_zip(archive)
    return {"ok": True, "path": path, "downloaded": True}
