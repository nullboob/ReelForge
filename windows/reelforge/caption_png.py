from __future__ import annotations

from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from reelforge.captions import safe_area
from reelforge.cards import hex_to_rgb


RAINBOW = ["#FF2D55", "#FF7A00", "#FFE14D", "#34C759", "#0072FF", "#7B5CFF"]


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
    font = ImageFont.truetype(str(font_file), font_size) if font_file and font_file.exists() else ImageFont.load_default()
    words = [w["word"] if isinstance(w, dict) else str(w) for w in (cue.get("words") or [])]
    if not words:
        words = (cue.get("text") or "").split()
    if style.get("allCaps"):
        words = [w.upper() for w in words]
    left, bottom, box_w, box_h = safe_area(width, height)
    text = " ".join(words)
    text_w = draw.textlength(text, font=font)
    line_h = font_size + 18
    pad_x, pad_y = 28, 16
    box_width = min(box_w, text_w + pad_x * 2)
    box_height = line_h + pad_y
    box_x = left + (box_w - box_width) / 2
    if style.get("position") == "bottom":
        box_y = height - bottom - box_height
    else:
        box_y = (height - box_height) / 2
        box_y = max(height * 0.12, min(box_y, height - bottom - box_height))

    plate = style.get("plate") or "none"
    plate_fill = style.get("plateFill") or "#111111"
    if plate_fill == "primaryHex":
        plate_fill = primary_hex or "#FF4D6D"
    if plate in {"pill", "bar", "box", "soft"}:
        color = (*hex_to_rgb(plate_fill), 230 if plate != "soft" else 170)
        radius = 28 if plate == "pill" else (8 if plate == "box" else 12)
        _rounded(draw, (box_x, box_y, box_x + box_width, box_y + box_height), radius, color)

    x = box_x + (box_width - text_w) / 2
    y = box_y + pad_y / 2
    gradient = style.get("gradient") or []
    if style.get("id") == "rainbow-word":
        for index, word in enumerate(words):
            fill = hex_to_rgb(RAINBOW[index % len(RAINBOW)])
            if active_word is not None and index == active_word:
                fill = (255, 255, 255)
            _word(draw, word, x, y, font, fill, style)
            x += draw.textlength(word + " ", font=font)
    elif gradient and style.get("renderer") == "png":
        mask = Image.new("L", (width, height), 0)
        mask_draw = ImageDraw.Draw(mask)
        cursor = x
        for word in words:
            mask_draw.text((cursor, y), word, font=font, fill=255)
            cursor += draw.textlength(word + " ", font=font)
        graded = _gradient_image(width, height, [hex_to_rgb(c) for c in gradient])
        if int(style.get("outline") or 0) > 0:
            stroke = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            sdraw = ImageDraw.Draw(stroke)
            cursor = x
            for word in words:
                sdraw.text((cursor, y), word, font=font, fill=(*hex_to_rgb(style.get("stroke") or "#111111"), 255), stroke_width=int(style["outline"]), stroke_fill=(*hex_to_rgb(style.get("stroke") or "#111111"), 255))
                cursor += draw.textlength(word + " ", font=font)
            image = Image.alpha_composite(image, stroke)
            draw = ImageDraw.Draw(image)
        image.paste(graded, (0, 0), mask)
        if active_word is not None and 0 <= active_word < len(words):
            cursor = x
            for index, word in enumerate(words):
                if index == active_word:
                    draw.text((cursor, y), word, font=font, fill=(255, 255, 255, 255))
                cursor += draw.textlength(word + " ", font=font)
    else:
        for index, word in enumerate(words):
            fill = hex_to_rgb(style.get("highlight") if active_word == index else style.get("fill") or "#FFFFFF")
            _word(draw, word, x, y, font, fill, style)
            x += draw.textlength(word + " ", font=font)

    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest, "PNG")
    return dest


def _word(draw: ImageDraw.ImageDraw, word: str, x: float, y: float, font: ImageFont.ImageFont, fill: tuple[int, int, int], style: dict[str, Any]) -> None:
    outline = int(style.get("outline") or 0)
    if outline > 0:
        draw.text((x, y), word, font=font, fill=(*fill, 255), stroke_width=outline, stroke_fill=(*hex_to_rgb(style.get("stroke") or "#111111"), 255))
    else:
        draw.text((x, y), word, font=font, fill=(*fill, 255))


def _rounded(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], radius: int, color: tuple[int, int, int, int]) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=color)


def _gradient_image(width: int, height: int, colors: list[tuple[int, int, int]]) -> Image.Image:
    img = Image.new("RGB", (width, height), colors[0])
    pixels = img.load()
    stops = max(1, len(colors) - 1)
    for x in range(width):
        t = x / max(1, width - 1)
        seg = min(stops - 1, int(t * stops))
        local = (t * stops) - seg
        a = colors[seg]
        b = colors[min(len(colors) - 1, seg + 1)]
        color = tuple(int(a[i] + (b[i] - a[i]) * local) for i in range(3))
        for y in range(height):
            pixels[x, y] = color
    return img.convert("RGBA")
