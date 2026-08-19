from __future__ import annotations

import re
from typing import Any

from reelforge.hooks import is_forbidden_open


class StoryboardError(ValueError):
    def __init__(self, message: str = "The first beat must be a hook scene — on-screen claim, VO start, picture change. No logo open."):
        super().__init__(message)


def build(script: dict[str, Any], preset: dict[str, Any], duration: float) -> dict[str, Any]:
    target = max(8.0, float(duration))
    numbered = bool(preset.get("titleCard", {}).get("numbered"))
    raw = raw_units(script, numbered)
    raw = fit_count(raw, preset.get("pace", {}), target)

    weights = [float(max(8, len(unit["text"]))) for unit in raw]
    weight_sum = sum(weights) or 1.0
    min_c = float(preset.get("pace", {}).get("cutMinSec", 0.8))
    max_c = float(preset.get("pace", {}).get("cutMaxSec", 1.8))
    durations = [min(max(target * (w / weight_sum), min_c), max_c) for w in weights]
    clamped_sum = sum(durations)
    if clamped_sum > 0:
        scale = target / clamped_sum
        durations = [d * scale for d in durations]
    if durations:
        durations[-1] = max(0.4, durations[-1] + (target - sum(durations)))
    pin_hook_hold(durations, raw, target)

    queries = preset.get("footage", {}).get("unsplashQueries") or ["cinematic texture"]
    beats = []
    cursor = 0.0
    for index, unit in enumerate(raw):
        beat_duration = durations[index]
        beats.append({
            "id": f"beat-{index}",
            "index": index,
            "role": unit["role"],
            "text": unit["text"],
            "start": cursor,
            "duration": beat_duration,
            "unsplashQuery": query_for_beat(unit["text"], queries, index),
            "stepNumber": unit.get("step"),
        })
        cursor += beat_duration

    if not beats or beats[0]["role"] != "hook":
        raise StoryboardError()
    if is_forbidden_open(beats[0]["text"]):
        raise StoryboardError()
    return {"beats": beats, "duration": cursor, "presetID": preset["id"]}


def appending_outro(board: dict[str, Any], channel_name: str, enabled: bool) -> dict[str, Any]:
    if not enabled:
        return board
    beats = list(board["beats"])
    duration = float(board["duration"])
    beats.append({
        "id": "outro",
        "index": len(beats),
        "role": "cta",
        "text": f"Subscribe to {channel_name}." if channel_name else "Subscribe for the next one.",
        "start": duration,
        "duration": 2.4,
        "unsplashQuery": "dark studio subscribe",
        "stepNumber": None,
    })
    return {"beats": beats, "duration": duration + 2.4, "presetID": board["presetID"]}


def rescale(board: dict[str, Any], duration: float) -> dict[str, Any]:
    current = max(0.01, float(board["duration"]))
    scale = duration / current
    cursor = 0.0
    beats = []
    for beat in board["beats"]:
        next_beat = dict(beat)
        next_beat["start"] = cursor
        next_beat["duration"] = beat["duration"] * scale
        cursor += next_beat["duration"]
        beats.append(next_beat)
    return {"beats": beats, "duration": cursor, "presetID": board["presetID"]}


def raw_units(script: dict[str, Any], numbered: bool) -> list[dict[str, Any]]:
    units: list[dict[str, Any]] = []
    hook = (script.get("hook") or "").strip()
    if hook:
        units.append({"role": "hook", "text": hook, "step": 0 if numbered else None})
    for i, line in enumerate(script.get("body") or []):
        if line.strip():
            units.append({"role": "body", "text": line, "step": (i + 1) if numbered else None})
    cta = (script.get("cta") or "").strip()
    if cta:
        units.append({"role": "cta", "text": cta, "step": None})
    if not units:
        units.append({"role": "hook", "text": "Stay with this for a second.", "step": 1 if numbered else None})
    return units


