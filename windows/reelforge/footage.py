from __future__ import annotations

import json
import re
import shutil
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import httpx

from reelforge.cards import render_card, render_painted
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


def local_kind(beat_index: int, local_mode: str) -> str:
    if local_mode == "local-quality":
        return "wan" if beat_index <= 2 else "qwen"
    return "ltx" if beat_index == 0 else "qwen"


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
    local_mode: str = "stock-first",
    comfy_url: str | None = None,
    comfy_settings: dict[str, Any] | None = None,
) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]], list[str], bool]:
    assignments: dict[str, dict[str, Any]] = {}
    ledger: list[dict[str, Any]] = []
    warnings: list[str] = []
    size = pixel_size(aspect)
    locals_ = [Path(p) for p in (local_files or []) if Path(p).exists()]
    mode = local_mode if local_mode in {"stock-first", "local-fast", "local-quality"} else "stock-first"
    has_stock_key = bool((use_pexels and pexels_key) or (use_pixabay and pixabay_key))
    if use_pexels and not pexels_key:
        warnings.append("No Pexels key — stock video skipped unless Pixabay is set.")
    if not has_stock_key and not locals_:
        warnings.append("No stock key and no local files. Instant pack uses painted full-bleed art unless a GPU model is Ready.")

    used_clip_ids: set[int] = set()
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
        excluding = load_blacklist(channel_name) | used_clip_ids
        portrait = aspect != "16:9"
        try_stock_first = mode == "stock-first"

        if try_stock_first and _assign_stock(
            beat, index, query, work, aspect, portrait, excluding, channel_name,
            use_pexels, pexels_key, use_pixabay, pixabay_key, assignments, ledger,
            used_clip_ids,
        ):
            continue
        if use_local_models and _assign_native(
            beat, index, query, work, aspect, preset, mode, models_dir, on_progress,
            assignments, ledger, warnings,
        ):
            continue
        if not try_stock_first and _assign_stock(
            beat, index, query, work, aspect, portrait, excluding, channel_name,
            use_pexels, pexels_key, use_pixabay, pixabay_key, assignments, ledger,
            used_clip_ids,
        ):
            continue

        painted = work / f"painted-{index}.png"
        try:
            render_painted(beat["text"], painted, size, preset, channel_name)
            assignments[beat["id"]] = {"kind": "image", "path": str(painted), "source": "painted"}
            ledger.append(_entry(f"painted-{index}", "visual", "painted", "Generated in-app", "Painted art", beat["id"]))
            continue
        except Exception:
            pass
        render_card(beat["text"], dest_card, size, preset, channel_name, watermark=beat["start"] >= 1.5)
        assignments[beat["id"]] = {"kind": "card", "path": str(dest_card), "source": "reelforge-card"}
        ledger.append(_entry(f"card-{index}", "visual", "reelforge-card", "Generated in-app", "Styled card", beat["id"]))
        card_count += 1

    cards_only = card_count == len(beats) and len(beats) > 0 and not locals_
    if cards_only:
        warnings.append("Export used styled cards for every beat — not a finished Short unless you opted into cards.")
    elif any((assignments.get(beat["id"]) or {}).get("source") == "painted" for beat in beats):
        warnings.append("Used painted full-bleed art. Add a free Pexels key for real B-roll.")
    elif card_count:
        warnings.append(f"{card_count} beat(s) fell back to cards after stock and local gen missed.")
    return assignments, ledger, warnings, cards_only


def _assign_stock(
    beat, index, query, work, aspect, portrait, excluding, channel_name,
    use_pexels, pexels_key, use_pixabay, pixabay_key, assignments, ledger,
    used_clip_ids,
) -> bool:
    if use_pexels and pexels_key:
        clip = search_pexels(query, pexels_key, portrait, index, excluding)
        if clip:
            dest_video = work / f"pexels-{index}.mp4"
            if download(clip["url"], dest_video):
                remember_clip(clip["id"], channel_name)
                used_clip_ids.add(int(clip["id"]))
                assignments[beat["id"]] = {"kind": "video", "path": str(dest_video), "source": "pexels", "clipID": str(clip["id"])}
                ledger.append(_entry(
                    f"pexels-{clip['id']}", "visual", "pexels", "Pexels License",
                    f"{clip['photographer']} / Pexels", beat["id"], str(clip["id"])
                ))
                return True
    if use_pixabay and pixabay_key:
        clip = search_pixabay(query, pixabay_key, portrait, index, excluding)
        if clip:
            dest_video = work / f"pixabay-{index}.mp4"
            if download(clip["url"], dest_video):
                remember_clip(clip["id"], channel_name)
                used_clip_ids.add(int(clip["id"]))
                assignments[beat["id"]] = {"kind": "video", "path": str(dest_video), "source": "pixabay", "clipID": str(clip["id"])}
                ledger.append(_entry(
                    f"pixabay-{clip['id']}", "visual", "pixabay", "Pixabay License",
                    f"{clip['user']} / Pixabay", beat["id"], str(clip["id"])
                ))
                return True
    return False


