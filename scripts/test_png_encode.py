# Run from the repository root: python3 -m unittest scripts/test_png_encode.py
#
# engine/png_encode_test.odin checks that png_encode writes the fixture byte
# for byte. This test reads the fixture with Python's zlib and the PNG reader
# in bridge.py, so a reader that is not the host's agrees with the writer.

import os
import sys
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bridge

FIXTURE = Path(__file__).resolve().parent.parent / "engine" / "testdata" / "png_encode_4x3.png"
WIDTH = 4
HEIGHT = 3


# Keep in step with png_fixture_pixels in engine/png_encode_test.odin.
def pixel(x, y):
    return bytes([(x * 64) & 255, (y * 100) & 255, (200 - x * 30 - y * 10) & 255, (255 - x * 20 - y * 5) & 255])


class PngEncodeTest(unittest.TestCase):
    def test_zlib_and_a_png_reader_decode_the_odin_fixture_to_the_same_pixels(self):
        width, height, rgba = bridge.png_rgba(FIXTURE.read_bytes())
        self.assertEqual((width, height), (WIDTH, HEIGHT))
        want = b"".join(pixel(x, y) for y in range(HEIGHT) for x in range(WIDTH))
        self.assertEqual(rgba, want)

    def test_the_reader_rejects_a_bad_crc(self):
        data = bytearray(FIXTURE.read_bytes())
        data[-20] ^= 1
        with self.assertRaises((ValueError, zlib.error)):
            bridge.png_rgba(bytes(data))


if __name__ == "__main__":
    unittest.main()
