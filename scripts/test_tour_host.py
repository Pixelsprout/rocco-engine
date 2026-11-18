import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tour_host


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)


class SharedDataTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.out = os.path.join(self.root, 'out')
        os.makedirs(self.out)
        tutorial = os.path.join(self.root, 'examples', 'tutorial')
        write(os.path.join(tutorial, '02-character', 'assets', 'meshes', 'pip.glb'), b'PIP')
        write(os.path.join(tutorial, '08-sound', 'assets', 'meshes', 'pip.glb'), b'PIP')
        write(os.path.join(tutorial, '08-sound', 'assets', 'sound', 'blip.wav'), b'BLIP')
        write(os.path.join(tutorial, '08-sound', 'assets', '.DS_Store'), b'x')
        write(os.path.join(tutorial, '01-window', 'main.roc'), b'app')
        write(os.path.join(tutorial, 'source', 'make_meshes.py'), b'')

    def tearDown(self):
        self.tmp.cleanup()

    def files(self):
        return tour_host.write_shared_data(self.root, self.out)

    def test_one_data_file_holds_the_assets_of_every_tutorial_step_once(self):
        self.assertEqual(self.files(), ['/assets/meshes/pip.glb', '/assets/sound/blip.wav'])
        with open(os.path.join(self.out, 'index.data'), 'rb') as f:
            self.assertEqual(f.read(), b'PIPBLIP')
        with open(os.path.join(self.out, 'index.data.js')) as f:
            loader = f.read()
        self.assertIn('["/assets/sound/blip.wav", 3, 7]', loader)
        self.assertIn('["/assets", "sound"]', loader)

    def test_the_data_loader_takes_its_file_names_from_the_preview_loader(self):
        self.files()
        with open(os.path.join(self.out, 'index.data.js')) as f:
            loader = f.read()
        self.assertIn('Module["locateFile"] = globalThis.tourLocateFile', loader)
        self.assertIn('fetch(Module["locateFile"]("index.data", ""))', loader)

    def test_two_steps_with_different_bytes_under_one_name_fail(self):
        write(os.path.join(self.root, 'examples', 'tutorial', '10-animation', 'assets', 'meshes', 'pip.glb'), b'NEW')
        with self.assertRaisesRegex(tour_host.BuildError, '/assets/meshes/pip.glb.*02-character.*10-animation'):
            self.files()


# A module with one function: (drop (memory.grow (i32.const 1))), or with no memory.grow.
WASM_HEAD = bytes.fromhex('0061736d01000000' '010401600000' '03020100' '0503010001')
WASM_GROW = WASM_HEAD + bytes.fromhex('0a09010700410140001a0b')
WASM_NO_GROW = WASM_HEAD + bytes.fromhex('0a0701050041011a0b')


@unittest.skipUnless(tour_host.wasm_dis(), 'needs wasm-dis from emsdk (scripts/toolchain.sh run)')
class MemoryGrowCheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def module(self, data):
        path = os.path.join(self.tmp.name, 'index.wasm')
        write(path, data)
        return path

    def test_a_module_that_grows_memory_from_wasm_fails(self):
        with self.assertRaisesRegex(tour_host.BuildError, '1 memory.grow'):
            tour_host.check_no_memory_grow(self.module(WASM_GROW))

    def test_a_module_with_no_memory_grow_passes(self):
        tour_host.check_no_memory_grow(self.module(WASM_NO_GROW))


class EmscriptenEnvTest(unittest.TestCase):
    def test_em_cache_under_a_symlinked_folder_becomes_its_real_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            real = os.path.join(tmp, 'real')
            os.makedirs(real)
            os.symlink(real, os.path.join(tmp, 'link'))
            env = tour_host.emscripten_env({'EM_CACHE': os.path.join(tmp, 'link', 'cache'), 'PATH': '/bin'})
            self.assertEqual(env['EM_CACHE'], os.path.join(os.path.realpath(real), 'cache'))
            self.assertEqual(env['PATH'], '/bin')

    def test_no_em_cache_keeps_the_emsdk_default(self):
        self.assertNotIn('EM_CACHE', tour_host.emscripten_env({'PATH': '/bin'}))


class GlueAbiTest(unittest.TestCase):
    ABI = os.path.join(tour_host.ROOT, 'engine', 'roc_platform_abi.odin')
    GLUE = os.path.join(tour_host.HOST_DIR, 'tour_glue.c')

    def test_the_glue_types_have_the_wasm32_sizes_of_the_generated_abi(self):
        tour_host.check_glue_abi(self.GLUE, self.ABI)

    def test_a_glue_type_with_another_size_fails(self):
        with open(self.GLUE) as f:
            glue = f.read()
        self.assertIn('ROC_TYPE(Roc_View, 212)', glue)
        with tempfile.TemporaryDirectory() as tmp:
            changed = os.path.join(tmp, 'tour_glue.c')
            write(changed, glue.replace('ROC_TYPE(Roc_View, 212)', 'ROC_TYPE(Roc_View, 216)').encode())
            with self.assertRaisesRegex(tour_host.BuildError, 'Roc_View is 216 bytes.*212'):
                tour_host.check_glue_abi(changed, self.ABI)


if __name__ == '__main__':
    unittest.main()
