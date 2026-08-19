from __future__ import annotations

from pathlib import Path
from typing import Any

from reelforge.captions import caption_band, caption_center_y, exclusive_cues
from reelforge.cards import hex_to_rgb


def ass_color(hex_color: str, alpha: int = 0) -> str:
    r, g, b = hex_to_rgb(hex_color or "#FFFFFF")
    return f"&H{alpha:02X}{b:02X}{g:02X}{r:02X}"


def ass_time(seconds: float) -> str:
    clamped = max(0.0, seconds)
    hours = int(clamped) // 3600
    minutes = (int(clamped) % 3600) // 60
    secs = int(clamped) % 60
    cs = int((clamped - int(clamped)) * 100)
    return f"{hours}:{minutes:02d}:{secs:02d}.{cs:02d}"


def escape_ass(text: str) -> str:
    return text.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}").replace("\n", r"\N")


def ffmpeg_ass_filter(ass_name: str, fonts_dir: str) -> str:
    """Hard rule: burn with ass= only. Never subtitles= or drawtext."""
    return f"ass={ass_name}:fontsdir={fonts_dir}"


def build_ass(
    cues: list[dict[str, Any]],
    style: dict[str, Any],
    width: int,
    height: int,
    font_name: str,
    primary_hex: str | None = None,
) -> str:
    left, top, box_w, box_h = caption_band(width, height)
    margin_l = int(left)
    margin_r = int(width - left - box_w)
    margin_v = int(height - top - box_h)
    align = 2 if style.get("position") == "bottom" else 5
    fill = style.get("fill") or "#FFFFFF"
    highlight = style.get("highlight") or fill
    stroke = style.get("stroke") or "#111111"
    plate = style.get("plate") or "none"
    border_style = 3 if plate in {"bar", "box"} else 1
    outline = int(style.get("outline") or 4)
    shadow = int(style.get("shadow") or 1)
    back = style.get("plateFill") if plate != "none" else "#000000"
    if back == "primaryHex":
        back = primary_hex or "#FF4D6D"
    back = back or "#111111"
    size = int(style.get("size") or 64)
    italic = -1 if "italic" in (style.get("font") or "").lower() else 0
    cx = width / 2
    cy = caption_center_y(height)

    header = [
        "[Script Info]",
        "ScriptType: v4.00+",
        "WrapStyle: 2",
        "ScaledBorderAndShadow: yes",
        f"PlayResX: {width}",
        f"PlayResY: {height}",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        (
            f"Style: Default,{font_name},{size},{ass_color(highlight)},{ass_color(fill)},"
            f"{ass_color(stroke)},{ass_color(back, 80 if plate == 'none' else 0)},-1,{italic},0,0,100,100,0,0,"
            f"{border_style},{outline},{shadow},{align},{margin_l},{margin_r},{margin_v},1"
        ),
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    animation = style.get("animation") or "karaoke-word"
    for cue in exclusive_cues(cues):
        start = ass_time(cue["start"])
        end = ass_time(cue["start"] + cue["duration"])
        text = cue_text(cue, style, animation)
        overrides = [f"\\pos({cx:.0f},{cy:.0f})"]
        if animation == "pop-scale":
            overrides.append(r"\fscx118\fscy118\t(0,140,\fscx100\fscy100)")
        elif animation == "bounce":
            overrides.append(r"\fscx110\fscy120\t(0,80,\fscx100\fscy100)\t(80,160,\fscx104\fscy96)\t(160,240,\fscx100\fscy100)")
        elif animation == "fade":
            overrides.append(r"\fad(90,90)")
        elif animation == "slide-up":
            overrides.append(f"\\move({cx:.0f},{cy + 40:.0f},{cx:.0f},{cy:.0f},0,160)")
        elif animation == "glow-pulse":
            overrides.append(r"\blur2\t(0,200,\blur6)\t(200,400,\blur2)")
        prefix = "{" + "".join(overrides) + "}"
        header.append(f"Dialogue: 0,{start},{end},Default,,0,0,0,,{prefix}{text}")
    return "\n".join(header) + "\n"


def dialogue_windows(ass_text: str) -> list[tuple[float, float, str]]:
    windows: list[tuple[float, float, str]] = []
    for line in ass_text.splitlines():
        if not line.startswith("Dialogue:"):
            continue
        payload = line.split(":", 1)[1]
        parts = payload.split(",", 9)
        if len(parts) < 10:
            continue
        windows.append((_parse_ass_time(parts[1].strip()), _parse_ass_time(parts[2].strip()), parts[9]))
    return windows


def _parse_ass_time(value: str) -> float:
    hours, minutes, rest = value.split(":")
    seconds, cs = rest.split(".")
    return int(hours) * 3600 + int(minutes) * 60 + int(seconds) + int(cs) / 100.0


def _word_dicts(cue: dict[str, Any]) -> list[dict[str, Any]]:
    raw = cue.get("words") or []
    if raw and isinstance(raw[0], dict):
        return raw
    tokens = [w["word"] if isinstance(w, dict) else str(w) for w in raw] or (cue.get("text") or "").split()
    each = max(0.12, float(cue.get("duration") or 0.8) / max(1, len(tokens)))
    return [{"word": token, "duration": each} for token in tokens]


def cue_text(cue: dict[str, Any], style: dict[str, Any], animation: str) -> str:
    words = _word_dicts(cue)
    tokens = [w.get("word") or "" for w in words]
    if style.get("allCaps"):
        tokens = [token.upper() for token in tokens]
        for index, word in enumerate(words):
            word = dict(word)
            word["word"] = tokens[index]
            words[index] = word
    if animation == "typewriter":
        chars = list(" ".join(tokens))
        each = max(1, int(((cue.get("duration") or 0.8) / max(1, len(chars))) * 100))
        return "".join(rf"{{\k{each}}}{escape_ass(ch)}" for ch in chars)
    if style.get("karaoke") == "none" or animation in {"none", ""}:
        return escape_ass(" ".join(tokens))
    tag = r"\kf" if (style.get("karaoke") == "fill" or animation in {"karaoke-fill", "gradient-sweep"}) else r"\k"
    emphasis = cue.get("highlightWordIndex")
    if emphasis is None:
        from reelforge.captions import emphasis_index
        emphasis = emphasis_index(tokens)
    parts = []
    for index, word in enumerate(words):
        dur = max(1, int(float(word.get("duration") or 0.2) * 100))
        token = word.get("word") or ""
        color = ""
        if style.get("id") == "color-switch-strobe" and index % 2 == 1:
            color = r"\1c" + ass_color(style.get("highlight") or "#FF4D6D")
        elif index == emphasis and style.get("primitive") == "keyword-paint":
            color = r"\1c" + ass_color(style.get("highlight") or "#F7C204")
        parts.append(rf"{{{tag}{dur}{color}}}{escape_ass(token)}")
    return " ".join(parts)