def fit_count(units: list[dict[str, Any]], pace: dict[str, Any], duration: float) -> list[dict[str, Any]]:
    result = list(units)
    min_c = float(pace.get("cutMinSec", 0.8))
    max_c = float(pace.get("cutMaxSec", 1.8))
    avg = max(0.6, (min_c + max_c) / 2)
    target_count = min(max(int(round(duration / avg)), 3), 16)
    while len(result) * min_c > duration + 0.01 and len(result) > 3:
        result = merge_shortest_body(result)
    guard = 0
    while len(result) < target_count and len(result) * max_c < duration and guard < 12:
        idx = longest_splittable_index(result)
        if idx is None:
            break
        result = split_unit(result, idx)
        guard += 1
    return result


def merge_shortest_body(units: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if len(units) <= 1:
        return units
    best = -1
    best_len = 10**9
    for i in range(len(units) - 1):
        if units[i]["role"] == "hook":
            continue
        combined = len(units[i]["text"]) + len(units[i + 1]["text"])
        if combined < best_len:
            best_len = combined
            best = i
    if best < 0:
        best = max(0, len(units) - 2)
    next_units = [dict(u) for u in units]
    next_units[best]["text"] = next_units[best]["text"].strip() + " " + next_units[best + 1]["text"]
    del next_units[best + 1]
    return next_units


def longest_splittable_index(units: list[dict[str, Any]]) -> int | None:
    best = None
    best_count = 0
    for i, unit in enumerate(units):
        parts = split_text(unit["text"])
        if len(parts) >= 2 and len(unit["text"]) > best_count:
            best = i
            best_count = len(unit["text"])
    return best


def split_unit(units: list[dict[str, Any]], index: int) -> list[dict[str, Any]]:
    parts = split_text(units[index]["text"])
    if len(parts) < 2:
        return units
    mid = len(parts) // 2
    next_units = [dict(u) for u in units]
    next_units[index]["text"] = " ".join(parts[:mid])
    inserted = dict(units[index])
    inserted["text"] = " ".join(parts[mid:])
    next_units.insert(index + 1, inserted)
    return next_units


def pin_hook_hold(durations: list[float], units: list[dict[str, Any]], target: float) -> None:
    try:
        index = next(i for i, unit in enumerate(units) if unit["role"] == "hook")
    except StopIteration:
        return
    need = 1.5
    if durations[index] + 0.001 >= need:
        return
    steal = need - durations[index]
    durations[index] = need
    for j in range(len(durations) - 1, -1, -1):
        if j == index:
            continue
        available = durations[j] - 0.45
        if available <= 0.01:
            continue
        take = min(available, steal)
        durations[j] -= take
        steal -= take
        if steal <= 0.001:
            break
    if durations:
        durations[-1] = max(0.4, durations[-1] + (target - sum(durations)))


def split_text(text: str) -> list[str]:
    sentences = [part.strip() for part in re.split(r"[.!?]", text) if part.strip()]
    if len(sentences) >= 2:
        return sentences
    emdash = [part.strip() for part in text.split(" — ") if part.strip()]
    if len(emdash) >= 2:
        return emdash
    commas = [part.strip() for part in text.split(",") if part.strip()]
    if len(commas) >= 2 and all(len(part.split()) >= 3 for part in commas):
        return commas
    for token in (" but ", " and then ", " so ", " because "):
        idx = text.lower().find(token)
        if idx > 0:
            left = text[:idx].strip()
            right = text[idx + len(token):].strip()
            if len(left.split()) >= 3 and len(right.split()) >= 3:
                return [left, right]
    return [text]


def query_for_beat(text: str, hints: list[str], index: int) -> str:
    hint = hints[index % len(hints)]
    keyword = interesting_keyword(text)
    if keyword and len(keyword) > 3:
        return f"{hint} {keyword}"
    return hint


def interesting_keyword(text: str) -> str | None:
    stop = {
        "this", "that", "with", "from", "your", "about", "have", "just", "then",
        "than", "they", "them", "what", "when", "stop", "here", "most", "people",
        "reason", "step", "fact", "feature", "meet", "quick", "brief",
    }
    for word in re.findall(r"[A-Za-z]+", text.lower()):
        if len(word) > 4 and word not in stop:
            return word
    return None
