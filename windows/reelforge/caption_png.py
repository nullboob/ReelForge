from __future__ import annotations

from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from reelforge.captions import caption_band, emphasis_index
from reelforge.cards import hex_to_rgb


def render_cue_png(
    cue: dict[str, Any],
    style: dict[str, Any],
    dest: Path,
    size: tuple[int, int],
    font_file: Path | None,
    primary_hex: str | None = None,
    active_word: int | None = None,
) -> Path:
    width, height = size
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    font_size = int(style.get("size") or 64)
    if style.get("animation") == "pop-scale" and active_word is not None:
        font_size = int(font_size * 1.08)
    font = ImageFont.truetype(str(font_file), font_size) if font_file and font_file.exists() else ImageFont.load_default()
    words = [w["word"] if isinstance(w, dict) else str(w) for w in (cue.get("words") or [])]
    if not words:
        words = (cue.get("text") or "").split()
    if style.get("allCaps"):
        words = [w.upper() for w in words]
    if style.get("animation") == "typewriter" and active_word is not None:
        words = words[: active_word + 1]
    left, top, box_w, box_h = caption_band(width, height)
    text = " ".join(words)
    text_w = draw.textlength(text, font=font) if words else 0
    line_h = font_size + 18
    pad_x, pad_y = 28, 16
    box_width = min(box_w, max(text_w + pad_x * 2, 80))
    box_height = line_h + pad_y + (18 if style.get("id") == "beast-3d-pop" else 0)
    box_x = left + (box_w - box_width) / 2
    box_y = top + (box_h - box_height) / 2
    if style.get("animation") == "bounce" and active_word is not None:
        box_y -= 10
    if style.get("animation") == "slide-up" and active_word == 0:
        box_y += 24

    plate = style.get("plate") or "none"
    plate_fill = style.get("plateFill") or "#111111"
    if plate_fill == "primaryHex":
        plate_fill = primary_hex or "#FF4D6D"
    progress = 1.0
    if words and active_word is not None:
        progress = min(1.0, (active_word + 1) / max(1, len(words)))
    if plate in {"pill", "bar", "box", "soft", "chip"}:
        color = (*hex_to_rgb(plate_fill), 230 if plate != "soft" else 170)
        radius = 28 if plate == "pill" else (18 if plate == "chip" else (8 if plate == "box" else 12))
        grown = box_width * (0.72 + 0.28 * progress) if style.get("primitive") == "plate-grow" else box_width
        gx = box_x + (box_width - grown) / 2
        _rounded(draw, (gx, box_y, gx + grown, box_y + box_height), radius, color)
        if plate == "chip":
            chip = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            cdraw = ImageDraw.Draw(chip)
            _rounded(cdraw, (box_x - 8, box_y - 6, box_x + 52, box_y + 34), 12, (*hex_to_rgb(style.get("highlight") or "#F7C204"), 255))
            image = Image.alpha_composite(image, chip)
            draw = ImageDraw.Draw(image)
    elif plate == "wipe":
        wipe_w = box_width * progress
        _rounded(draw, (box_x, box_y, box_x + wipe_w, box_y + box_height), 8, (*hex_to_rgb(plate_fill), 230))

    x = box_x + (box_width - text_w) / 2
    y = box_y + pad_y / 2
    emphasis = cue.get("highlightWordIndex")
    if emphasis is None:
        emphasis = emphasis_index(words)

    gradient = style.get("gradient") or []
    accent_only = style.get("role") == "accent" and bool(gradient)

    if style.get("id") == "beast-3d-pop":
        for dx, dy, color in ((6, 6, (0, 0, 0)), (3, 3, (40, 40, 40)), (0, 0, hex_to_rgb(style.get("fill") or "#FFFFFF"))):
            cursor = x
            for index, word in enumerate(words):
                fill = hex_to_rgb(style.get("highlight") or "#F7C204") if index == emphasis and color != (0, 0, 0) else color
                _word(draw, word, cursor + dx, y + dy, font, fill, style)
                cursor += draw.textlength(word + " ", font=font)
    elif accent_only:
        cursor = x
        for index, word in enumerate(words):
            if index == emphasis:
                _gradient_word(image, word, cursor, y, font, style, width, height)
            else:
                _word(draw, word, cursor, y, font, hex_to_rgb("#FFFFFF"), {**style, "stroke": "#111111", "outline": max(4, int(style.get("outline") or 4))})
            cursor += draw.textlength(word + " ", font=font)
        draw = ImageDraw.Draw(image)
    elif gradient and style.get("renderer") == "png":
        _gradient_word(image, text, x, y, font, style, width, height)
        draw = ImageDraw.Draw(image)
    else:
        for index, word in enumerate(words):
            fill = hex_to_rgb(style.get("highlight") if active_word == index or (active_word is None and index == emphasis) else style.get("fill") or "#FFFFFF")
            _word(draw, word, x, y, font, fill, style)
            x += draw.textlength(word + " ", font=font)

    if style.get("animation") == "glow-pulse":
        glow = image.filter(ImageFilter.GaussianBlur(4))
        image = Image.alpha_composite(glow, image)

    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest, "PNG")
    return dest


