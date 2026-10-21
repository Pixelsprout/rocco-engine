# Run from the repository root: python3 -m unittest scripts/test_release.py

import os
import io
import json
import sys
import tarfile
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
BASE = "https://github.com/Pixelsprout/rocco-engine/releases/download/v0.2.0"
BUNDLE_URLS = {
    "platform": f"{BASE}/platform-AAA.tar.zst",
    "linalg": f"{BASE}/linalg-BBB.tar.zst",
    "mesh": f"{BASE}/mesh-CCC.tar.zst",
    "ui": f"{BASE}/ui-DDD.tar.zst",
}
NIGHTLY = "nightly-2026-10-11-7d256b9"


def write_api_docs(api_dir, names=("platform", "linalg", "mesh", "ui")):
    for name in names:
        (api_dir / name / "Module").mkdir(parents=True)
        (api_dir / name / "index.html").write_text(f"<h1>{name}</h1>")
        (api_dir / name / "Module/index.html").write_text("<h1>Module</h1>")


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


class PackDocsTest(unittest.TestCase):
    def test_holds_the_api_html_of_each_bundle_and_the_urls(self):
        with tempfile.TemporaryDirectory() as tmp:
            api = Path(tmp) / "docs"
            write_api_docs(api)
            out = Path(tmp) / "docs.tar.gz"

            release.pack_docs(api, out, NIGHTLY, BUNDLE_URLS)

            with tarfile.open(out) as tar:
                names = set(tar.getnames())
                urls = json.load(tar.extractfile("urls.json"))
            for name in ["platform", "linalg", "mesh", "ui"]:
                self.assertIn(f"{name}/index.html", names)
                self.assertIn(f"{name}/Module/index.html", names)
            self.assertEqual(
                urls,
                {
                    "platform_url": f"{BASE}/platform-AAA.tar.zst",
                    "linalg_url": f"{BASE}/linalg-BBB.tar.zst",
                    "mesh_url": f"{BASE}/mesh-CCC.tar.zst",
                    "ui_url": f"{BASE}/ui-DDD.tar.zst",
                    "roc_nightly": "nightly-2026-10-11-7d256b9",
                },
            )

    def test_rejects_a_bundle_with_no_url(self):
        with tempfile.TemporaryDirectory() as tmp:
            api = Path(tmp) / "docs"
            write_api_docs(api)
            urls = {name: url for name, url in BUNDLE_URLS.items() if name != "mesh"}
            with self.assertRaisesRegex(ValueError, "mesh"):
                release.pack_docs(api, Path(tmp) / "docs.tar.gz", NIGHTLY, urls)

    def test_rejects_a_bundle_with_no_api_html(self):
        with tempfile.TemporaryDirectory() as tmp:
            api = Path(tmp) / "docs"
            write_api_docs(api, names=("platform", "linalg", "mesh"))
            with self.assertRaisesRegex(ValueError, "ui"):
                release.pack_docs(api, Path(tmp) / "docs.tar.gz", NIGHTLY, BUNDLE_URLS)


class CheckDocsTest(unittest.TestCase):
    ASSETS = ["platform-AAA.tar.zst", "linalg-BBB.tar.zst", "mesh-CCC.tar.zst", "ui-DDD.tar.zst", "docs.tar.gz"]

    def pack(self, tmp, urls=BUNDLE_URLS):
        api = Path(tmp) / "docs"
        write_api_docs(api)
        out = Path(tmp) / "docs.tar.gz"
        release.pack_docs(api, out, NIGHTLY, urls)
        return out

    def test_passes_when_every_url_names_an_asset_of_the_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(release.check_docs(self.pack(tmp), BASE, self.ASSETS), [])

    def test_names_a_url_whose_file_the_release_does_not_hold(self):
        with tempfile.TemporaryDirectory() as tmp:
            assets = [name for name in self.ASSETS if name != "mesh-CCC.tar.zst"]
            problems = release.check_docs(self.pack(tmp), BASE, assets)
            self.assertEqual(len(problems), 1)
            self.assertIn("mesh_url", problems[0])

    def test_names_a_url_of_another_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            urls = dict(BUNDLE_URLS, ui=BUNDLE_URLS["ui"].replace("v0.2.0", "v0.1.0"))
            problems = release.check_docs(self.pack(tmp, urls), BASE, self.ASSETS)
            self.assertEqual(len(problems), 1)
            self.assertIn("ui_url", problems[0])

    def test_names_a_missing_or_unknown_key_in_the_urls(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = self.pack(tmp)
            values = release.docs_urls(NIGHTLY, BUNDLE_URLS)
            del values["roc_nightly"]
            values["camera_url"] = f"{BASE}/camera.tar.zst"
            repack(out, {"urls.json": json.dumps(values)})
            problems = release.check_docs(out, BASE, self.ASSETS)
            self.assertEqual(len(problems), 2)
            self.assertIn("roc_nightly", problems[0])
            self.assertIn("camera_url", problems[1])

    def test_names_a_bundle_with_no_api_page(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = self.pack(tmp)
            repack(out, {"linalg/index.html": None})
            problems = release.check_docs(out, BASE, self.ASSETS)
            self.assertEqual(len(problems), 1)
            self.assertIn("linalg/index.html", problems[0])


# Rewrites a tarball with each named member replaced, or dropped when its text is None.
def repack(path, changes):
    with tarfile.open(path) as tar:
        members = {m.name: tar.extractfile(m).read() for m in tar.getmembers() if m.isfile()}
    for name, text in changes.items():
        if text is None:
            del members[name]
        else:
            members[name] = text.encode()
    with tarfile.open(path, "w:gz") as tar:
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


if __name__ == "__main__":
    unittest.main()
