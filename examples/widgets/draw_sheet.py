#!/usr/bin/env python3
"""Draws assets/images/sheet.png, the sprite sheet of the widgets example.

    python3 examples/widgets/draw_sheet.py

The sheet is four 16 by 16 frames in a row: a plus, a heart, a star and a gem.
The plus and the heart are white, so a tint gives them their colour. Every
pixel outside a shape is fully transparent.
"""

import math
import os
import struct
import zlib

FRAME = 16
WHITE = (255, 255, 255, 255)
YELLOW = (255, 210, 60, 255)
ORANGE = (230, 140, 30, 255)
CYAN = (90, 220, 230, 255)
TEAL = (30, 130, 150, 255)
CLEAR = (0, 0, 0, 0)


def plus(x, y):
    return WHITE if (6 <= x <= 9 and 2 <= y <= 13) or (2 <= x <= 13 and 6 <= y <= 9) else CLEAR


# The heart curve (x^2 + y^2 - 1)^3 = x^2 y^3, with y up.
def heart(x, y):
    u = (x + 0.5 - 8) / 6.5
    v = (8 - (y + 0.5)) / 6.5 + 0.15
    return WHITE if (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0 else CLEAR


def star(x, y):
    u, v = x + 0.5 - 8, y + 0.5 - 8.5
    angle = math.atan2(v, u) + math.pi / 2
    # The radius of a five-pointed star swings between 3 and 7.5 with the angle.
    spoke = abs(((angle * 5 / (2 * math.pi)) % 1) - 0.5) * 2
    reach = 3 + 4.5 * spoke
    distance = math.hypot(u, v)
    if distance > reach:
        return CLEAR
    return ORANGE if distance > reach - 1.2 else YELLOW


def gem(x, y):
    u, v = abs(x + 0.5 - 8), abs(y + 0.5 - 8)
    if u / 6.5 + v / 7.5 > 1:
        return CLEAR
    return TEAL if x < 8 else CYAN


FRAMES = [plus, heart, star, gem]


def png(width, height, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(c for pixel in row for c in pixel) for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main():
    rows = [[FRAMES[x // FRAME](x % FRAME, y) for x in range(FRAME * len(FRAMES))] for y in range(FRAME)]
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "images", "sheet.png")
    with open(path, "wb") as f:
        f.write(png(FRAME * len(FRAMES), FRAME, rows))
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
