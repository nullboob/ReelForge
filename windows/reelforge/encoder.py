from __future__ import annotations

import shutil
import subprocess
from functools import lru_cache

from reelforge.edl import ENCODER_WHITELIST


def which_ffmpeg() -> str | None:
    return shutil.which("ffmpeg")


@lru_cache(maxsize=1)
def listed_encoders() -> set[str]:
    binary = which_ffmpeg()
    if not binary:
        return {"libx264"}
    result = subprocess.run([binary, "-hide_banner", "-encoders"], capture_output=True, text=True)
    blob = result.stdout or ""
    found = {name for name in ENCODER_WHITELIST if name in blob}
    found.add("libx264")
    return found


def probe_encoder(name: str) -> bool:
    binary = which_ffmpeg()
    if not binary:
        return name == "libx264"
    if name not in listed_encoders():
        return False
    if name == "libx264":
        return True
    result = subprocess.run(
        [
            binary, "-hide_banner", "-y", "-f", "lavfi", "-i", "color=c=black:s=16x16:d=0.1",
            "-frames:v", "1", "-c:v", name, "-f", "null", "-",
        ],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def pick_encoder() -> str:
    for name in ENCODER_WHITELIST:
        if probe_encoder(name):
            return name
    return "libx264"


def video_args(codec: str | None = None) -> list[str]:
    name = codec or pick_encoder()
    args = ["-c:v", name, "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
    if name == "libx264":
        args += ["-crf", "18", "-preset", "veryfast"]
    elif name == "h264_nvenc":
        args += ["-preset", "p4", "-rc", "vbr", "-cq", "19"]
    elif name == "h264_videotoolbox":
        args += ["-q:v", "65"]
    return args
