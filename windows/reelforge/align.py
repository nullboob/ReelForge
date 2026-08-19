from __future__ import annotations

from typing import Any


def normalize(word: str) -> str:
    return "".join(ch for ch in word.lower() if ch.isalnum())


def force_align_tokens(script_words: list[str], timed: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Map timed words onto SCRIPT tokens. Caption text stays the script."""
    if not script_words:
        return []
    clock = [
        {
            "word": item.get("word") or "",
            "start": float(item.get("start") or 0),
            "duration": float(item.get("duration") or item.get("end", 0) - item.get("start", 0) or 0.08),
        }
        for item in timed
        if (item.get("word") or "").strip()
    ]
    if not clock:
        return []
    aligned: list[dict[str, Any]] = []
    cursor = 0
    last_end = clock[0]["start"]
    for token in script_words:
        needle = normalize(token)
        match = None
        look = cursor
        while look < len(clock) and look - cursor < 6:
            if needle and normalize(clock[look]["word"]) == needle:
                match = clock[look]
                cursor = look + 1
                break
            look += 1
        if match:
            aligned.append({"word": token, "start": match["start"], "duration": max(0.04, match["duration"])})
            last_end = match["start"] + max(0.04, match["duration"])
        else:
            aligned.append({"word": token, "start": last_end, "duration": 0.12})
            last_end += 0.12
    return aligned


def force_align_cues(cues: list[dict[str, Any]], timed: list[dict[str, Any]]) -> list[dict[str, Any]]:
    tokens: list[str] = []
    spans: list[tuple[int, int]] = []
    for cue in cues:
        words = [item.get("word") if isinstance(item, dict) else str(item) for item in (cue.get("words") or cue.get("text", "").split())]
        words = [word for word in words if str(word).strip()]
        if not words:
            words = (cue.get("text") or "").split()
        start = len(tokens)
        tokens.extend(words)
        spans.append((start, len(tokens)))
    mapped = force_align_tokens(tokens, timed)
    out: list[dict[str, Any]] = []
    for cue, (start, end) in zip(cues, spans):
        slice_ = mapped[start:end]
        next_cue = dict(cue)
        if slice_:
            window_start = float(cue.get("start") or slice_[0]["start"])
            window_end = window_start + max(0.04, float(cue.get("duration") or 0.04))
            fitted = []
            for word in slice_:
                word_start = min(max(word["start"], window_start), window_end - 0.04)
                word_end = min(window_end, word_start + max(0.04, word["duration"]))
                fitted.append({"word": word["word"], "start": word_start, "duration": max(0.04, word_end - word_start)})
            next_cue["words"] = fitted
        next_cue["text"] = cue.get("text") or " ".join(tokens[start:end])
        out.append(next_cue)
    return out
