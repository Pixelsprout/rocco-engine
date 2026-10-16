# Run from the repository root: python3 -m unittest scripts/test_release.py

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import release

HEADER = (
    'app [init] { pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", '
    'cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc" }\n'
    "\n"
    "import linalg.Quat\n"
)
URLS = {
    "platform": "https://example.com/p.tar.zst",
    "linalg": "https://example.com/l.tar.zst",
}


class PointHeaderTest(unittest.TestCase):
    def test_points_the_platform_and_bundled_packages_at_their_urls(self):
        source, _ = release.point_header(HEADER, URLS)
        self.assertIn('pf: platform "https://example.com/p.tar.zst"', source)
        self.assertIn('linalg: "https://example.com/l.tar.zst"', source)

    def test_points_an_unbundled_package_at_a_copy_beside_the_app(self):
        source, copied = release.point_header(HEADER, URLS)
        self.assertIn('cam: "camera/main.roc"', source)
        self.assertEqual(copied, ["camera"])

    def test_keeps_the_roc_pin_and_the_body(self):
        source, _ = release.point_header(HEADER, URLS)
        self.assertIn('roc: "nightly-2026-10-11-7d256b9"', source)
        self.assertTrue(source.endswith("\n\nimport linalg.Quat\n"))
        self.assertNotIn("../", source)

    def test_rejects_an_app_with_no_local_platform(self):
        with self.assertRaises(ValueError):
            release.point_header('app [init] { pf: platform "https://example.com/p.tar.zst" }\n', URLS)

    def test_rejects_a_platform_with_no_url(self):
        with self.assertRaises(ValueError):
            release.point_header(HEADER, {"linalg": URLS["linalg"]})


class PrepareAppTest(unittest.TestCase):
    def test_writes_the_app_and_copies_the_unbundled_packages(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "examples/cards").mkdir(parents=True)
            (root / "examples/cards/main.roc").write_text(HEADER)
            (root / "examples/cards/cards.bin").write_text("built")
            (root / "packages/camera").mkdir(parents=True)
            (root / "packages/camera/main.roc").write_text("package [Camera] {}\n")
            (root / "packages/camera/Camera.roc").write_text("Camera := {}\n")

            out = root / "out"
            release.prepare_app(root / "examples/cards", out, URLS, root / "packages")

            self.assertIn("https://example.com/p.tar.zst", (out / "main.roc").read_text())
            self.assertEqual((out / "camera/Camera.roc").read_text(), "Camera := {}\n")
            self.assertFalse((out / "cards.bin").exists())


class NotesTest(unittest.TestCase):
    def test_names_the_roc_nightly_and_every_bundle_url(self):
        notes = release.notes("v0.1.0", "nightly-2026-10-11-7d256b9", URLS)
        self.assertIn("nightly-2026-10-11-7d256b9", notes)
        self.assertIn("https://example.com/p.tar.zst", notes)
        self.assertIn("https://example.com/l.tar.zst", notes)
        self.assertLess(notes.index("platform"), notes.index("linalg"))


if __name__ == "__main__":
    unittest.main()
