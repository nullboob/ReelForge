from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from reelforge.captions import safe_area


def find_font(bold: bool = True) -> str:
    windir = Path(os.environ.get("WINDIR", r"C:\Windows"))
    candidates = [
        windir / "Fonts" / ("segoeuib.ttf" if bold else "segoeui.ttf"),
        windir / "Fonts" / "arialbd.ttf",
        windir / "Fonts" / "arial.ttf",
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return str(path)
    return ""


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    raw = value.lstrip("#")
    if len(raw) == 3:
        raw = "".join(ch * 2 for ch in raw)
    raw = (raw + "000000")[:6]
    return int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16)


def render_card(
    text: str,
    dest: Path,
    size: tuple[int, int],
    preset: dict[str, Any],
    channel_name: str = "",
    watermark: bool = False,
) -> Path:
    width, height = size
    colors = preset.get("coverGradient") or ["#FF4D6D", "#2B0A12"]
    top = hex_to_rgb(colors[0])
    bottom = hex_to_rgb(colors[-1])
    image = Image.new("RGB", (width, height), bottom)
    pixels = image.load()
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for x in range(width):
            pixels[x, y] = color
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, width, int(height * 0.22)), fill=(0, 0, 0))
    font_path = find_font(True)
    font_size = 72 if width < height else 64
    font = ImageFont.truetype(font_path, font_size) if font_path else ImageFont.load_default()
    left, bottom_m, box_w, box_h = safe_area(width, height)
    wrapped = wrap_text(draw, text, font, int(box_w))
    x = left
    y = height * 0.5 - (len(wrapped) * (font_size + 12)) / 2
    y = max(height * 0.18, min(y, height * 0.72))
    for line in wrapped:
        draw.text((x + 3, y + 3), line, font=font, fill=(0, 0, 0))
        draw.text((x, y), line, font=font, fill=(255, 255, 255))
        y += font_size + 12
    if watermark and channel_name:
        small = ImageFont.truetype(font_path, 28) if font_path else font
        draw.text((left, height * 0.82), channel_name[:28], font=small, fill=(255, 255, 255, 140))
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest, "PNG")
    return dest


def render_thumbnail(headline: str, dest: Path, preset: dict[str, Any], channel: dict[str, Any]) -> Path:
    width, height = 1280, 720
    colors = [channel.get("primaryHex") or "#FF4D6D", channel.get("accentHex") or "#E8C39A"]
    top = hex_to_rgb(colors[0])
    bottom = hex_to_rgb(preset.get("coverGradient", colors)[-1])
    image = Image.new("RGB", (width, height), bottom)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        draw.line((0, y, width, y), fill=color)
    font_path = find_font(True)
    font = ImageFont.truetype(font_path, 92) if font_path else ImageFont.load_default()
    lines = wrap_text(draw, headline, font, 1100)
    y = 180
    for line in lines[:3]:
        draw.text((70, y + 4), line, font=font, fill=(0, 0, 0))
        draw.text((66, y), line, font=font, fill=(255, 248, 236))
        y += 110
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest, "JPEG", quality=90)
    return dest


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, max_width: int) -> list[str]:
    words = text.split()
    if not words:
        return [""]
    lines: list[str] = []
    current = words[0]
    for word in words[1:]:
        trial = f"{current} {word}"
        if draw.textlength(trial, font=font) <= max_width:
            current = trial
        else:
            lines.append(current)
            current = word
    lines.append(current)
    return lines
