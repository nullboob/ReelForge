from __future__ import annotations

from typing import Any

from reelforge.presets import max_caption_words


def cues(script: dict[str, Any], duration: float, max_words: int, storyboard: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    if storyboard and storyboard.get("beats"):
        return cues_aligned_to_beats(script, storyboard, max_words)
    return align(full_text(script), duration, max_words)


def cues_for_preset(script: dict[str, Any], storyboard: dict[str, Any], preset: dict[str, Any]) -> list[dict[str, Any]]:
    return cues(script, storyboard["duration"], max_caption_words(preset), storyboard)


def align(text: str, duration: float, max_words_per_card: int) -> list[dict[str, Any]]:
    words = tokenize(text)
    if not words or duration <= 0:
        return []
    cards = pack(words, max(1, min(max_words_per_card, 12)))
    return time_cards(cards, duration)


def cues_aligned_to_beats(script: dict[str, Any], storyboard: dict[str, Any], max_words: int) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for beat in storyboard["beats"]:
        text = beat["text"] or full_text(script)
        for cue in align(text, beat["duration"], max_words):
            cue["start"] += beat["start"]
            cue["words"] = [
                {**word, "start": word["start"] + beat["start"]}
                for word in cue["words"]
            ]
            out.append(cue)
    for index, cue in enumerate(out):
        cue["id"] = f"cue-{index}"
    return out


def tokenize(text: str) -> list[str]:
    return [part for part in text.split() if part]


def pack(words: list[str], max_words: int) -> list[list[str]]:
    cards: list[list[str]] = []
    current: list[str] = []
    for word in words:
        current.append(word)
        punct = word[-1] in ".!?,;:" if word else False
        if len(current) >= max_words or (punct and len(current) >= 2):
            cards.append(current)
            current = []
    if current:
        cards.append(current)
    return cards


def time_cards(cards: list[list[str]], duration: float) -> list[dict[str, Any]]:
    weights = [float(max(1, len("".join(card)))) for card in cards]
    total = sum(weights) or 1.0
    cursor = 0.0
    cues_out: list[dict[str, Any]] = []
    for index, card in enumerate(cards):
        d = duration * (weights[index] / total)
        d = max(0.28, d)
        if index == len(cards) - 1:
            d = max(0.28, duration - cursor)
        words = word_timings(card, cursor, d)
        cues_out.append({
            "id": f"cue-{index}",
            "text": " ".join(card),
            "start": cursor,
            "duration": d,
            "words": words,
            "highlightWordIndex": min(len(card) - 1, 1) if len(card) > 2 else 0,
        })
        cursor += d
    return cues_out


def word_timings(words: list[str], start: float, duration: float) -> list[dict[str, Any]]:
    weights = [float(max(1, len(word))) for word in words]
    total = sum(weights) or 1.0
    cursor = start
    timed = []
    for index, word in enumerate(words):
        d = duration * (weights[index] / total)
        timed.append({"word": word, "start": cursor, "duration": d})
        cursor += d
    return timed


def full_text(script: dict[str, Any]) -> str:
    parts = [script.get("hook", "")] + list(script.get("body") or []) + [script.get("cta", "")]
    return " ".join(part.strip() for part in parts if part and part.strip())


def srt_string(cues_list: list[dict[str, Any]]) -> str:
    blocks = []
    for index, cue in enumerate(cues_list):
        end = cue["start"] + cue["duration"]
        blocks.append(f"{index + 1}\n{stamp(cue['start'])} --> {stamp(end)}\n{cue['text']}")
    return ("\n\n".join(blocks) + ("\n" if blocks else ""))


def stamp(seconds: float) -> str:
    clamped = max(0.0, seconds)
    hours = int(clamped) // 3600
    minutes = (int(clamped) % 3600) // 60
    secs = int(clamped) % 60
    millis = int((clamped - int(clamped)) * 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"


def safe_area(width: float, height: float) -> tuple[float, float, float, float]:
    portrait = width < height
    left = width * 0.08
    right = width * (0.18 if portrait else 0.08)
    bottom = height * 0.15
    top = height * 0.15
    return left, bottom, max(1.0, width - left - right), max(1.0, height - bottom - top)
