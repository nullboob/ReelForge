from __future__ import annotations

import os
import shutil
import subprocess
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

    timed = _edge_tts(spoken, dest)
    if timed:
        return timed[0], "edge-tts", timed[1]

    duration = _sapi(spoken, dest, speed)
    if duration:
        return duration, "SAPI", []

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


def _edge_tts(text: str, dest: Path) -> tuple[float, list[dict]] | None:
    if os.environ.get("REELFORGE_DISABLE_EDGE_TTS") == "1":
        return None
    try:
        import asyncio
        import edge_tts
    except Exception:
        return None

    async def run() -> list[dict]:
        communicate = edge_tts.Communicate(text, "en-US-JennyNeural")
        words: list[dict] = []
        audio = bytearray()
        async for chunk in communicate.stream():
            kind = chunk.get("type")
            if kind == "audio":
                audio.extend(chunk.get("data") or b"")
            elif kind == "WordBoundary":
                words.append({
                    "word": chunk.get("text") or "",
                    "start": float(chunk.get("offset") or 0) / 10_000_000,
                    "duration": float(chunk.get("duration") or 0) / 10_000_000,
                })
        if len(audio) > 200:
            dest.write_bytes(bytes(audio))
        return words

    try:
        words = asyncio.run(run())
        if dest.exists() and dest.stat().st_size > 200:
            duration = wav_duration(dest)
            if duration is None:
                duration = _transcode_to_wav(dest) or estimate_duration(text)
            return duration, words
    except Exception:
        return None
    return None


def _transcode_to_wav(dest: Path) -> float | None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    tmp = dest.with_suffix(".edge.mp3")
    dest.replace(tmp)
    result = subprocess.run(
        [ffmpeg, "-hide_banner", "-y", "-i", str(tmp), "-ac", "1", "-ar", str(SAMPLE_RATE), str(dest)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not dest.exists():
        if tmp.exists() and not dest.exists():
            tmp.replace(dest)
        return None
    tmp.unlink(missing_ok=True)
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
