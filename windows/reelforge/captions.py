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
    cards = word_clock_cards(words, max_words_per_card, duration)
    return time_cards(cards, duration)


def cues_aligned_to_beats(script: dict[str, Any], storyboard: dict[str, Any], max_words: int) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for beat in storyboard["beats"]:
        text = beat["text"] or full_text(script)
        if beat.get("role") == "hook":
            slice_ = [hook_card(text, beat["duration"], max_words)]
        else:
            slice_ = align(text, beat["duration"], max_words)
        for cue in slice_:
            cue["start"] += beat["start"]
            cue["words"] = [
                {**word, "start": word["start"] + beat["start"]}
                for word in cue["words"]
            ]
            out.append(cue)
    for index, cue in enumerate(out):
        cue["id"] = f"cue-{index}"
    return exclusive_cues(out)


def hook_card(text: str, duration: float, max_words: int) -> dict[str, Any]:
    """One clean hook card for the full hook hold — never two lines in the first 1.5s."""
    words = tokenize(text)
    card: list[str] = []
    limit = max(1, min(max_words, 3))
    for word in words:
        card.append(word)
        punct = word[-1] in ".!?" if word else False
        if punct and len(card) >= 2:
            break
        if len(card) >= limit:
            break
    if not card:
        card = ["Watch this"]
    timed = time_cards([card], max(0.4, duration))
    return timed[0]


def tokenize(text: str) -> list[str]:
    return [part for part in text.split() if part]


def emphasis_index(words: list[str]) -> int:
    stop = {"the", "a", "an", "to", "of", "and", "or", "in", "on", "for", "is", "your", "this", "that"}
    best = 0
    best_len = 0
    for index, word in enumerate(words):
        clean = "".join(ch for ch in word.lower() if ch.isalnum())
        if clean in stop and len(words) > 1:
            continue
        if len(clean) >= best_len:
            best = index
            best_len = len(clean)
    return best


def word_clock_cards(words: list[str], max_words: int, duration: float, max_seconds: float = 2.0) -> list[list[str]]:
    capped = max(1, min(max_words, 4))
    cards = pack(words, capped)
    cards = prefer_two_to_four(cards, capped)
    return split_overlong(cards, duration, max_seconds)


def prefer_two_to_four(cards: list[list[str]], max_words: int) -> list[list[str]]:
    """2–4 words/page unless the style is single-word."""
    if max_words <= 1 or not cards:
        return cards
    out = [list(card) for card in cards if card]
    index = 0
    while index < len(out):
        if len(out[index]) == 1 and max_words >= 2:
            if index > 0 and len(out[index - 1]) < max_words:
                out[index - 1].extend(out[index])
                out.pop(index)
                continue
            if index + 1 < len(out) and len(out[index + 1]) < max_words:
                out[index + 1] = out[index] + out[index + 1]
                out.pop(index)
                continue
            if index > 0 and len(out[index - 1]) >= 2:
                stolen = out[index - 1].pop()
                out[index] = [stolen] + out[index]
        index += 1
    return out


