from __future__ import annotations

import json
from pathlib import Path
from typing import Any

GAP_DB = -8.0
SPEECH_DB = -18.0
ENCODER_WHITELIST = ["h264_nvenc", "h264_qsv", "h264_amf", "h264_videotoolbox", "libx264"]


def gap_linear() -> float:
    return 10 ** (GAP_DB / 20.0)


def build(
    beats: list[dict[str, Any]],
    assignments: dict[str, dict[str, Any]],
    voice_path: Path,
    music_path: Path,
    duration: float,
    width: int,
    height: int,
    preset: dict[str, Any],
    ass_path: Path,
    caption_style: dict[str, Any] | None,
    fps: int = 30,
) -> dict[str, Any]:
    footage = preset.get("footage") or {}
    grade = preset.get("colorGrade") or {}
    clips: list[dict[str, Any]] = []
    for index, beat in enumerate(beats):
        assignment = assignments.get(beat["id"]) or {}
        role = beat.get("role") or ("hook" if index == 0 else "body")
        clips.append({
            "beatID": beat["id"],
            "role": role,
            "start": float(beat.get("start") or 0),
            "duration": float(beat.get("duration") or 0.4),
            "source": str(assignment.get("path") or ""),
            "kind": assignment.get("kind") or "card",
            "sourceID": assignment.get("clipID"),
            "kenBurns": bool(footage.get("kenBurns")) and assignment.get("kind") in {"image", "card"},
            "zoomPulse": bool(footage.get("zoomPulse")),
            "punchIn": 1.12 if role == "hook" or index == 0 else None,
            "transitionIn": "hardCut" if role == "hook" or index == 0 else (preset.get("pace") or {}).get("transition") or "hardCut",
        })
    style = caption_style or {}
    return {
        "version": 1,
        "width": width,
        "height": height,
        "fps": fps,
        "duration": float(duration),
        "audioMaster": True,
        "voice": {"path": str(voice_path), "start": 0.0, "duration": float(duration)},
        "music": {"path": str(music_path), "start": 0.0, "duration": float(duration)},
        "duck": {"gapDb": GAP_DB, "speechDb": SPEECH_DB, "mode": "sidechaincompress"},
        "captions": {
            "assPath": str(ass_path),
            "renderer": style.get("renderer") or "ass",
            "styleID": style.get("id") or "",
        },
        "grade": {
            "contrast": float(grade.get("contrast") or 1.08),
            "saturation": float(grade.get("saturation") or 1.12),
            "warmth": float(grade.get("warmth") or 0),
            "vignette": float(grade.get("vignette") or 0.35),
            "unsharp": True,
            "grain": bool(footage.get("overlayGrain")),
        },
        "hook": {"punchIn": 1.12, "holdSec": 1.5, "flashFrames": 8 if footage.get("zoomPulse") else 0, "fadeFromBlack": False},
        "clips": clips,
        "encoder": {"preferred": list(ENCODER_WHITELIST), "pixFmt": "yuv420p", "faststart": True},
    }


def write(edl: dict[str, Any], dest: Path) -> Path:
    dest.write_text(json.dumps(edl, indent=2), encoding="utf-8")
    return dest


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def even(value: int) -> int:
    return int(value) - (int(value) % 2)


def video_filter(clip: dict[str, Any], edl: dict[str, Any], index: int) -> str:
    width, height = even(edl["width"]), even(edl["height"])
    cover = (
        f"scale={width}:{height}:force_original_aspect_ratio=increase:force_divisible_by=2,"
        f"crop={width}:{height},setsar=1"
    )
    chain = [cover]
    hook = edl.get("hook") or {}
    is_hook = clip.get("role") == "hook" or index == 0
    if is_hook:
        punch = float(clip.get("punchIn") or hook.get("punchIn") or 1.12)
        punch = min(1.15, max(1.08, punch))
        frames = max(8, int(round(float(hook.get("holdSec") or 1.5) * int(edl.get("fps") or 30))))
        chain.append(
            f"zoompan=z='if(lt(on,{frames}),{punch:.3f}-{(punch - 1):.3f}*on/{frames},1)'"
            f":x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s={width}x{height}:fps={int(edl.get('fps') or 30)}"
        )
        flash = int(hook.get("flashFrames") or 0)
        if flash > 0:
            chain.append(f"eq=brightness='if(lt(n,{flash}),0.45,0)'")
    elif clip.get("kenBurns"):
        dur = max(0.4, float(clip.get("duration") or 1))
        chain.append(
            f"crop={width}:{height}:'((in_w-out_w)*t/{dur:.3f})':'((in_h-out_h)*t/{dur:.3f}*0.45)'"
        )
    chain.append(f"trim=duration={max(0.4, float(clip.get('duration') or 0.4)):.3f}")
    chain.append("setpts=PTS-STARTPTS")
    chain.append(f"fps={int(edl.get('fps') or 30)}")
    chain.append("format=yuv420p")
    return ",".join(chain)


def grade_filter(edl: dict[str, Any]) -> str:
    grade = edl.get("grade") or {}
    parts = [
        "eq=contrast={c:.3f}:saturation={s:.3f}:brightness={b:.3f}".format(
            c=float(grade.get("contrast") or 1.08),
            s=float(grade.get("saturation") or 1.12),
            b=float(grade.get("warmth") or 0) * 0.02,
        )
    ]
    if grade.get("unsharp", True):
        parts.append("unsharp=5:5:0.6:5:5:0.0")
    if float(grade.get("vignette") or 0) > 0.05:
        parts.append("vignette=PI/5")
    if grade.get("grain"):
        parts.append("noise=alls=8:allf=t")
    return ",".join(parts)


def filter_complex(edl: dict[str, Any], fonts_dir: str, burn_captions: bool = True) -> str:
    clips = edl.get("clips") or []
    parts: list[str] = []
    labels: list[str] = []
    for index, clip in enumerate(clips):
        parts.append(f"[{index}:v]{video_filter(clip, edl, index)}[v{index}]")
        labels.append(f"[v{index}]")
    if not clips:
        parts.append(
            f"color=c=black:s={even(edl['width'])}x{even(edl['height'])}:d={max(0.4, float(edl.get('duration') or 1))}:r={int(edl.get('fps') or 30)}[vcat]"
        )
    elif len(clips) == 1:
        parts.append(f"{labels[0]}null[vcat]")
    else:
        parts.append(f"{''.join(labels)}concat=n={len(clips)}:v=1:a=0[vcat]")
    parts.append(f"[vcat]{grade_filter(edl)}[vg]")
    captions = edl.get("captions") or {}
    if burn_captions and captions.get("assPath") and captions.get("renderer") != "off":
        ass = str(captions["assPath"]).replace("\\", "/")
        fonts = fonts_dir.replace("\\", "/")
        parts.append(f"[vg]ass={ass}:fontsdir={fonts}[vout]")
    else:
        parts.append("[vg]null[vout]")
    voice_i = len(clips)
    music_i = len(clips) + 1
    duck = edl.get("duck") or {}
    gap = 10 ** (float(duck.get("gapDb") or GAP_DB) / 20.0)
    parts.append(f"[{voice_i}:a]aformat=sample_fmts=fltp:channel_layouts=stereo[vo]")
    parts.append(f"[{music_i}:a]aformat=sample_fmts=fltp:channel_layouts=stereo,volume={gap:.4f}[bg]")
    parts.append("[bg][vo]sidechaincompress=threshold=0.02:ratio=8:attack=12:release=220:makeup=1[ducked]")
    parts.append("[vo][ducked]amix=inputs=2:duration=first:normalize=0[a]")
    return ";".join(parts)
