#!/usr/bin/env python3
"""Build the example's dust and orientation sprites with the Python standard library."""

import math
from pathlib import Path
import struct
import zlib


def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)


def write_image(name, size, rows):
    image = b'\x89PNG\r\n\x1a\n'
    image += chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
    image += chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')
    Path(__file__).resolve().parents[1].joinpath('assets/images', name).write_bytes(image)


def main():
    size = 32
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            radius = math.hypot((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1)
            rows.extend((255, 255, 255, int(max(0, 1 - radius) ** 2 * 255)))
    write_image('dust.png', size, rows)
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        rows.extend(bytes((255, 0, 0, 255) if y < size // 2 else (0, 0, 255, 255)) * size)
    write_image('orientation.png', size, rows)


if __name__ == '__main__':
    main()
