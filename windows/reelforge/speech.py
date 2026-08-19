from __future__ import annotations

import os
import shutil
import subprocess
import wave
from pathlib import Path

import httpx

from reelforge.music import SAMPLE_RATE, write_silence

KOKORO_URLS = (
    "http://127.0.0.1:8880/v1/audio/speech",
    "http://127.0.0.1:8880/audio/speech",
)

KOKORO_VOICES = [
    ("kokoro:af_bella", "Kokoro · Bella"),
    ("kokoro:af_sarah", "Kokoro · Sarah"),
    ("kokoro:am_adam", "Kokoro · Adam"),
    ("kokoro:am_michael", "Kokoro · Michael"),
    ("kokoro:bf_emma", "Kokoro · Emma"),
    ("kokoro:af_nicole", "Kokoro · Nicole"),
    ("kokoro:am_fenrir", "Kokoro · Fenrir"),
]


def synthesize(text: str, dest: Path, voice_identifier: str | None = None, speed: float = 1.0) -> tuple[float, str, list[dict]]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    spoken = text.replace(", ", ", … ").strip()
    if not spoken:
        write_silence(dest, 4)
        return 4.0, "silence", []

    wants_kokoro = voice_identifier is None or str(voice_identifier).startswith("kokoro:")
    if wants_kokoro:
        voice = "af_bella"
        if voice_identifier and str(voice_identifier).startswith("kokoro:"):
            voice = str(voice_identifier).split(":", 1)[1]
        duration = _kokoro(spoken, dest, voice, speed)
        if duration:
            return duration, "Kokoro", []

    timed = _edge_tts_cli(spoken, dest)
    if timed:
        return timed[0], "edge-tts-cli", timed[1]

    if _basic_voice(spoken, dest):
        return wav_duration(dest) or estimate_duration(spoken), "basic voice", []

    write_silence(dest, estimate_duration(spoken))
    return estimate_duration(spoken), "silence", []


def probe_kokoro() -> bool:
    try:
        with httpx.Client(timeout=0.6) as client:
            for url in ("http://127.0.0.1:8880/v1/models", "http://127.0.0.1:8880/"):
                try:
                    response = client.get(url)
                    if response.status_code < 500:
                        return True
                except httpx.HTTPError:
                    continue
    except Exception:
        return False
    return False


def probe_edge_tts_cli() -> bool:
    return shutil.which("edge-tts") is not None


def probe_basic_voice() -> bool:
    if os.name == "nt":
        return shutil.which("powershell") is not None
    return shutil.which("say") is not None


def probe_ollama() -> str | None:
    try:
        with httpx.Client(timeout=0.6) as client:
            response = client.get("http://127.0.0.1:11434/api/tags")
            if response.status_code == 200:
                models = response.json().get("models") or []
                if models:
                    return models[0].get("name")
                return "ollama"
    except Exception:
        return None
    return None


def _kokoro(text: str, dest: Path, voice: str, speed: float) -> float | None:
    payload = {
        "model": "kokoro",
        "input": text,
        "voice": voice,
        "response_format": "wav",
        "speed": max(0.7, min(1.4, speed)),
    }
    try:
        with httpx.Client(timeout=60) as client:
            for url in KOKORO_URLS:
                try:
                    response = client.post(url, json=payload)
                    if 200 <= response.status_code < 300 and len(response.content) > 200:
                        dest.write_bytes(response.content)
                        return wav_duration(dest) or estimate_duration(text)
                except httpx.HTTPError:
                    continue
    except Exception:
        return None
    return None


def _edge_tts_cli(text: str, dest: Path) -> tuple[float, list[dict]] | None:
    """User-installed edge-tts CLI only. Do not import or vendor the package."""
    if os.environ.get("REELFORGE_DISABLE_EDGE_TTS") == "1":
        return None
    binary = shutil.which("edge-tts")
    if not binary:
        return None
    tmp = dest.with_suffix(".edge.mp3")
    result = subprocess.run(
        [binary, "--voice", "en-US-JennyNeural", "--text", text, "--write-media", str(tmp)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not tmp.exists() or tmp.stat().st_size < 200:
        tmp.unlink(missing_ok=True)
        return None
    duration = _transcode_to_wav(tmp, dest) or estimate_duration(text)
    tmp.unlink(missing_ok=True)
    if dest.exists() and dest.stat().st_size > 200:
        return duration, []
    return None


def _transcode_to_wav(src: Path, dest: Path) -> float | None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    result = subprocess.run(
        [ffmpeg, "-hide_banner", "-y", "-i", str(src), "-ac", "1", "-ar", str(SAMPLE_RATE), str(dest)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not dest.exists():
        return None
    return wav_duration(dest)


def wav_duration(path: Path) -> float | None:
    try:
        with wave.open(str(path), "r") as wav:
            return wav.getnframes() / float(wav.getframerate() or SAMPLE_RATE)
    except Exception:
        return None


def estimate_duration(text: str) -> float:
    words = len(text.split())
    return max(4.0, words / 2.35)


def _basic_voice(text: str, dest: Path) -> bool:
    """OS neural / SAPI last resort. Labeled 'basic voice'. Do not vendor pyttsx3."""
    if os.environ.get("REELFORGE_DISABLE_BASIC_VOICE") == "1":
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    if os.name == "nt" and (powershell := shutil.which("powershell")):
        script = (
            "Add-Type -AssemblyName System.Speech; "
            "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
            f"$s.SetOutputToWaveFile('{str(dest).replace(chr(39), '')}'); "
            f"$s.Speak('{text.replace(chr(39), '').replace(chr(10), ' ')[:800]}'); "
            "$s.Dispose()"
        )
        result = subprocess.run([powershell, "-NoProfile", "-Command", script], capture_output=True, text=True)
        return result.returncode == 0 and dest.exists() and dest.stat().st_size > 200
    say = shutil.which("say")
    if say:
        aiff = dest.with_suffix(".aiff")
        result = subprocess.run([say, "-o", str(aiff), text[:800]], capture_output=True, text=True)
        if result.returncode == 0 and aiff.exists():
            return bool(_transcode_to_wav(aiff, dest))
    return False
