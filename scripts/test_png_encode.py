# Run from the repository root: python3 -m unittest scripts/test_png_encode.py
#
# engine/png_encode_test.odin checks that png_encode writes the fixture byte
# for byte. This test reads the fixture with Python's zlib and a small PNG
# reader, so a reader that is not the host's agrees with the writer.

import struct
import unittest
import zlib
from pathlib import Path

FIXTURE = Path(__file__).resolve().parent.parent / "engine" / "testdata" / "png_encode_4x3.png"
SIGNATURE = b"\x89PNG\r\n\x1a\n"
WIDTH = 4
HEIGHT = 3


# Keep in step with png_fixture_pixels in engine/png_encode_test.odin.
def pixel(x, y):
    return bytes([(x * 64) & 255, (y * 100) & 255, (200 - x * 30 - y * 10) & 255, (255 - x * 20 - y * 5) & 255])


def read_chunks(data):
    if data[:8] != SIGNATURE:
        raise ValueError("no PNG signature")
    chunks = []
    at = 8
    while at < len(data):
        (length,) = struct.unpack(">I", data[at : at + 4])
        kind = data[at + 4 : at + 8]
        body = data[at + 8 : at + 8 + length]
        (crc,) = struct.unpack(">I", data[at + 8 + length : at + 12 + length])
        if zlib.crc32(kind + body) != crc:
            raise ValueError(f"bad CRC in {kind!r}")
        chunks.append((kind, body))
        at += 12 + length
    return chunks


# Reads an 8-bit RGBA PNG with no interlace. Every filter type is handled, so
# the reader does not assume the writer's choice of filter 0.
def read_rgba(data):
    chunks = read_chunks(data)
    kinds = [kind for kind, _ in chunks]
    if kinds[0] != b"IHDR" or kinds[-1] != b"IEND":
        raise ValueError(f"bad chunk order {kinds}")
    width, height, depth, color_type, compression, filter_method, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    if (depth, color_type, compression, filter_method, interlace) != (8, 6, 0, 0, 0):
        raise ValueError("not 8-bit RGBA")
    # zlib checks the Adler-32.
    raw = zlib.decompress(b"".join(body for kind, body in chunks if kind == b"IDAT"))
    stride = width * 4
    if len(raw) != (stride + 1) * height:
        raise ValueError("wrong length of rows")
    rows = []
    prev = bytearray(stride)
    for y in range(height):
        line = raw[y * (stride + 1) : (y + 1) * (stride + 1)]
        row = unfilter(line[0], bytearray(line[1:]), prev)
        rows.append(bytes(row))
        prev = row
    return width, height, b"".join(rows)


def unfilter(kind, row, prev):
    for i in range(len(row)):
        left = row[i - 4] if i >= 4 else 0
        up = prev[i]
        up_left = prev[i - 4] if i >= 4 else 0
        if kind == 0:
            add = 0
        elif kind == 1:
            add = left
        elif kind == 2:
            add = up
        elif kind == 3:
            add = (left + up) // 2
        elif kind == 4:
            p = left + up - up_left
            pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
            add = left if pa <= pb and pa <= pc else (up if pb <= pc else up_left)
        else:
            raise ValueError(f"bad filter type {kind}")
        row[i] = (row[i] + add) & 255
    return row


class PngEncodeTest(unittest.TestCase):
    def test_zlib_and_a_png_reader_decode_the_odin_fixture_to_the_same_pixels(self):
        width, height, rgba = read_rgba(FIXTURE.read_bytes())
        self.assertEqual((width, height), (WIDTH, HEIGHT))
        want = b"".join(pixel(x, y) for y in range(HEIGHT) for x in range(WIDTH))
        self.assertEqual(rgba, want)

    def test_the_reader_rejects_a_bad_crc(self):
        data = bytearray(FIXTURE.read_bytes())
        data[-20] ^= 1
        with self.assertRaises((ValueError, zlib.error)):
            read_rgba(bytes(data))


if __name__ == "__main__":
    unittest.main()
