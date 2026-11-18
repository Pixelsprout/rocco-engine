import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tour_artifacts

BUILD = 'v0.14.1-44-gabc1234-dirty'
PREVIEW = ('host.html', 'preview.js', 'rocco.js', 'index.js', 'index.wasm', 'index.data', 'index.data.js')


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)


def fake_worker(out, build_id):
    write(os.path.join(out, 'compile-worker.wasm'), b'\0asm' + build_id.encode() + b'\0')
    write(os.path.join(out, 'compile-worker.mjs'), b'export {}')
    write(os.path.join(out, 'source-bundle.json'), b'{"files":{},"urls":{}}')


def fake_host(out, build_id):
    for name in PREVIEW:
        write(os.path.join(out, name), b'x')
    write(os.path.join(out, 'preview.js'), f'var BUILD_ID = {json.dumps(build_id)};'.encode())


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = os.path.join(self.tmp.name, 'tour')

    def tearDown(self):
        self.tmp.cleanup()

    def build(self, worker=fake_worker, host=fake_host, tag='v0.15.0'):
        tour_artifacts.build(self.out, build_id=BUILD, tag=tag, roc_nightly='2026-11-04-2622062',
                             urls={}, build_worker=worker, build_host=host)

    def files(self):
        found = []
        for dirpath, _, names in os.walk(self.out):
            found += [os.path.relpath(os.path.join(dirpath, n), self.out) for n in names]
        return sorted(found)

    def test_the_folder_has_the_tarball_layout(self):
        self.build()
        self.assertEqual(self.files(), sorted(
            ['manifest.json', 'compile-worker/compile-worker.wasm', 'compile-worker/compile-worker.mjs',
             'compile-worker/source-bundle.json'] + [f'preview/{n}' for n in PREVIEW]))

    def test_the_manifest_names_the_build_the_tag_and_the_roc_nightly(self):
        self.build()
        with open(os.path.join(self.out, 'manifest.json')) as f:
            self.assertEqual(json.load(f), {'buildId': BUILD, 'tag': 'v0.15.0', 'rocNightly': 'nightly-2026-11-04-2622062'})

    def test_a_worker_from_another_build_fails(self):
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'compile-worker.wasm'):
            self.build(worker=lambda out, _: fake_worker(out, 'v0.0.0-1-g0000000'))

    def test_a_preview_from_another_build_fails(self):
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'preview.js'):
            self.build(host=lambda out, _: fake_host(out, 'v0.0.0-1-g0000000'))

    def test_a_tag_that_is_not_a_safe_folder_name_fails(self):
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'tag'):
            self.build(tag='../v1')

    def test_old_files_in_the_folder_go(self):
        write(os.path.join(self.out, 'roc', 'build.zig'), b'')
        self.build()
        self.assertNotIn('roc/build.zig', self.files())


if __name__ == '__main__':
    unittest.main()
