# Run from the repository root: python3 -m unittest scripts/test_web_pixel_check.py

import os
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import web_pixel_check


def write_png(path, width, height, pixels):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    rows = b"".join(b"\x00" + bytes(pixels[y * width * 4 : (y + 1) * width * 4]) for y in range(height))
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


class PixelCheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.native = os.path.join(self.tmp.name, "native.png")
        self.web = os.path.join(self.tmp.name, "web.png")

    def tearDown(self):
        self.tmp.cleanup()

    def test_counts_only_the_pixels_with_a_channel_past_the_tolerance(self):
        write_png(self.native, 3, 1, [10, 10, 10, 255] * 3)
        write_png(self.web, 3, 1, [10, 10, 10, 255, 14, 10, 10, 255, 10, 10, 30, 255])
        self.assertEqual(web_pixel_check.changed_pixels(self.native, self.web, tolerance=4), 1)
        self.assertEqual(web_pixel_check.changed_pixels(self.native, self.web, tolerance=3), 2)

    def test_alpha_is_not_compared(self):
        write_png(self.native, 1, 1, [10, 10, 10, 255])
        write_png(self.web, 1, 1, [10, 10, 10, 0])
        self.assertEqual(web_pixel_check.changed_pixels(self.native, self.web, tolerance=0), 0)

    def test_two_sizes_fail(self):
        write_png(self.native, 2, 1, [0] * 8)
        write_png(self.web, 1, 2, [0] * 8)
        with self.assertRaises(ValueError):
            web_pixel_check.changed_pixels(self.native, self.web, tolerance=0)

    def test_main_fails_above_the_limit(self):
        write_png(self.native, 2, 1, [0, 0, 0, 255] * 2)
        write_png(self.web, 2, 1, [0, 0, 0, 255, 200, 0, 0, 255])
        self.assertEqual(web_pixel_check.main([self.native, self.web, "--tolerance", "8", "--limit", "1"]), 0)
        self.assertEqual(web_pixel_check.main([self.native, self.web, "--tolerance", "8", "--limit", "0"]), 1)


if __name__ == "__main__":
    unittest.main()
