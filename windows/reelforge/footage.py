from __future__ import annotations

import json
import re
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

STOP = {
    "this", "that", "with", "from", "your", "have", "will", "stop", "just",
    "they", "them", "then", "than", "what", "when", "where", "about", "after",
    "before", "because", "could", "should", "would", "there", "their", "these",
    "those", "into", "over", "under", "more", "most", "some", "very", "also",
}


def specific_query(raw: str) -> str:
    lower = raw.lower()
    nouns = [word for word in re.findall(r"[A-Za-z]{4,}", raw) if word.lower() not in STOP]
    if nouns:
        return " ".join(nouns[:3]) + " handheld closeup"
    if any(needle in lower for needle in GENERIC):
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
    pixabay_key: str | None = None,
    use_pixabay: bool = True,
    use_local_models: bool = True,
    models_dir: str | None = None,
) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]], list[str], bool]:
    assignments: dict[str, dict[str, Any]] = {}
    ledger: list[dict[str, Any]] = []
    warnings: list[str] = []
    size = pixel_size(aspect)
    locals_ = [Path(p) for p in (local_files or []) if Path(p).exists()]
    has_stock_key = bool((use_pexels and pexels_key) or (use_pixabay and pixabay_key))
    if use_pexels and not pexels_key:
        warnings.append("No Pexels key — stock video skipped unless Pixabay is set.")
    if not has_stock_key and not locals_:
        warnings.append(
            "CARDS ONLY: no Pexels/Pixabay key and no local files. "
            "Point Model Manager at Ready weights, or this will look like a slide deck."
        )

    card_count = 0
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

        query = specific_query(beat.get("unsplashQuery") or beat.get("text") or "")
        excluding = load_blacklist(channel_name)
        portrait = aspect != "16:9"

        if use_pexels and pexels_key:
            clip = search_pexels(query, pexels_key, portrait, index, excluding)
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

        if use_pixabay and pixabay_key:
            clip = search_pixabay(query, pixabay_key, portrait, index, excluding)
            if clip:
                dest_video = work / f"pixabay-{index}.mp4"
                if download(clip["url"], dest_video):
                    remember_clip(clip["id"], channel_name)
                    assignments[beat["id"]] = {"kind": "video", "path": str(dest_video), "source": "pixabay", "clipID": str(clip["id"])}
                    ledger.append(_entry(
                        f"pixabay-{clip['id']}", "visual", "pixabay", "Pixabay License",
                        f"{clip['user']} / Pixabay", beat["id"], str(clip["id"])
                    ))
                    continue

        if use_local_models:
            from reelforge import infer
            prompt = f"{beat.get('text') or query}. {preset.get('aiImageStyleSuffix') or ''}"
            if index == 0 or preset.get("aiVideoEnabled"):
                dest_video = work / f"ltx-{index}.mp4"
                if on_progress:
                    on_progress(f"Trying in-app LTX for beat {index + 1}/{len(beats)}")
                if infer.generate_video(prompt, dest_video, aspect=aspect, seconds=min(4.0, float(beat.get("duration") or 3)), models_dir=models_dir):
                    assignments[beat["id"]] = {"kind": "video", "path": str(dest_video), "source": "ltx"}
                    ledger.append(_entry(f"ltx-{index}", "visual", "ltx", "Generated in-app", "LTX distilled", beat["id"]))
                    continue
            dest_still = work / f"qwen-{index}.png"
            if on_progress:
                on_progress(f"Trying in-app Qwen still for beat {index + 1}/{len(beats)}")
            if infer.generate_image(prompt, dest_still, aspect=aspect, models_dir=models_dir):
                assignments[beat["id"]] = {"kind": "image", "path": str(dest_still), "source": "qwen"}
                ledger.append(_entry(f"qwen-{index}", "visual", "qwen", "Generated in-app", "Qwen Image", beat["id"]))
                continue

        render_card(beat["text"], dest_card, size, preset, channel_name, watermark=beat["start"] >= 1.5)
        assignments[beat["id"]] = {"kind": "card", "path": str(dest_card), "source": "reelforge-card"}
        ledger.append(_entry(f"card-{index}", "visual", "reelforge-card", "Generated in-app", "Styled card", beat["id"]))
        card_count += 1

    cards_only = card_count == len(beats) and len(beats) > 0 and not locals_
    if cards_only:
        warnings.append("Export used styled cards for every beat — not a finished Short unless you opted into cards.")
    elif card_count:
        warnings.append(f"{card_count} beat(s) fell back to cards after stock search missed.")
    return assignments, ledger, warnings, cards_only


def search_pexels(query: str, key: str, portrait: bool, index: int, excluding: set[int]) -> dict[str, Any] | None:
    params = urlencode({
        "query": query,
        "per_page": 15,
        "page": 1 + (index % 4),
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


def search_pixabay(query: str, key: str, portrait: bool, index: int, excluding: set[int]) -> dict[str, Any] | None:
    params = urlencode({
        "key": key,
        "q": query,
        "per_page": 12,
        "page": 1 + (index % 3),
        "video_type": "film",
        "safesearch": "true",
        "orientation": "vertical" if portrait else "horizontal",
    })
    url = f"https://pixabay.com/api/videos/?{params}"
    try:
        with httpx.Client(timeout=12) as client:
            response = client.get(url)
            if response.status_code != 200:
                return None
            hits = response.json().get("hits") or []
            unused = [hit for hit in hits if int(hit.get("id") or 0) not in excluding]
            pick = (unused or hits or [None])[0]
            if not pick:
                return None
            videos = pick.get("videos") or {}
            preferred = videos.get("large") or videos.get("medium") or videos.get("small") or {}
            link = preferred.get("url")
            if not link:
                return None
            return {
                "id": int(pick.get("id") or 0),
                "url": link,
                "user": pick.get("user") or "Pixabay contributor",
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
