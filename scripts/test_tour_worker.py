import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import roc_patches
import tour_worker


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


class PinTest(unittest.TestCase):
    def test_the_worker_builds_the_roc_commit_of_the_dockerfile(self):
        self.assertEqual(tour_worker.zon_roc_commit(), roc_patches.pin('ROC_COMMIT'))

    def test_the_zon_commit_is_read_from_the_codeload_url(self):
        zon = '.roc = .{\n    .url = "https://codeload.github.com/roc-lang/roc/tar.gz/abc123",\n    .hash = "roc-0.0.0-X",\n},\n'
        self.assertEqual(tour_worker.zon_roc_commit(zon), 'abc123')

    def test_a_zon_with_no_roc_url_fails(self):
        with self.assertRaises(ValueError):
            tour_worker.zon_roc_commit('.dependencies = .{},\n')


class SourceBundleTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        write(os.path.join(self.root, 'platform', 'main.roc'), 'platform ""\n')
        write(os.path.join(self.root, 'platform', 'Draw.roc'), 'module [Draw]\n')
        write(os.path.join(self.root, 'platform', 'targets', 'x', 'host.roc'), 'skip\n')
        write(os.path.join(self.root, 'platform', 'shader-tools', 'a.roc'), 'skip\n')
        write(os.path.join(self.root, 'platform', 'notes.md'), 'skip\n')
        write(os.path.join(self.root, 'packages', 'linalg', 'main.roc'), 'package [Vec3] {}\n')
        write(os.path.join(self.root, 'packages', 'linalg', 'assets', 'a.roc'), 'skip\n')
        write(os.path.join(self.root, 'examples', 'tutorial', '01-window', 'main.roc'), 'skip\n')

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_bundle_holds_platform_and_package_sources_in_repo_layout(self):
        bundle = tour_worker.source_bundle(self.root, {})
        self.assertEqual(sorted(bundle['files']), [
            '/rocco/packages/linalg/main.roc',
            '/rocco/platform/Draw.roc',
            '/rocco/platform/main.roc',
        ])
        self.assertEqual(bundle['files']['/rocco/platform/Draw.roc'], 'module [Draw]\n')
        self.assertEqual(bundle['urls'], {})

    def test_each_pinned_url_maps_to_its_bundle_folder(self):
        bundle = tour_worker.source_bundle(self.root, {
            'platform': 'https://example.com/platform-AAA.tar.zst',
            'linalg': 'https://example.com/linalg-BBB.tar.zst',
        })
        self.assertEqual(bundle['urls'], {
            'https://example.com/platform-AAA.tar.zst': '/rocco/platform',
            'https://example.com/linalg-BBB.tar.zst': '/rocco/packages/linalg',
        })

    def test_a_url_for_an_unknown_package_fails(self):
        with self.assertRaises(ValueError):
            tour_worker.source_bundle(self.root, {'nope': 'https://example.com/nope-A.tar.zst'})

    def test_the_bundle_is_the_same_json_on_each_write(self):
        out = os.path.join(self.root, 'a.json')
        tour_worker.write_source_bundle(self.root, {}, out)
        with open(out) as f:
            first = f.read()
        tour_worker.write_source_bundle(self.root, {}, out)
        with open(out) as f:
            self.assertEqual(f.read(), first)
        self.assertIn('/rocco/platform/main.roc', json.loads(first)['files'])


if __name__ == '__main__':
    unittest.main()
