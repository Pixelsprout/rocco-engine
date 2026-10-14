# Builds the test sky for Kula: six PNGs in assets/sky/test/. Run from any directory:
#   python3 games/kula/assets/source/make_sky.py
#
# Each texel's colour comes from its world direction, so the sky has no seams.
# The face layout is the one engine/sky.odin states: face px holds the
# directions nearest +x, with its top row towards +y and its left column
# towards +z. A warm disc sits at MARKER, so a wrong face order shows by eye.

import math
import os
import struct
import zlib

SKY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sky", "test")
SIDE = 128

# Linear colours.
ZENITH = (0.05, 0.12, 0.45)
HORIZON = (0.55, 0.65, 0.8)
GROUND = (0.08, 0.07, 0.06)
MARKER_COLOUR = (1.0, 0.6, 0.2)
MARKER = (1.0, 0.25, 0.0)
MARKER_RADIUS = math.radians(6)
LINE_COLOUR_SCALE = 0.7
LINE_STEP = math.radians(15)
LINE_WIDTH = math.radians(0.6)


# u and v run from -1 at the left and top to 1 at the right and bottom.
FACES = {
    "px": lambda u, v: (1.0, -v, -u),
    "nx": lambda u, v: (-1.0, -v, u),
    "py": lambda u, v: (u, 1.0, v),
    "ny": lambda u, v: (u, -1.0, -v),
    "pz": lambda u, v: (u, -v, 1.0),
    "nz": lambda u, v: (-u, -v, -1.0),
}


def normalise(d):
    length = math.sqrt(sum(c * c for c in d))
    return tuple(c / length for c in d)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def near_line(angle):
    return abs(angle - round(angle / LINE_STEP) * LINE_STEP) < LINE_WIDTH


def sky_colour(d):
    if d[1] >= 0:
        colour = mix(HORIZON, ZENITH, math.sqrt(d[1]))
    else:
        colour = mix(HORIZON, GROUND, min(1.0, -d[1] * 8))
    elevation = math.asin(max(-1.0, min(1.0, d[1])))
    azimuth = math.atan2(d[2], d[0])
    if near_line(elevation) or (abs(d[1]) < 0.97 and near_line(azimuth)):
        colour = tuple(c * LINE_COLOUR_SCALE for c in colour)
    marker = normalise(MARKER)
    if math.acos(max(-1.0, min(1.0, sum(a * b for a, b in zip(d, marker))))) < MARKER_RADIUS:
        colour = MARKER_COLOUR
    return colour


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def png(width, height, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(b"\x00" + row for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def face_rows(direction):
    rows = []
    for y in range(SIDE):
        row = bytearray()
        for x in range(SIDE):
            u = 2 * (x + 0.5) / SIDE - 1
            v = 2 * (y + 0.5) / SIDE - 1
            colour = sky_colour(normalise(direction(u, v)))
            row += bytes(round(linear_to_srgb(c) * 255) for c in colour)
        rows.append(bytes(row))
    return rows


def main():
    os.makedirs(SKY, exist_ok=True)
    for name, direction in FACES.items():
        with open(os.path.join(SKY, name + ".png"), "wb") as f:
            f.write(png(SIDE, SIDE, face_rows(direction)))


main()