def split_overlong(cards: list[list[str]], duration: float, max_seconds: float) -> list[list[str]]:
    if not cards or duration <= 0:
        return cards
    current = [list(card) for card in cards]
    for _ in range(12):
        weights = [float(max(1, len("".join(card)))) for card in current]
        total = sum(weights) or 1.0
        changed = False
        next_cards: list[list[str]] = []
        for index, card in enumerate(current):
            slice_ = duration * (weights[index] / total)
            if slice_ > max_seconds + 0.001 and len(card) > 1:
                mid = max(1, len(card) // 2)
                next_cards.append(card[:mid])
                next_cards.append(card[mid:])
                changed = True
            else:
                next_cards.append(card)
        current = next_cards
        if not changed:
            break
    return current


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
    raw = [duration * (weight / total) for weight in weights]
    cursor = 0.0
    cues_out: list[dict[str, Any]] = []
    for index, card in enumerate(cards):
        remaining = len(cards) - index
        leftover = duration - cursor
        if remaining == 1:
            d = leftover
        else:
            floor = 0.04 * (remaining - 1)
            d = min(raw[index], max(0.04, leftover - floor))
        d = max(0.04, d)
        words = word_timings(card, cursor, d)
        cues_out.append({
            "id": f"cue-{index}",
            "text": " ".join(card),
            "start": cursor,
            "duration": d,
            "words": words,
            "highlightWordIndex": emphasis_index(card),
        })
        cursor += d
    return exclusive_cues(cues_out)


def exclusive_cues(cues: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Cues replace each other. No two burned cards share [start, start+duration)."""
    if not cues:
        return []
    ordered = sorted((dict(cue) for cue in cues), key=lambda cue: (float(cue.get("start") or 0), -float(cue.get("duration") or 0)))
    out: list[dict[str, Any]] = []
    for index, cue in enumerate(ordered):
        start = float(cue.get("start") or 0)
        end = start + max(0.04, float(cue.get("duration") or 0.04))
        if index + 1 < len(ordered):
            nxt = float(ordered[index + 1].get("start") or 0)
            if nxt <= start:
                ordered[index + 1]["start"] = start + 0.04
                nxt = start + 0.04
            end = min(end, nxt)
        duration = max(0.04, end - start)
        words = fit_words_into_window(cue.get("words") or [], start, duration)
        if not words:
            words = word_timings((cue.get("text") or "").split() or [""], start, duration)
        next_cue = dict(cue)
        next_cue["start"] = start
        next_cue["duration"] = duration
        next_cue["words"] = words
        out.append(next_cue)
    return out


def cues_overlap(cues: list[dict[str, Any]], epsilon: float = 1e-4) -> list[tuple[str, str]]:
    hits: list[tuple[str, str]] = []
    for index, left in enumerate(cues):
        left_start = float(left["start"])
        left_end = left_start + float(left["duration"])
        for right in cues[index + 1 :]:
            right_start = float(right["start"])
            right_end = right_start + float(right["duration"])
            if left_start < right_end - epsilon and right_start < left_end - epsilon:
                hits.append((left.get("id") or str(index), right.get("id") or ""))
    return hits


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


def fit_words_into_window(words: list[dict[str, Any]], start: float, duration: float) -> list[dict[str, Any]]:
    tokens = []
    for word in words:
        if isinstance(word, dict):
            token = (word.get("word") or "").strip()
            if token:
                tokens.append(token)
        elif str(word).strip():
            tokens.append(str(word).strip())
    if not tokens:
        return []
    return word_timings(tokens, start, duration)


def apply_tts_words(cues: list[dict[str, Any]], tts_words: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Map timed words onto SCRIPT card text. Never replace caption text with Whisper soup."""
    return force_align_to_script(cues, tts_words)


def force_align_to_script(cues: list[dict[str, Any]], timed_words: list[dict[str, Any]]) -> list[dict[str, Any]]:
    from reelforge.align import force_align_cues
    return exclusive_cues(force_align_cues(cues, timed_words))


def safe_area(width: float, height: float) -> tuple[float, float, float, float]:
    portrait = width < height
    left = width * 0.08
    right = width * (0.18 if portrait else 0.08)
    bottom = height * 0.18
    top = height * 0.12
    return left, bottom, max(1.0, width - left - right), max(1.0, height - bottom - top)


def caption_band(width: float, height: float) -> tuple[float, float, float, float]:
    """Caption block for 1080×1920 lives around y 700–1360. Other sizes scale."""
    left, _, box_w, _ = safe_area(width, height)
    top = height * (700.0 / 1920.0)
    bottom = height * (1360.0 / 1920.0)
    return left, top, box_w, max(1.0, bottom - top)


def caption_center_y(height: float) -> float:
    return height * ((700.0 + 1360.0) / 2.0 / 1920.0)
