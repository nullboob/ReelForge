from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Any

from reelforge.captions import safe_area, srt_string
from reelforge.cards import find_font, hex_to_rgb, render_card, render_thumbnail
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
    result = subprocess.run(
        [binary, "-hide_banner", "-y", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        tail = (result.stderr or result.stdout or "")[-1200:]
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
) -> dict[str, Any]:
    width, height = pixel_size(aspect)
    clips: list[Path] = []
    for index, beat in enumerate(storyboard["beats"]):
        if on_progress:
            on_progress(f"Composing beat {index + 1}/{len(storyboard['beats'])}")
        assignment = assignments.get(beat["id"]) or {}
        clip = work / f"clip-{index}.mp4"
        source = Path(assignment.get("path") or "")
        if assignment.get("kind") == "video" and source.exists():
            write_video_clip(source, clip, beat["duration"], width, height, work)
        else:
            if not source.exists() or assignment.get("kind") != "image" and assignment.get("kind") != "card":
                source = work / f"beat-{index}.png"
                render_card(beat["text"], source, (width, height), preset, channel.get("name") or "", watermark=beat["start"] >= 1.5)
            write_still_clip(source, clip, beat["duration"], width, height, work)
        if channel.get("logoPath") and beat["start"] >= 1.5 and Path(channel["logoPath"]).exists():
            overlay_logo(clip, Path(channel["logoPath"]), width, height, work)
        clips.append(clip)

    concat_list = work / "concat.txt"
    concat_list.write_text("".join(f"file '{ffpath(clip)}'\n" for clip in clips), encoding="utf-8")
    silent = work / "picture.mp4"
    try:
        run_ffmpeg(["-f", "concat", "-safe", "0", "-i", concat_list.name, "-c", "copy", silent.name], work)
    except RuntimeError:
        run_ffmpeg(["-f", "concat", "-safe", "0", "-i", concat_list.name, "-c:v", "libx264", "-pix_fmt", "yuv420p", silent.name], work)

    if burn_captions and captions:
        ass = work / "captions.ass"
        ass.write_text(ass_document(captions, width, height, preset), encoding="utf-8")
        pictured = work / "pictured.mp4"
        try:
            run_ffmpeg(["-i", silent.name, "-vf", f"ass={ass.name}", "-c:v", "libx264", "-pix_fmt", "yuv420p", pictured.name], work)
            silent = pictured
        except RuntimeError:
            try:
                run_ffmpeg(["-i", silent.name, "-vf", f"subtitles={ass.name}", "-c:v", "libx264", "-pix_fmt", "yuv420p", pictured.name], work)
                silent = pictured
            except RuntimeError:
                pass

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
            "-i", silent.name,
            "-i", voice_path.name,
            "-i", music_path.name,
            "-filter_complex", filter_complex,
            "-map", "0:v:0",
            "-map", "[a]",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
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


def write_still_clip(image: Path, dest: Path, duration: float, width: int, height: int, work: Path) -> None:
    run_ffmpeg(
        [
            "-loop", "1",
            "-i", image.name if image.parent == work else ffpath(image),
            "-t", f"{max(0.4, duration):.3f}",
            "-vf", f"scale={width}:{height}:force_original_aspect_ratio=increase,crop={width}:{height},fps=30,format=yuv420p",
            "-an",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            dest.name,
        ],
        work,
    )


def write_video_clip(source: Path, dest: Path, duration: float, width: int, height: int, work: Path) -> None:
    copied = work / source.name
    if source.resolve() != copied.resolve():
        shutil.copy2(source, copied)
    run_ffmpeg(
        [
            "-stream_loop", "-1",
            "-i", copied.name,
            "-t", f"{max(0.4, duration):.3f}",
            "-vf", f"scale={width}:{height}:force_original_aspect_ratio=increase,crop={width}:{height},fps=30,format=yuv420p",
            "-an",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
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
            "-pix_fmt", "yuv420p",
            out.name,
        ],
        work,
    )
    out.replace(clip)


def ass_document(cues: list[dict[str, Any]], width: int, height: int, preset: dict[str, Any]) -> str:
    left, bottom, box_w, box_h = safe_area(width, height)
    margin_v = int(height * 0.15 + 20)
    margin_l = int(left)
    margin_r = int(width - left - box_w)
    fill = preset.get("captionStyle", {}).get("fill") or "#FFFFFF"
    r, g, b = hex_to_rgb(fill)
    primary = f"&H00{b:02X}{g:02X}{r:02X}"
    align = 5 if preset.get("captionStyle", {}).get("position") == "center" else 2
    size = 64 if preset.get("id") == "viral-hook" else 48
    font = "Arial"
    font_file = find_font(True)
    if font_file:
        font = Path(font_file).stem
    lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        f"PlayResX: {width}",
        f"PlayResY: {height}",
        "WrapStyle: 2",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        f"Style: Default,{font},{size},{primary},&H000000FF,&H00111111,&H80000000,-1,0,0,0,100,100,0,0,1,4,0,{align},{margin_l},{margin_r},{margin_v},1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    for cue in cues:
        start = ass_time(cue["start"])
        end = ass_time(cue["start"] + cue["duration"])
        text = escape_ass(cue["text"])
        lines.append(f"Dialogue: 0,{start},{end},Default,,0,0,0,,{text}")
    return "\n".join(lines) + "\n"


def ass_time(seconds: float) -> str:
    clamped = max(0.0, seconds)
    hours = int(clamped) // 3600
    minutes = (int(clamped) % 3600) // 60
    secs = int(clamped) % 60
    cs = int((clamped - int(clamped)) * 100)
    return f"{hours}:{minutes:02d}:{secs:02d}.{cs:02d}"


def escape_ass(text: str) -> str:
    return text.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}").replace("\n", r"\N")
