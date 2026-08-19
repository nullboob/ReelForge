from __future__ import annotations

import re
from typing import Any


SYNTHETIC_REMINDER = (
    "Before you upload: tick YouTube’s altered / synthetic content checkbox "
    "if the voice or visuals are generated."
)


def write_pack(
    topic: str,
    script: dict[str, Any],
    storyboard: dict[str, Any],
    preset: dict[str, Any],
    channel: dict[str, Any],
    series: str | None,
    target: str,
    credits: list[str],
) -> dict[str, Any]:
    title = make_title(topic, script, series)
    chapters = chapters_from(storyboard)
    description = make_description(script, chapters, channel, series, target, credits)
    tags = make_tags(topic, preset, channel, series)
    hashtags = ["#" + tag.replace(" ", "") for tag in tags[:4]]
    return {
        "title": title,
        "description": description,
        "tags": tags,
        "hashtags": hashtags,
        "chapters": chapters,
        "suggestedFilename": f"{slugify(title)}.mp4",
        "source": script.get("source", "template"),
        "credits": credits,
        "syntheticReminder": SYNTHETIC_REMINDER,
        "thumbnailPaths": [],
        "thumbnailPath": None,
        "srtPath": None,
    }


def thumbnail_headline(hook: str, max_words: int = 6) -> str:
    words = [part for part in hook.split() if part]
    if not words:
        return "Watch this"
    out: list[str] = []
    for word in words[: min(6, max(4, max_words))]:
        out.append(word)
        if word[-1:] in ".!?" and len(out) >= 3:
            break
        if len(out) >= 6:
            break
    return " ".join(out)


def chapters_from(storyboard: dict[str, Any]) -> list[dict[str, Any]]:
    marks = []
    for index, beat in enumerate(storyboard.get("beats") or []):
        raw = " ".join(beat["text"].split()[:8])
        start = 0.0 if index == 0 else float(beat["start"])
        marks.append({"id": beat["id"], "start": start, "title": raw, "timestamp": timestamp(start)})
    if marks and marks[0]["start"] != 0:
        marks[0]["start"] = 0
        marks[0]["timestamp"] = "0:00"
    return marks


def make_title(topic: str, script: dict[str, Any], series: str | None) -> str:
    base = script.get("hook") or topic
    if len(base) > 68:
        base = topic.strip()
    if series:
        mixed = f"{series}: {base}"
        if len(mixed) <= 70:
            base = mixed
    return clip(base.replace('"', ""), 70)


def make_description(
    script: dict[str, Any],
    chapters: list[dict[str, Any]],
    channel: dict[str, Any],
    series: str | None,
    target: str,
    credits: list[str],
) -> str:
    hook = (script.get("hook") or "").strip()
    second = (script.get("body") or [script.get("cta", "")])[0]
    lines = [hook]
    if len(hook) < 140:
        lines.append(second)
    lines.append("")
    if series:
        lines.append(f"Series: {series}")
    name = channel.get("name") or ""
    if name:
        lines.append(f"{name} — new videos for people building in public.")
    lines.append("")
    lines.append("Chapters")
    for chapter in chapters[:12]:
        lines.append(f"{chapter['timestamp']} {chapter['title']}")
    lines.append("")
    lines.append(script.get("cta") or "")
    if target == "longForm":
        lines.append("If this helped, subscribe and drop the next topic in the comments.")
    else:
        lines.append("More shorts on the channel. Subscribe if this saved you a search.")
    if credits:
        lines.append("")
        lines.append("Credits")
        lines.extend(credits[:12])
    lines.append("")
    lines.append(SYNTHETIC_REMINDER)
    return "\n".join(lines)


def make_tags(topic: str, preset: dict[str, Any], channel: dict[str, Any], series: str | None) -> list[str]:
    tags = [
        "youtube shorts",
        "faceless youtube",
        str(preset.get("name", "")).lower(),
        "how to",
        "explained",
    ]
    tags.extend(word.lower() for word in re.findall(r"[A-Za-z]{4,}", topic)[:4])
    if series:
        tags.append(series.lower())
    if channel.get("name"):
        tags.append(channel["name"].lower())
    seen: set[str] = set()
    out = []
    for tag in tags:
        if tag and tag not in seen:
            seen.add(tag)
            out.append(tag)
    return out[:12]


def clip(text: str, limit: int) -> str:
    trimmed = text.strip()
    if len(trimmed) <= limit:
        return trimmed
    return trimmed[: limit - 1].rstrip() + "…"


def slugify(text: str) -> str:
    parts = [part for part in re.split(r"[^A-Za-z0-9]+", text.lower()) if part][:8]
    return "-".join(parts) or "reelforge-video"


def timestamp(start: float) -> str:
    total = max(0, int(round(start)))
    return f"{total // 60}:{total % 60:02d}"
