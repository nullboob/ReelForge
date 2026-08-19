from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import httpx

from reelforge.cards import render_card
from reelforge.paths import blacklist_path
from reelforge.presets import pixel_size

GENERIC = (
    "office", "nature", "city aerial", "aerial city", "cityscape aerial",
    "handshake", "business meeting", "generic city", "stock office",
)


def specific_query(raw: str) -> str:
    lower = raw.lower()
    if any(needle in lower for needle in GENERIC):
        words = [word for word in "".join(ch if ch.isalpha() else " " for ch in raw).split() if len(word) > 4]
        for word in words:
            if not any(word.lower() in needle for needle in GENERIC):
                return f"{word} handheld documentary"
        return "handheld documentary texture"
    return raw


def load_blacklist(channel: str) -> set[int]:
    path = blacklist_path(channel)
    if not path.exists():
        return set()
    try:
        return set(json.loads(path.read_text(encoding="utf-8")))
    except Exception:
        return set()


def remember_clip(clip_id: int, channel: str) -> None:
    if clip_id <= 0:
        return
    ids = load_blacklist(channel)
    ids.add(clip_id)
    trimmed = sorted(ids)[-160:]
    blacklist_path(channel).write_text(json.dumps(trimmed), encoding="utf-8")


def gather(
    beats: list[dict[str, Any]],
    preset: dict[str, Any],
    aspect: str,
    work: Path,
    pexels_key: str | None,
    use_pexels: bool,
    channel_name: str,
    local_files: list[str] | None = None,
    on_progress=None,
) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]], list[str]]:
    assignments: dict[str, dict[str, Any]] = {}
    ledger: list[dict[str, Any]] = []
    warnings: list[str] = []
    size = pixel_size(aspect)
    locals_ = [Path(p) for p in (local_files or []) if Path(p).exists()]
    if use_pexels and not pexels_key:
        warnings.append("No Pexels key — stock video skipped. Add one in Settings.")

    for index, beat in enumerate(beats):
        if on_progress:
            on_progress(f"Fetching B-roll for beat {index + 1}/{len(beats)}")
        dest_card = work / f"beat-{index}.png"
        if locals_:
            src = locals_[index % len(locals_)]
            copied = work / f"local-{index}-{src.name}"
            shutil.copy2(src, copied)
            kind = "video" if src.suffix.lower() in {".mp4", ".mov", ".m4v"} else "image"
            assignments[beat["id"]] = {"kind": kind, "path": str(copied), "source": "user-local"}
            ledger.append(_entry(f"local-{index}", "visual", "user-local", "User provided", "Local file", beat["id"]))
            continue

        if use_pexels and pexels_key:
            clip = search_pexels(beat.get("unsplashQuery") or beat["text"], pexels_key, aspect != "16:9", index, load_blacklist(channel_name))
            if clip:
                dest_video = work / f"pexels-{index}.mp4"
                if download(clip["url"], dest_video):
                    remember_clip(clip["id"], channel_name)
                    assignments[beat["id"]] = {"kind": "video", "path": str(dest_video), "source": "pexels", "clipID": str(clip["id"])}
                    ledger.append(_entry(
                        f"pexels-{clip['id']}", "visual", "pexels", "Pexels License",
                        f"{clip['photographer']} / Pexels", beat["id"], str(clip["id"])
                    ))
                    continue

        render_card(beat["text"], dest_card, size, preset, channel_name, watermark=beat["start"] >= 1.5)
        assignments[beat["id"]] = {"kind": "card", "path": str(dest_card), "source": "reelforge-card"}
        ledger.append(_entry(f"card-{index}", "visual", "reelforge-card", "Generated in-app", "Styled card", beat["id"]))

    if len(assignments) < len(beats):
        warnings.append("Some beats used fallback cards so export could finish.")
    return assignments, ledger, warnings


def search_pexels(query: str, key: str, portrait: bool, index: int, excluding: set[int]) -> dict[str, Any] | None:
    cleaned = specific_query(query)
    params = urlencode({
        "query": cleaned,
        "per_page": 12,
        "page": 2 + (index % 3),
        "orientation": "portrait" if portrait else "landscape",
    })
    url = f"https://api.pexels.com/videos/search?{params}"
    try:
        with httpx.Client(timeout=12) as client:
            response = client.get(url, headers={"Authorization": key})
            if response.status_code != 200:
                return None
            videos = response.json().get("videos") or []
            unused = [video for video in videos if int(video.get("id") or 0) not in excluding]
            pick = (unused or videos or [None])[0]
            if not pick:
                return None
            files = pick.get("video_files") or []
            preferred = next((f for f in files if f.get("quality") == "hd"), files[0] if files else None)
            if not preferred or not preferred.get("link"):
                return None
            user = pick.get("user") or {}
            return {
                "id": int(pick.get("id") or 0),
                "url": preferred["link"],
                "photographer": user.get("name") or "Pexels contributor",
            }
    except Exception:
        return None


def download(url: str, dest: Path) -> bool:
    try:
        with httpx.Client(timeout=40, follow_redirects=True) as client:
            response = client.get(url)
            if response.status_code == 200 and len(response.content) > 400:
                dest.write_bytes(response.content)
                return True
    except Exception:
        return False
    return False


def _entry(entry_id: str, kind: str, source: str, license_name: str, credit: str, beat_id: str, clip_id: str | None = None) -> dict[str, Any]:
    return {
        "id": entry_id,
        "kind": kind,
        "source": source,
        "license": license_name,
        "clipID": clip_id,
        "credit": credit,
        "beatID": beat_id,
    }
