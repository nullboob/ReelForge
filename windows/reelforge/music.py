from __future__ import annotations

import math
import os
import struct
import wave
from pathlib import Path

import httpx

SAMPLE_RATE = 44100
LOOP_SECONDS = 8.0


ACE_PROBE = (
    "http://127.0.0.1:7865/",
    "http://127.0.0.1:7865/config",
    "http://127.0.0.1:8001/health",
    "http://127.0.0.1:8019/health",
)
ACE_GENERATE = (
    "http://127.0.0.1:7865/generate",
    "http://127.0.0.1:8001/generate",
    "http://127.0.0.1:8001/v1/music",
    "http://127.0.0.1:8019/generate",
)


def probe_ace() -> bool:
    if os.environ.get("REELFORGE_SKIP_ACE") == "1":
        return False
    for url in ACE_PROBE:
        try:
            with httpx.Client(timeout=0.6) as client:
                if client.get(url).status_code < 500:
                    return True
        except Exception:
            continue
    return False


def try_ace_step(dest: Path, mood: str, bpm: int, duration: float) -> bool:
    if os.environ.get("REELFORGE_SKIP_ACE") == "1":
        return False
    body = {
        "prompt": f"Instrumental {mood} bed, {bpm} BPM, no vocals, clean loop, original-safe electronic score",
        "lyrics": "",
        "duration": max(8, int(duration or 8)),
        "bpm": bpm,
        "infer_step": 30,
    }
    for url in ACE_GENERATE:
        try:
            with httpx.Client(timeout=8.0) as client:
                response = client.post(url, json=body)
            if response.status_code >= 300 or len(response.content) < 200:
                continue
            try:
                payload = response.json()
            except Exception:
                payload = None
            if isinstance(payload, dict):
                b64 = payload.get("audio") or payload.get("wav")
                if isinstance(b64, str):
                    import base64
                    dest.write_bytes(base64.b64decode(b64))
                    return dest.exists() and dest.stat().st_size > 200
                path = payload.get("path")
                if isinstance(path, str) and Path(path).exists():
                    dest.write_bytes(Path(path).read_bytes())
                    return True
            if response.content[:4] in {b"RIFF", b"fLaC", b"OggS"} or response.headers.get("content-type", "").startswith("audio/"):
                dest.write_bytes(response.content)
                return True
        except Exception:
            continue
    return False


def write_loop(mood: str, bpm: int, dest: Path, duration: float | None = None) -> Path:
    seconds = max(LOOP_SECONDS, duration or LOOP_SECONDS)
    frames = int(seconds * SAMPLE_RATE)
    left = [0.0] * frames
    right = [0.0] * frames
    render(mood, max(60, bpm), left, right)
    write_wav(dest, left, right)
    return dest


def write_silence(dest: Path, duration: float) -> Path:
    frames = int(max(0.4, duration) * SAMPLE_RATE)
    zeros = [0.0] * frames
    write_wav(dest, zeros, zeros)
    return dest


def render(mood: str, bpm: int, left: list[float], right: list[float]) -> None:
    beat = 60.0 / bpm
    if mood == "cinematic":
        add_pad(left, right, [110, 165, 220, 329.6], 0.18)
        add_swell(left, right, 55, 0.12)
    elif mood == "clean":
        add_kick(left, right, beat * 2, 0.28)
        add_arp(left, right, [261.6, 329.6, 392.0, 523.3], beat, 0.11)
        add_pad(left, right, [130.8, 196.0], 0.08)
    elif mood == "warm":
        add_pad(left, right, [98, 147, 196, 246.9], 0.16)
        add_hats(left, right, beat, 0.06)
        add_bass(left, right, 49, beat * 2, 0.16)
    else:
        add_kick(left, right, beat, 0.55)
        add_hats(left, right, beat / 2, 0.12)
        add_bass(left, right, 55, beat, 0.22)
        add_arp(left, right, [196, 247, 294, 392], beat / 2, 0.09)
    normalize(left, right, 0.86)
    fade_edges(left, right)


