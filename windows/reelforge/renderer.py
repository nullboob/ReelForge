from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

from reelforge import caption_ass
from reelforge import caption_png
from reelforge import caption_styles
from reelforge.captions import exclusive_cues, safe_area, srt_string
from reelforge.cards import render_card, render_thumbnail
from reelforge.paths import fonts_dir
from reelforge.presets import duck_linear, pixel_size
from reelforge.publish import thumbnail_headline


def which_ffmpeg() -> str:
    found = shutil.which("ffmpeg")
    if not found:
        raise RuntimeError("ffmpeg is not on PATH. Install ffmpeg and try again.")
    return found


def ffpath(path: Path) -> str:
    return path.resolve().as_posix().replace("'", r"\'")


def run_ffmpeg(args: list[str], cwd: Path) -> None:
    binary = which_ffmpeg()
    result = __import__("subprocess").run(
        [binary, "-hide_banner", "-y", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        tail = (result.stderr or result.stdout or "")[-1400:]
        raise RuntimeError(f"ffmpeg failed: {tail}")


def compose(
    storyboard: dict[str, Any],
    preset: dict[str, Any],
    aspect: str,
    assignments: dict[str, dict[str, Any]],
    captions: list[dict[str, Any]],
    voice_path: Path,
    music_path: Path,
    work: Path,
    export_dir: Path,
    stem: str,
    channel: dict[str, Any],
    script: dict[str, Any],
    burn_captions: bool,
    export_srt: bool,
    on_progress=None,
    caption_style: dict[str, Any] | None = None,
) -> dict[str, Any]:
    width, height = pixel_size(aspect)
    style = caption_style or caption_styles.style_by_id(caption_styles.default_for_preset(preset.get("id") or ""))
    footage = preset.get("footage") or {}
    ken_burns = bool(footage.get("kenBurns"))
    zoom_pulse = bool(footage.get("zoomPulse"))
    grain = bool(footage.get("overlayGrain"))
    grade = preset.get("colorGrade") or {}
    clips: list[Path] = []
    for index, beat in enumerate(storyboard["beats"]):
        if on_progress:
            on_progress(f"Composing beat {index + 1}/{len(storyboard['beats'])}")
        assignment = assignments.get(beat["id"]) or {}
        clip = work / f"clip-{index}.mp4"
        source = Path(assignment.get("path") or "")
        if assignment.get("kind") == "video" and source.exists():
            write_video_clip(source, clip, beat["duration"], width, height, work, zoom_pulse=zoom_pulse)
        else:
            if not source.exists() or assignment.get("kind") not in {"image", "card"}:
                source = work / f"beat-{index}.png"
                render_card(beat["text"], source, (width, height), preset, channel.get("name") or "", watermark=beat["start"] >= 1.5)
            write_still_clip(source, clip, beat["duration"], width, height, work, ken_burns=ken_burns)
        if channel.get("logoPath") and beat["start"] >= 1.5 and Path(channel["logoPath"]).exists():
            overlay_logo(clip, Path(channel["logoPath"]), width, height, work)
        clips.append(clip)

    concat_list = work / "concat.txt"
    concat_list.write_text("".join(f"file '{ffpath(clip)}'\n" for clip in clips), encoding="utf-8")
    silent = work / "picture.mp4"
    try:
        run_ffmpeg(["-f", "concat", "-safe", "0", "-i", concat_list.name, "-c", "copy", silent.name], work)
    except RuntimeError:
        run_ffmpeg(
            ["-f", "concat", "-safe", "0", "-i", concat_list.name, "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", silent.name],
            work,
        )

    pictured = work / "pictured.mp4"
    vf = master_filters(grade, grain, width, height)
    captioned = silent
    if burn_captions and captions:
        if on_progress:
            on_progress("Burning karaoke captions")
        captions = exclusive_cues(captions)
        captioned = burn_captions_layer(silent, pictured, captions, style, width, height, work, channel.get("primaryHex") or "#FF4D6D", vf)
    elif vf:
        run_ffmpeg(
            ["-i", silent.name, "-vf", vf, "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "30", pictured.name],
            work,
        )
        captioned = pictured

    if on_progress:
        on_progress("Mixing voice and ducked music")
    mixed = work / "mixed.mp4"
    vol = max(0.18, min(0.40, duck_linear(preset)))
    filter_complex = (
        f"[1:a]aformat=sample_fmts=fltp:channel_layouts=stereo,volume=1.0[v];"
        f"[2:a]aformat=sample_fmts=fltp:channel_layouts=stereo,volume={vol:.3f}[m];"
        f"[v][m]amix=inputs=2:duration=first:normalize=0[a]"
    )
    run_ffmpeg(
        [
            "-i", captioned.name,
            "-i", voice_path.name,
            "-i", music_path.name,
            "-filter_complex", filter_complex,
            "-map", "0:v:0",
            "-map", "[a]",
            "-c:v", "libx264",
            "-crf", "18",
            "-pix_fmt", "yuv420p",
            "-r", "30",
            "-c:a", "aac",
            "-b:a", "192k",
            "-shortest",
            mixed.name,
        ],
        work,
    )

    export_dir.mkdir(parents=True, exist_ok=True)
    mp4 = export_dir / f"{stem}.mp4"
    shutil.copy2(mixed, mp4)

    thumbs: list[str] = []
    headlines = [
        thumbnail_headline(script.get("hook") or ""),
        thumbnail_headline(script.get("body", [script.get("hook") or ""])[0] if script.get("body") else script.get("hook") or ""),
        thumbnail_headline(script.get("hook") or "Watch this"),
    ]
    for index, headline in enumerate(headlines[:3], start=1):
        thumb = export_dir / f"{stem}-thumb{index}.jpg"
        render_thumbnail(headline, thumb, preset, channel)
        thumbs.append(str(thumb))
    primary = export_dir / f"{stem}.jpg"
    if thumbs:
        shutil.copy2(thumbs[0], primary)

    srt_path = None
    if export_srt and captions:
        srt_path = export_dir / f"{stem}.srt"
        srt_path.write_text(srt_string(captions), encoding="utf-8")

    return {
        "mp4": str(mp4),
        "thumbs": thumbs,
        "thumb": str(primary) if thumbs else None,
        "srt": str(srt_path) if srt_path else None,
    }


def master_filters(grade: dict[str, Any], grain: bool, width: int, height: int) -> str:
    parts: list[str] = []
    contrast = float(grade.get("contrast") or 1.08)
    saturation = float(grade.get("saturation") or 1.12)
    brightness = float(grade.get("warmth") or 0) * 0.02
    parts.append(f"eq=contrast={contrast:.3f}:saturation={saturation:.3f}:brightness={brightness:.3f}")
    if float(grade.get("vignette") or 0.35) > 0.05:
        parts.append("vignette=PI/5")
    if grain:
        parts.append("noise=alls=8:allf=t")
    return ",".join(parts)


def burn_captions_layer(
    silent: Path,
    dest: Path,
    captions: list[dict[str, Any]],
    style: dict[str, Any],
    width: int,
    height: int,
    work: Path,
    primary_hex: str,
    vf: str,
) -> Path:
    if (style.get("renderer") or "ass") == "png":
        try:
            burn_png(silent, dest, captions, style, width, height, work, primary_hex, vf)
            return dest
        except RuntimeError:
            pass
    ass = work / "captions.ass"
    font_file = caption_styles.font_path(style)
    font_name = (font_file.stem if font_file else None) or style.get("font") or "Montserrat ExtraBold"
    ass.write_text(caption_ass.build_ass(captions, style, width, height, font_name, primary_hex), encoding="utf-8")
    fonts = ffpath(fonts_dir())
    ass_filter = f"ass={ass.name}:fontsdir={fonts}"
    chain = f"{vf},{ass_filter}" if vf else ass_filter
    run_ffmpeg(
        ["-i", silent.name, "-vf", chain, "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "30", dest.name],
        work,
    )
    return dest


def burn_png(
    silent: Path,
    dest: Path,
    captions: list[dict[str, Any]],
    style: dict[str, Any],
    width: int,
    height: int,
    work: Path,
    primary_hex: str,
    vf: str,
) -> None:
    font = caption_styles.font_path(style)
    overlays: list[tuple[Path, float, float]] = []
    captions = exclusive_cues(captions)
    word_budget = sum(max(1, len(cue.get("words") or [])) for cue in captions)
    per_word = word_budget <= 36 and (style.get("animation") or "") in {"karaoke-word", "pop-scale", "karaoke-fill", "gradient-sweep"}
    for index, cue in enumerate(captions):
        cue_end = float(cue["start"]) + float(cue["duration"])
        words = cue.get("words") or []
        if per_word and words:
            for word_index, word in enumerate(words):
                png = work / f"cap-{index}-{word_index}.png"
                caption_png.render_cue_png(cue, style, png, (width, height), font, primary_hex, active_word=word_index)
                start = float(word.get("start") or cue["start"])
                end = start + max(0.04, float(word.get("duration") or 0.12))
                if word_index + 1 < len(words):
                    end = min(end, float(words[word_index + 1].get("start") or end))
                end = min(end, cue_end)
                overlays.append((png, start, max(start + 0.04, end)))
        else:
            png = work / f"cap-{index}.png"
            caption_png.render_cue_png(cue, style, png, (width, height), font, primary_hex)
            overlays.append((png, float(cue["start"]), cue_end))
    for index in range(len(overlays) - 1):
        png, start, end = overlays[index]
        nxt = overlays[index + 1][1]
        overlays[index] = (png, start, min(end, nxt))

    args: list[str] = ["-i", silent.name]
    for png, _, _ in overlays:
        args += ["-i", png.name]
    last = "[base]"
    filters = [f"[0:v]{vf or 'null'}{last}"]
    if not vf:
        filters = [f"[0:v]null{last}"]
    for idx, (_, start, end) in enumerate(overlays, start=1):
        out = f"[v{idx}]"
        filters.append(f"{last}[{idx}:v]overlay=0:0:enable='between(t,{start:.3f},{end:.3f})'{out}")
        last = out
    run_ffmpeg(
        [
            *args,
            "-filter_complex",
            ";".join(filters),
            "-map", last,
            "-c:v", "libx264",
            "-crf", "18",
            "-pix_fmt", "yuv420p",
            "-r", "30",
            dest.name,
        ],
        work,
    )


def even(value: int) -> int:
    return int(value) - (int(value) % 2)


def cover_vf(width: int, height: int, ken_burns: bool = False, duration: float = 1.0, zoom_pulse: bool = False) -> str:
    """Pad-to-cover: fill WxH with no letterbox bars. Never use pad-to-fit."""
    w, h = even(width), even(height)
    cover = (
        f"scale={w}:{h}:force_original_aspect_ratio=increase:force_divisible_by=2,"
        f"crop={w}:{h},setsar=1"
    )
    if ken_burns:
        zoom_w, zoom_h = even(int(w * 1.16)), even(int(h * 1.16))
        dur = max(0.4, duration)
        return (
            f"scale={zoom_w}:{zoom_h}:force_original_aspect_ratio=increase:force_divisible_by=2,"
            f"crop={zoom_w}:{zoom_h},"
            f"crop={w}:{h}:'((in_w-out_w)*t/{dur:.3f})':'((in_h-out_h)*t/{dur:.3f}*0.45)',"
            "setsar=1,fps=30,format=yuv420p"
        )
    if zoom_pulse:
        zoom_w, zoom_h = even(int(w * 1.12)), even(int(h * 1.12))
        dur = max(0.4, duration)
        return (
            f"scale={zoom_w}:{zoom_h}:force_original_aspect_ratio=increase:force_divisible_by=2,"
            f"crop={zoom_w}:{zoom_h},"
            f"crop={w}:{h}:"
            f"'(in_w-out_w)/2+((in_w-out_w)/2)*sin(2*PI*t/{max(dur, 2):.3f})':"
            f"'(in_h-out_h)/2',"
            "setsar=1,fps=30,format=yuv420p"
        )
    return f"{cover},fps=30,format=yuv420p"


def write_still_clip(image: Path, dest: Path, duration: float, width: int, height: int, work: Path, ken_burns: bool = False) -> None:
    src = image.name if image.parent == work else ffpath(image)
    dur = max(0.4, duration)
    run_ffmpeg(
        [
            "-loop", "1",
            "-i", src,
            "-t", f"{dur:.3f}",
            "-vf", cover_vf(width, height, ken_burns=ken_burns, duration=dur),
            "-an",
            "-c:v", "libx264",
            "-crf", "18",
            "-pix_fmt", "yuv420p",
            "-s", f"{even(width)}x{even(height)}",
            dest.name,
        ],
        work,
    )


def write_video_clip(source: Path, dest: Path, duration: float, width: int, height: int, work: Path, zoom_pulse: bool = False) -> None:
    copied = work / source.name
    if source.resolve() != copied.resolve():
        shutil.copy2(source, copied)
    dur = max(0.4, duration)
    run_ffmpeg(
        [
            "-stream_loop", "-1",
            "-i", copied.name,
            "-t", f"{dur:.3f}",
            "-vf", cover_vf(width, height, zoom_pulse=zoom_pulse, duration=dur),
            "-an",
            "-c:v", "libx264",
            "-crf", "18",
            "-pix_fmt", "yuv420p",
            "-s", f"{even(width)}x{even(height)}",
            dest.name,
        ],
        work,
    )


def overlay_logo(clip: Path, logo: Path, width: int, height: int, work: Path) -> None:
    logo_copy = work / "logo-overlay.png"
    shutil.copy2(logo, logo_copy)
    out = work / f"{clip.stem}-logo.mp4"
    left, _, _, _ = safe_area(width, height)
    x = int(left)
    y = int(height * 0.82)
    run_ffmpeg(
        [
            "-i", clip.name,
            "-i", logo_copy.name,
            "-filter_complex", f"[1:v]scale={int(width * 0.12)}:-1[lg];[0:v][lg]overlay={x}:{y}",
            "-c:v", "libx264",
            "-crf", "18",
            "-pix_fmt", "yuv420p",
            out.name,
        ],
        work,
    )
    out.replace(clip)


# Kept for unit tests that still import the old helper.
def ass_document(cues: list[dict[str, Any]], width: int, height: int, preset: dict[str, Any]) -> str:
    style = caption_styles.default_for_preset(preset.get("id") or "")
    look = caption_styles.style_by_id(style)
    font_file = caption_styles.font_path(look)
    font_name = (font_file.stem if font_file else None) or look.get("font") or "Montserrat ExtraBold"
    return caption_ass.build_ass(cues, look, width, height, font_name)
