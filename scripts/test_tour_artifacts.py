import io
import json
import os
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tour_artifacts

BUILD = 'v0.14.1-44-gabc1234-dirty'
NIGHTLY = '2026-11-04-2622062'
LAYOUT = sorted(tour_artifacts.LAYOUT)
PREVIEW = [name.removeprefix('preview/') for name in LAYOUT if name.startswith('preview/')]


def manifest():
    return {'buildId': BUILD, 'tag': 'v0.15.0', 'rocNightly': f'nightly-{NIGHTLY}'}


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
        tour_artifacts.build(self.out, build_id=BUILD, tag=tag, roc_nightly=NIGHTLY,
                             urls={}, build_worker=worker, build_host=host)

    def files(self):
        found = []
        for dirpath, _, names in os.walk(self.out):
            found += [os.path.relpath(os.path.join(dirpath, n), self.out) for n in names]
        return sorted(found)

    def test_the_folder_has_the_tarball_layout(self):
        self.build()
        self.assertEqual(self.files(), LAYOUT)

    def test_the_manifest_names_the_build_the_tag_and_the_roc_nightly(self):
        self.build()
        with open(os.path.join(self.out, 'manifest.json')) as f:
            self.assertEqual(json.load(f), manifest())

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


URLS = {name: f'https://example.com/v0.15.0/{name}-HASH{name}.tar.zst' for name in ('platform', 'linalg', 'mesh', 'ui', 'camera')}
RELEASE_URLS = {**URLS, 'rocco_web': 'https://example.com/v0.15.0/rocco_web.py'}


def read_member(tar_path, name):
    with tarfile.open(tar_path) as tar:
        return tar.extractfile(name).read()


def write_tar(path, members):
    with tarfile.open(path, 'w:gz') as tar:
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


class PackTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = os.path.join(self.tmp.name, 'tour')
        self.tar = os.path.join(self.tmp.name, 'tour.tar.gz')
        tour_artifacts.build(self.out, build_id=BUILD, tag='v0.15.0', roc_nightly=NIGHTLY,
                             urls={}, build_worker=fake_worker, build_host=fake_host)

    def tearDown(self):
        self.tmp.cleanup()

    def pack(self, tag='v0.15.0', urls=RELEASE_URLS):
        tour_artifacts.pack(self.out, self.tar, tag=tag, urls=urls)

    def test_the_tarball_holds_the_layout_at_its_root(self):
        self.pack()
        with tarfile.open(self.tar) as tar:
            self.assertEqual(sorted(m.name for m in tar.getmembers() if m.isfile()), LAYOUT)

    def test_the_manifest_in_the_tarball_names_the_release_tag(self):
        self.pack()
        self.assertEqual(json.loads(read_member(self.tar, 'manifest.json')), manifest())

    def test_the_source_bundle_mounts_the_five_docs_urls(self):
        self.pack()
        bundle = json.loads(read_member(self.tar, 'compile-worker/source-bundle.json'))
        self.assertEqual(bundle['urls'], {
            URLS['platform']: '/rocco/platform', URLS['linalg']: '/rocco/packages/linalg',
            URLS['mesh']: '/rocco/packages/mesh', URLS['ui']: '/rocco/packages/ui',
            URLS['camera']: '/rocco/packages/camera'})
        self.assertIn('/rocco/packages/ui/main.roc', bundle['files'])

    def test_a_missing_docs_url_fails(self):
        urls = dict(RELEASE_URLS)
        del urls['ui']
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'ui'):
            self.pack(urls=urls)

    def test_a_manifest_tag_that_is_not_the_release_tag_fails(self):
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'v0.16.0'):
            self.pack(tag='v0.16.0')

    def test_an_extra_file_in_the_folder_fails(self):
        write(os.path.join(self.out, 'roc-deps-empty', 'lib', 'x'), b'')
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'roc-deps-empty'):
            self.pack()


class CheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tar = os.path.join(self.tmp.name, 'tour.tar.gz')
        bundle = {'files': {}, 'urls': {url: '/rocco/platform' if name == 'platform' else f'/rocco/packages/{name}'
                                        for name, url in URLS.items()}}
        self.members = {name: b'x' for name in LAYOUT}
        self.members['compile-worker/source-bundle.json'] = json.dumps(bundle).encode()
        self.manifest = manifest()

    def tearDown(self):
        self.tmp.cleanup()

    def check(self, members=None, manifest=None, tag='v0.15.0'):
        members = dict(self.members if members is None else members)
        members['manifest.json'] = json.dumps(self.manifest if manifest is None else manifest).encode()
        write_tar(self.tar, members)
        tour_artifacts.check(self.tar, tag)

    def test_a_good_tarball_passes(self):
        self.check()

    def test_a_top_level_tour_folder_fails(self):
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'tour/manifest.json'):
            self.check(members={f'tour/{name}': data for name, data in self.members.items()})

    def test_a_missing_preview_file_fails(self):
        members = dict(self.members)
        del members['preview/index.wasm']
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'preview/index.wasm'):
            self.check(members=members)

    def test_a_manifest_with_another_shape_fails(self):
        for manifest in ({'buildId': BUILD, 'tag': 'v0.15.0'},
                         {**self.manifest, 'extra': 'x'},
                         {**self.manifest, 'buildId': 7},
                         {**self.manifest, 'rocNightly': ''}):
            with self.subTest(manifest=manifest), self.assertRaisesRegex(tour_artifacts.BuildError, 'manifest.json'):
                self.check(manifest=manifest)

    def test_a_manifest_tag_that_differs_from_the_release_tag_fails(self):
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'v0.16.0'):
            self.check(tag='v0.16.0')

    def test_a_source_bundle_without_the_five_urls_fails(self):
        members = dict(self.members)
        members['compile-worker/source-bundle.json'] = b'{"files":{},"urls":{}}'
        with self.assertRaisesRegex(tour_artifacts.BuildError, 'source-bundle.json'):
            self.check(members=members)


if __name__ == '__main__':
    unittest.main()
