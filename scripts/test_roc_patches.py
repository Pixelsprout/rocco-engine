import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import roc_patches


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


def read(path):
    with open(path) as f:
        return f.read()


HEADER = 'Change: a test change.\nUpstream: not proposed\n\n'


class CopyAndApplyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.roc = os.path.join(self.root, 'roc')
        self.patch_dir = os.path.join(self.root, 'patches')
        self.out = os.path.join(self.root, 'out')
        write(os.path.join(self.roc, 'src', 'a.zig'), 'one\ntwo\nthree\n')
        os.makedirs(self.patch_dir)

    def tearDown(self):
        self.tmp.cleanup()

    def patch(self, name, body):
        write(os.path.join(self.patch_dir, name), body)

    def test_applies_every_patch_in_name_order_to_a_copy(self):
        self.patch('0002-second.patch', HEADER + '--- a/src/a.zig\n+++ b/src/a.zig\n@@ -1,3 +1,3 @@\n ONE\n-two\n+TWO\n three\n')
        self.patch('0001-first.patch', HEADER + '--- a/src/a.zig\n+++ b/src/a.zig\n@@ -1,3 +1,3 @@\n-one\n+ONE\n two\n three\n')
        roc_patches.copy_and_apply(self.roc, self.out, self.patch_dir)
        self.assertEqual(read(os.path.join(self.out, 'src', 'a.zig')), 'ONE\nTWO\nthree\n')
        self.assertEqual(read(os.path.join(self.roc, 'src', 'a.zig')), 'one\ntwo\nthree\n')

    def test_a_patch_that_does_not_apply_fails_with_its_name(self):
        self.patch('0001-stale.patch', HEADER + '--- a/src/a.zig\n+++ b/src/a.zig\n@@ -1,3 +1,3 @@\n-uno\n+ONE\n two\n three\n')
        with self.assertRaises(roc_patches.PatchError) as caught:
            roc_patches.copy_and_apply(self.roc, self.out, self.patch_dir)
        self.assertIn('0001-stale.patch', str(caught.exception))

    def test_a_patch_without_an_upstream_header_fails(self):
        self.patch('0001-bare.patch', '--- a/src/a.zig\n+++ b/src/a.zig\n@@ -1,3 +1,3 @@\n-one\n+ONE\n two\n three\n')
        with self.assertRaises(roc_patches.PatchError) as caught:
            roc_patches.copy_and_apply(self.roc, self.out, self.patch_dir)
        self.assertIn('0001-bare.patch', str(caught.exception))
        self.assertIn('Upstream:', str(caught.exception))

    def test_replaces_an_earlier_copy(self):
        self.patch('0001-first.patch', HEADER + '--- a/src/a.zig\n+++ b/src/a.zig\n@@ -1,3 +1,3 @@\n-one\n+ONE\n two\n three\n')
        roc_patches.copy_and_apply(self.roc, self.out, self.patch_dir)
        roc_patches.copy_and_apply(self.roc, self.out, self.patch_dir)
        self.assertEqual(read(os.path.join(self.out, 'src', 'a.zig')), 'ONE\ntwo\nthree\n')

    def test_an_empty_patch_directory_fails(self):
        with self.assertRaises(roc_patches.PatchError):
            roc_patches.copy_and_apply(self.roc, self.out, self.patch_dir)


class CarriedPatchesTest(unittest.TestCase):
    def test_every_carried_patch_states_its_upstream_status(self):
        names = roc_patches.patches(roc_patches.PATCH_DIR)
        self.assertGreater(len(names), 0)

    def test_the_roc_commit_is_a_full_hash(self):
        self.assertRegex(roc_patches.pin('ROC_COMMIT'), r'^[0-9a-f]{40}$')

    def test_the_platform_header_pins_roc_pin(self):
        with open(os.path.join(roc_patches.ROOT, 'platform', 'main.roc')) as f:
            self.assertIn(f'roc: "{roc_patches.pin("ROC_PIN")}"', f.read())


if __name__ == '__main__':
    unittest.main()