def _gradient_word(image: Image.Image, word: str, x: float, y: float, font: ImageFont.ImageFont, style: dict[str, Any], width: int, height: int) -> None:
    colors = [hex_to_rgb(c) for c in (style.get("gradient") or ["#FFFFFF", "#FFFFFF"])]
    mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)
    outline = int(style.get("outline") or 0)
    if outline > 0:
        stroke = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(stroke)
        sdraw.text((x, y), word, font=font, fill=(*hex_to_rgb(style.get("stroke") or "#111111"), 255), stroke_width=outline, stroke_fill=(*hex_to_rgb(style.get("stroke") or "#111111"), 255))
        blended = Image.alpha_composite(image, stroke)
        image.paste(blended)
    mask_draw.text((x, y), word, font=font, fill=255)
    graded = _gradient_image(width, height, colors, float(style.get("angle") or 0))
    image.paste(graded, (0, 0), mask)


def _word(draw: ImageDraw.ImageDraw, word: str, x: float, y: float, font: ImageFont.ImageFont, fill: tuple[int, int, int], style: dict[str, Any]) -> None:
    outline = int(style.get("outline") or 0)
    if outline > 0:
        draw.text((x, y), word, font=font, fill=(*fill, 255), stroke_width=outline, stroke_fill=(*hex_to_rgb(style.get("stroke") or "#111111"), 255))
    else:
        draw.text((x, y), word, font=font, fill=(*fill, 255))


def _rounded(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], radius: int, color: tuple[int, int, int, int]) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=color)


def _mix(colors: list[tuple[int, int, int]], t: float) -> tuple[int, int, int]:
    t = min(1.0, max(0.0, t))
    stops = max(1, len(colors) - 1)
    seg = min(stops - 1, int(t * stops))
    local = (t * stops) - seg
    a = colors[seg]
    b = colors[min(len(colors) - 1, seg + 1)]
    return tuple(int(a[i] + (b[i] - a[i]) * local) for i in range(3))


def _gradient_image(width: int, height: int, colors: list[tuple[int, int, int]], angle: float = 0) -> Image.Image:
    if abs(angle - 135) < 1:
        diag = Image.new("RGB", (width, height), colors[0])
        pixels = diag.load()
        for x in range(0, width, 2):
            t = x / max(1, width - 1)
            color = _mix(colors, t)
            for y in range(0, height, 2):
                pixels[x, y] = color
                if x + 1 < width:
                    pixels[x + 1, y] = color
                if y + 1 < height:
                    pixels[x, y + 1] = color
                    if x + 1 < width:
                        pixels[x + 1, y + 1] = color
        return diag.convert("RGBA")
    strip = Image.new("RGB", (width, 1), colors[0])
    pixels = strip.load()
    for x in range(width):
        pixels[x, 0] = _mix(colors, x / max(1, width - 1))
    return strip.resize((width, height)).convert("RGBA")
