from __future__ import annotations


def human(exc: BaseException | str) -> str:
    text = str(exc)
    lower = text.lower()
    if "ffmpeg" in lower and ("not on path" in lower or "not found" in lower or "not available" in lower):
        return "We need ffmpeg to finish the MP4. Click Download ffmpeg — it lands in your ReelForge folder, not Windows."
    if "checksum" in lower:
        return "That download did not match the expected file. We deleted it. Hit retry."
    if "out of memory" in lower or "cuda" in lower and "memory" in lower:
        return "The GPU ran out of memory. We unload, retry a smaller size, then stills-only if it still fails."
    if "cards" in lower and "pexels" in lower:
        return "No moving B-roll yet. Add a free Pexels key, drop a local clip, or keep painted art."
    if "kokoro" in lower or "voice" in lower or "speech" in lower:
        return "Neural voice was busy. We try Kokoro, then edge-tts, then a basic system voice so export still finishes."
    if "ass=" in lower or "caption" in lower:
        return "Karaoke burn missed. We try PNG captions, then a sidecar SRT so you still have text."
    if "network" in lower or "timed out" in lower or "connection" in lower:
        return "The network blinked. Instant pack still works offline with painted art and cached stock."
    if text.strip():
        return f"{text.rstrip('.')} — export keeps a fallback so you are not stuck."
    return "Something failed, but there is a fallback. Check the log in AppData if it happens again."


def log(message: str) -> None:
    from reelforge.paths import log_path
    path = log_path()
    try:
        with path.open("a", encoding="utf-8") as handle:
            handle.write(message.rstrip() + "\n")
    except OSError:
        pass
