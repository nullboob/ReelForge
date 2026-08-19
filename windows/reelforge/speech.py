from __future__ import annotations

import os
import sys
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


def synthesize(text: str, dest: Path, voice_identifier: str | None = None, speed: float = 1.0) -> tuple[float, str]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    spoken = text.replace(", ", ", … ").strip()
    if not spoken:
        write_silence(dest, 4)
        return 4.0, "silence"

    wants_kokoro = voice_identifier is None or str(voice_identifier).startswith("kokoro:")
    if wants_kokoro:
        voice = "af_bella"
        if voice_identifier and str(voice_identifier).startswith("kokoro:"):
            voice = str(voice_identifier).split(":", 1)[1]
        duration = _kokoro(spoken, dest, voice, speed)
        if duration:
            return duration, "Kokoro"

    duration = _sapi(spoken, dest, speed)
    if duration:
        return duration, "SAPI"

    duration = _edge_tts(spoken, dest)
    if duration:
        return duration, "edge-tts"

    write_silence(dest, estimate_duration(spoken))
    return estimate_duration(spoken), "silence"


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


def _sapi(text: str, dest: Path, speed: float) -> float | None:
    if sys.platform != "win32":
        return None
    try:
        import pyttsx3
    except Exception:
        return None
    try:
        engine = pyttsx3.init()
        engine.setProperty("rate", int(180 * max(0.7, min(1.4, speed))))
        tmp = dest.with_suffix(".sapi.wav")
        engine.save_to_file(text, str(tmp))
        engine.runAndWait()
        if tmp.exists() and tmp.stat().st_size > 200:
            if dest.exists():
                dest.unlink()
            tmp.replace(dest)
            return wav_duration(dest) or estimate_duration(text)
    except Exception:
        return None
    return None


def _edge_tts(text: str, dest: Path) -> float | None:
    if os.environ.get("REELFORGE_DISABLE_EDGE_TTS") == "1":
        return None
    try:
        import asyncio
        import edge_tts
    except Exception:
        return None

    async def run() -> None:
        communicate = edge_tts.Communicate(text, "en-US-JennyNeural")
        await communicate.save(str(dest))

    try:
        asyncio.run(run())
        if dest.exists() and dest.stat().st_size > 200:
            return wav_duration(dest) or estimate_duration(text)
    except Exception:
        return None
    return None


def wav_duration(path: Path) -> float | None:
    try:
        with wave.open(str(path), "r") as wav:
            return wav.getnframes() / float(wav.getframerate() or SAMPLE_RATE)
    except Exception:
        return None


def estimate_duration(text: str) -> float:
    words = len(text.split())
    return max(4.0, words / 2.35)