def _assign_native(
    beat, index, query, work, aspect, preset, mode, models_dir, on_progress,
    assignments, ledger, warnings,
) -> bool:
    from reelforge import infer
    kind = local_kind(index, mode)
    style = preset.get("aiImageStyleSuffix") or ""
    prompt = f"{query}, vertical {aspect} photoreal footage, natural light, no text, no captions, no logo. {style}".strip()
    seconds = min(4.0, max(2.0, float(beat.get("duration") or 3)))
    if kind in {"ltx", "wan"}:
        dest_video = work / f"{kind}-{index}.mp4"
        if on_progress:
            on_progress(f"Local {kind.upper()} for beat {index + 1}")
        ok = infer.generate_video(prompt, dest_video, aspect=aspect, seconds=seconds, models_dir=models_dir)
        if not ok and kind == "wan":
            ok = infer.generate_wan_video(prompt, dest_video)
        if ok:
            credit = "LTX-2.3 local" if kind == "ltx" else "Wan 2.2 local"
            assignments[beat["id"]] = {"kind": "video", "path": str(dest_video), "source": kind}
            ledger.append(_entry(f"{kind}-{index}", "visual", kind, "Generated in-app", credit, beat["id"]))
            return True
        warnings.append(f"GPU video missed beat {index + 1} — trying a still.")
    dest_still = work / f"qwen-{index}.png"
    if on_progress:
        on_progress(f"Local Qwen still for beat {index + 1}")
    if infer.generate_image(prompt, dest_still, aspect=aspect, models_dir=models_dir):
        assignments[beat["id"]] = {"kind": "image", "path": str(dest_still), "source": "qwen"}
        ledger.append(_entry(f"qwen-{index}", "visual", "qwen", "Generated in-app", "Qwen Image local", beat["id"]))
        return True
    return False


def _assign_comfy(
    beat, index, query, work, aspect, preset, mode, comfy_url, comfy_settings,
    comfy_status, models_dir, on_progress, assignments, ledger, warnings,
) -> bool:
    from reelforge import comfy
    from reelforge import infer
    kind = local_kind(index, mode)
    prompt = comfy.render_prompt(beat.get("text") or query, preset.get("aiImageStyleSuffix") or "", aspect)
    seconds = min(4.0, max(2.0, float(beat.get("duration") or 3)))
    if (comfy_status or {}).get("up"):
        if kind in {"ltx", "wan"}:
            dest_video = work / f"{kind}-{index}.mp4"
            if on_progress:
                on_progress(f"ComfyUI {kind.upper()} for beat {index + 1}")
            if comfy.generate_video(prompt, dest_video, kind=kind, aspect=aspect, seconds=seconds, url=comfy_url, settings=comfy_settings):
                credit = "LTX-2.3 local" if kind == "ltx" else "Wan 2.2 local"
                assignments[beat["id"]] = {"kind": "video", "path": str(dest_video), "source": kind}
                ledger.append(_entry(f"{kind}-{index}", "visual", kind, "Generated in-app", credit, beat["id"]))
                return True
        dest_still = work / f"qwen-{index}.png"
        if on_progress:
            on_progress(f"ComfyUI Qwen still for beat {index + 1}")
        if comfy.generate_image(prompt, dest_still, aspect=aspect, url=comfy_url, settings=comfy_settings):
            assignments[beat["id"]] = {"kind": "image", "path": str(dest_still), "source": "qwen"}
            ledger.append(_entry(f"qwen-{index}", "visual", "qwen", "Generated in-app", "Qwen Image local", beat["id"]))
            return True
        warnings.append(f"ComfyUI missed beat {index + 1} ({kind}).")
    if kind == "ltx" and infer.generate_video(prompt, work / f"ltx-{index}.mp4", aspect=aspect, seconds=seconds, models_dir=models_dir):
        dest = work / f"ltx-{index}.mp4"
        assignments[beat["id"]] = {"kind": "video", "path": str(dest), "source": "ltx"}
        ledger.append(_entry(f"ltx-{index}", "visual", "ltx", "Generated in-app", "LTX-2.3 local", beat["id"]))
        return True
    if infer.generate_image(prompt, work / f"qwen-{index}.png", aspect=aspect, models_dir=models_dir):
        dest = work / f"qwen-{index}.png"
        assignments[beat["id"]] = {"kind": "image", "path": str(dest), "source": "qwen"}
        ledger.append(_entry(f"qwen-{index}", "visual", "qwen", "Generated in-app", "Qwen Image local", beat["id"]))
        return True
    return False


def first_unused(items: list[dict[str, Any]], excluding: set[int]) -> dict[str, Any] | None:
    unused = [item for item in items if int(item.get("id") or 0) > 0 and int(item.get("id") or 0) not in excluding]
    return unused[0] if unused else None


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
            pick = first_unused(videos, excluding)
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
            pick = first_unused(hits, excluding)
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
