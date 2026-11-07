#!/usr/bin/env python3
"""Prepare source images and a fixed-time LDR sky without third-party packages."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile
import zlib

CHECKSUM = "2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d"
OUT = Path(__file__).resolve().parents[1]
PREFIX = "cq-godot-3d-village-look/"
FACES = {
    "px": lambda u, v: (1, -v, -u),
    "nx": lambda u, v: (-1, -v, u),
    "py": lambda u, v: (u, 1, v),
    "ny": lambda u, v: (u, -1, -v),
    "pz": lambda u, v: (u, -v, 1),
    "nz": lambda u, v: (-u, -v, -1),
}


def linear(x):
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4


def srgb(x):
    return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055


def colour(*values):
    return tuple(map(linear, values))


def mix(a, b, t):
    return tuple(x * (1 - t) + y * t for x, y in zip(a, b))


def smooth(a, b, x):
    t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def noise_pixels(data):
    width, height, depth, kind, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", data[16:29]
    )
    assert (depth, kind, compression, filtering, interlace) == (8, 6, 0, 0, 0)
    chunks = []
    offset = 8
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        if data[offset + 4:offset + 8] == b"IDAT":
            chunks.append(data[offset + 8:offset + 8 + length])
        offset += length + 12
    raw = zlib.decompress(b"".join(chunks))
    stride = width * 4
    prior = bytearray(stride)
    red = []
    for y in range(height):
        mode = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            left = row[i - 4] if i >= 4 else 0
            above = prior[i]
            corner = prior[i - 4] if i >= 4 else 0
            estimate = left + above - corner
            distances = [abs(estimate - n) for n in (left, above, corner)]
            paeth = (left, above, corner)[distances.index(min(distances))]
            predictor = (0, left, above, (left + above) // 2, paeth)[mode]
            row[i] = (row[i] + predictor) & 255
        red.extend(n / 255 for n in row[::4])
        prior = row
    return width, height, red


def sample(noise, u, v):
    width, height, pixels = noise
    x, y = (u % 1) * width - 0.5, (v % 1) * height - 0.5
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    def at(dx, dy):
        return pixels[((iy + dy) % height) * width + (ix + dx) % width]
    return (at(0, 0) * (1 - fx) + at(1, 0) * fx) * (1 - fy) + (at(0, 1) * (1 - fx) + at(1, 1) * fx) * fy


def ridge(azimuth, frequency, seed):
    value, amplitude = 0, 1
    for i in range(4):
        value += amplitude * (0.5 + 0.5 * math.sin(azimuth * frequency + seed * (i + 1) * 1.7) * math.cos(azimuth * frequency * 0.53 + seed * 2.3))
        amplitude *= 0.5
        frequency *= 2.1
    return value / 1.875


def sky(direction, noise, time):
    length = math.sqrt(sum(n * n for n in direction))
    x, h, z = (n / length for n in direction)
    length = math.sqrt(0.84 ** 2 + 0.52 ** 2 + 0.16 ** 2)
    sun = (-0.84 / length, 0.52 / length, -0.16 / length)
    mu = max(0, x * sun[0] + h * sun[1] + z * sun[2])
    horizontal = math.hypot(x + 0.0001, z + 0.0001)
    sun_horizontal = math.hypot(sun[0] + 0.0001, sun[2] + 0.0001)
    side = max(0, min(1, ((x + 0.0001) * (sun[0] + 0.0001) + (z + 0.0001) * (sun[2] + 0.0001)) / horizontal / sun_horizontal * 0.5 + 0.5))
    horizon = mix(colour(0.78, 0.8, 0.82), colour(1, 0.78, 0.55), side ** 3)
    result = mix(horizon, colour(0.22, 0.4, 0.72), max(0, h) ** 0.45)
    if h < 0:
        result = mix(horizon, colour(0.16, 0.15, 0.13), min(1, -h * 6))
    sun_colour = colour(1, 0.86, 0.7)
    # The source omits its disc during the cubemap lighting pass.
    result = tuple(c + s * (mu ** 6 * 0.55 + mu ** 220 * 1.5) for c, s in zip(result, sun_colour))
    if h > 0:
        u, v = x / (h + 0.12) * 0.32 + time * 0.004, z / (h + 0.12) * 0.32 + time * 0.0015
        density = sample(noise, u, v) * 0.6 + sample(noise, u * 2.3 + 0.37, v * 2.3 + 0.11) * 0.28 + sample(noise, u * 5.1 + 0.71, v * 5.1 + 0.53) * 0.12
        coverage = smooth(0.46, 0.62, density) * smooth(0, 0.16, h)
        thick = smooth(0.46, 0.81, density)
        cloud = mix(colour(1, 0.95, 0.88), colour(0.56, 0.6, 0.7), thick * 0.75)
        cloud = tuple(c * (0.85 + 0.35 * side) + s * mu ** 12 * (1 - thick) * 1.2 for c, s in zip(cloud, sun_colour))
        result = mix(result, tuple(c * (0.9 + 0.2 * h) for c in cloud), coverage * 0.92)
    az = math.atan2(x, z)
    if -0.02 < h < 0.02 + 0.11 * ridge(az, 3, 1.3) ** 1.6:
        result = mix(result, mix(colour(0.46, 0.54, 0.6), horizon, 0.35), 0.85)
    if -0.02 < h < 0.01 + 0.07 * ridge(az + 1.1, 5, 4.1) ** 1.4:
        result = mix(result, mix(colour(0.3, 0.38, 0.38), horizon, 0.2), 0.9)
    return result


def png(side, pixels):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + pixels[y * side * 3:(y + 1) * side * 3] for y in range(side))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", side, side, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def prepare(archive, output, side, time):
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == CHECKSUM, "Source archive checksum differs"
    report = {"archive_sha256": CHECKSUM, "time_seconds": time, "face_side": side, "format": "LDR sRGB RGB8", "sun_disc": False, "files": {}, "source_sha256": {}}
    def write(path, data):
        dest = output / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        report["files"][path] = hashlib.sha256(data).hexdigest()
    with zipfile.ZipFile(archive) as source:
        for name in ("T_Noise_Terrain.png", "ground_mask.png"):
            path = "textures/" + name
            data = source.read(PREFIX + path)
            report["source_sha256"][path] = hashlib.sha256(data).hexdigest()
            write("assets/images/" + name, data)
        noise = noise_pixels(source.read(PREFIX + "textures/T_Noise_Terrain.png"))
        for path in ("shaders/sky.gdshader", "shaders/ground.gdshader", "scripts/look.gd", "scenes/finished.tscn"):
            report["source_sha256"][path] = hashlib.sha256(source.read(PREFIX + path)).hexdigest()
    for name, direction in FACES.items():
        pixels = bytearray()
        clipped = 0
        for y in range(side):
            for x in range(side):
                result = sky(direction((x + 0.5) / side * 2 - 1, (y + 0.5) / side * 2 - 1), noise, time)
                clipped += any(c > 1 for c in result)
                pixels.extend(round(srgb(max(0, min(1, c))) * 255) for c in result)
        write("assets/sky/village/" + name + ".png", png(side, pixels))
        report.setdefault("clipped_texels", {})[name] = clipped
    (output / "source/lighting-manifest.json").parent.mkdir(parents=True, exist_ok=True)
    (output / "source/lighting-manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"images": len(report["files"]), "clipped_texels": report["clipped_texels"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output", type=Path, default=OUT)
    parser.add_argument("--side", type=int, default=256)
    parser.add_argument("--time", type=float, default=0.0)
    args = parser.parse_args()
    assert args.side > 0 and math.isfinite(args.time)
    prepare(args.archive, args.output, args.side, args.time)
