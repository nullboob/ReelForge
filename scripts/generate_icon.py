#!/usr/bin/env python3
"""Generate ReelForge macOS app icons without third-party libraries."""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def pixel(x: int, y: int, n: int) -> tuple[int, int, int, int]:
    u = (x + 0.5) / n
    v = (y + 0.5) / n
    dx = u - 0.5
    dy = v - 0.5
    r = math.hypot(dx, dy)

    # Rounded-rect mask
    corner = 0.18
    px = abs(dx) - 0.5 + corner
    py = abs(dy) - 0.5 + corner
    outside = math.hypot(max(px, 0), max(py, 0)) + min(max(px, py), 0)
    if outside > 0.002:
        return (0, 0, 0, 0)

    t = min(1.0, max(0.0, (u * 0.65 + (1 - v) * 0.55)))
    cr = int(lerp(255, 26, t))
    cg = int(lerp(77, 12, t))
    cb = int(lerp(109, 18, t))
    gold = max(0.0, 1 - abs((u - v) - 0.08) * 4.2)
    cr = min(255, int(cr + gold * 70))
    cg = min(255, int(cg + gold * 40))
    cb = min(255, int(cb + gold * 8))

    # Play chevron
    if 0.40 < u < 0.70 and 0.32 < v < 0.68:
        local = (v - 0.32) / 0.36
        left = 0.42
        right = 0.42 + local * 0.22 if v < 0.5 else 0.42 + (1 - local) * 0.22
        if left <= u <= right:
            cr = min(255, cr + 90)
            cg = min(255, cg + 80)
            cb = min(255, cb + 50)

    # Film sprocket holes
    for cy in (0.28, 0.50, 0.72):
        if math.hypot(u - 0.24, v - cy) < 0.035:
            cr, cg, cb = 12, 10, 12

    shade = 1 - r * 0.35
    return (
        max(0, min(255, int(cr * shade))),
        max(0, min(255, int(cg * shade))),
        max(0, min(255, int(cb * shade))),
        255,
    )


def write_png(path: Path, n: int) -> None:
    raw = bytearray()
    for y in range(n):
        raw.append(0)
        for x in range(n):
            raw.extend(pixel(x, y, n))
    compressor = zlib.compressobj(9)
    compressed = compressor.compress(bytes(raw)) + compressor.flush()

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", compressed)
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def main() -> None:
    out = Path(__file__).resolve().parents[1] / "Sources/ReelForgeApp/Resources/Assets.xcassets/AppIcon.appiconset"
    out.mkdir(parents=True, exist_ok=True)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        write_png(out / f"icon_{size}.png", size)
        print(f"wrote icon_{size}.png")


if __name__ == "__main__":
    main()