def add_kick(left: list[float], right: list[float], beat: float, gain: float) -> None:
    interval = int(beat * SAMPLE_RATE)
    if interval <= 0:
        return
    length = int(0.18 * SAMPLE_RATE)
    t = 0
    while t < len(left):
        for i in range(min(length, len(left) - t)):
            local = i / SAMPLE_RATE
            env = math.exp(-local * 18)
            hz = 140.0 * math.exp(-local * 12) + 42
            sample = math.sin(2 * math.pi * hz * local) * env * gain
            left[t + i] += sample
            right[t + i] += sample
        t += interval


def add_hats(left: list[float], right: list[float], beat: float, gain: float) -> None:
    interval = int(beat * SAMPLE_RATE)
    if interval <= 0:
        return
    seed = 0xC0FFEE
    t = interval // 2
    length = int(0.03 * SAMPLE_RATE)
    while t < len(left):
        for i in range(min(length, len(left) - t)):
            seed = (seed * 6364136223846793005 + 1) & ((1 << 64) - 1)
            noise = ((seed >> 33) / (1 << 31)) * 2 - 1
            env = math.exp(-(i / SAMPLE_RATE) * 80)
            sample = noise * env * gain
            left[t + i] += sample
            right[t + i] += sample * 0.7
        t += interval


def add_bass(left: list[float], right: list[float], hz: float, beat: float, gain: float) -> None:
    for i in range(len(left)):
        t = i / SAMPLE_RATE
        pulse = 0.6 + 0.4 * math.sin(2 * math.pi * t / max(beat, 0.2))
        sample = math.sin(2 * math.pi * hz * t) * gain * pulse
        left[i] += sample
        right[i] += sample


def add_arp(left: list[float], right: list[float], notes: list[float], beat: float, gain: float) -> None:
    step = max(1, int(beat * SAMPLE_RATE))
    for i in range(len(left)):
        note = notes[(i // step) % len(notes)]
        local = (i % step) / SAMPLE_RATE
        env = math.exp(-local * 6)
        sample = math.sin(2 * math.pi * note * local) * env * gain
        left[i] += sample
        right[i] += sample * 0.85


def add_pad(left: list[float], right: list[float], freqs: list[float], gain: float) -> None:
    for i in range(len(left)):
        t = i / SAMPLE_RATE
        sample = sum(math.sin(2 * math.pi * hz * t) for hz in freqs) / max(1, len(freqs))
        left[i] += sample * gain
        right[i] += sample * gain * 0.92


def add_swell(left: list[float], right: list[float], hz: float, gain: float) -> None:
    n = len(left)
    for i in range(n):
        env = 0.5 - 0.5 * math.cos(2 * math.pi * i / max(1, n))
        sample = math.sin(2 * math.pi * hz * i / SAMPLE_RATE) * env * gain
        left[i] += sample
        right[i] += sample


def normalize(left: list[float], right: list[float], ceiling: float) -> None:
    peak = max(max(abs(s) for s in left), max(abs(s) for s in right), 1e-6)
    scale = ceiling / peak
    for i in range(len(left)):
        left[i] *= scale
        right[i] *= scale


def fade_edges(left: list[float], right: list[float], ms: int = 12) -> None:
    fade = int(SAMPLE_RATE * ms / 1000)
    for i in range(min(fade, len(left))):
        g = i / max(1, fade)
        left[i] *= g
        right[i] *= g
        left[-1 - i] *= g
        right[-1 - i] *= g


def write_wav(dest: Path, left: list[float], right: list[float]) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(dest), "w") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for l, r in zip(left, right):
            frames += struct.pack("<hh", _pcm(l), _pcm(r))
        wav.writeframes(frames)


def _pcm(sample: float) -> int:
    return max(-32768, min(32767, int(sample * 32767)))
