import json
import os
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rocco_web import (
    BuildError,
    asset_files,
    find_target,
    pack_assets,
    platform_dirs,
    platform_source,
    roc_caches,
    shaders,
    copy_default_page,
    copy_game_page,
    exported_global,
    game_page_files,
    game_page_problems,
    link_problems,
    page_files,
    shift_asm_consts,
    write_zip,
)


GOOD_PAGE = '<canvas id="canvas"></canvas>\n<script src="rocco.js"></script>\n'


def write_files(root, files):
    for path, text in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'w') as f:
            f.write(text)


def leb(n):
    out = bytearray()
    while True:
        byte = n & 0x7F
        n >>= 7
        if n:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def sleb(n):
    out = bytearray()
    while True:
        byte = n & 0x7F
        n >>= 7
        if (n == 0 and not byte & 0x40) or (n == -1 and byte & 0x40):
            out.append(byte)
            return bytes(out)
        out.append(byte | 0x80)


def name(text):
    return leb(len(text)) + text.encode()


def section(kind, entries):
    body = leb(len(entries)) + b''.join(entries)
    return bytes([kind]) + leb(len(body)) + body


def module(imports=(), globals_=(), exports=()):
    """A wasm module with function imports, i32 const globals and exports.

    imports is a list of (module, name). globals_ is a list of i32 values, one
    imported global first if a name in imports starts with "global:".
    exports is a list of (name, kind, index).
    """
    import_entries = []
    for mod, field in imports:
        if field.startswith('global:'):
            import_entries.append(name(mod) + name(field[7:]) + bytes([3, 0x7F, 0]))
        else:
            import_entries.append(name(mod) + name(field) + bytes([0]) + leb(0))
    global_entries = [bytes([0x7F, 0, 0x41]) + sleb(value) + bytes([0x0B]) for value in globals_]
    export_entries = [name(field) + bytes([kind]) + leb(index) for field, kind, index in exports]
    return b'\0asm' + bytes([1, 0, 0, 0]) + section(2, import_entries) + section(6, global_entries) + section(7, export_entries)


class LinkProblemsTest(unittest.TestCase):
    def test_a_matching_game_has_no_problems(self):
        reference = module(imports=[('env', 'fopen')], exports=[('main', 0, 0)])
        game = module(imports=[('env', 'fopen')], exports=[('main', 0, 0), ('roc_step', 0, 1)])
        self.assertEqual(link_problems(reference, game), [])

    def test_names_an_import_the_loader_does_not_supply_and_an_export_it_expects(self):
        reference = module(exports=[('malloc', 0, 0)])
        game = module(imports=[('env', 'wgpuDeviceRelease')])
        self.assertEqual(link_problems(reference, game), [
            'import the loader does not supply: func env.wgpuDeviceRelease',
            'export the loader expects: func malloc',
        ])


class ExportedGlobalTest(unittest.TestCase):
    def test_reads_the_value_of_an_exported_i32_global(self):
        data = module(globals_=[8, 9131000], exports=[('__start_em_asm', 3, 1)])
        self.assertEqual(exported_global(data, '__start_em_asm'), 9131000)

    def test_counts_imported_globals_before_the_module_globals(self):
        data = module(imports=[('env', 'global:__stack_pointer')], globals_=[70000], exports=[('__start_em_asm', 3, 1)])
        self.assertEqual(exported_global(data, '__start_em_asm'), 70000)

    def test_a_missing_export_is_an_error(self):
        with self.assertRaises(ValueError):
            exported_global(module(), '__start_em_asm')


class ShiftAsmConstsTest(unittest.TestCase):
    def test_moves_each_key_by_the_delta(self):
        js = 'a = 1;\nvar ASM_CONSTS = {\n  9129516: ($0) => { return 1; },\n 9131694: () => { x({ 5: 1 }); }\n};\nb = { 7: 2 };\n'
        self.assertEqual(
            shift_asm_consts(js, 100),
            'a = 1;\nvar ASM_CONSTS = {\n  9129616: ($0) => { return 1; },\n 9131794: () => { x({ 5: 1 }); }\n};\nb = { 7: 2 };\n',
        )

    def test_a_loader_with_no_asm_consts_stays_the_same(self):
        self.assertEqual(shift_asm_consts('a = 1;\n', 100), 'a = 1;\n')


class PageFilesTest(unittest.TestCase):
    def test_lists_the_page_files_that_exist_in_load_order(self):
        with tempfile.TemporaryDirectory() as page:
            for file in ['index.wasm', 'rocco.js', 'index.html', 'index.data.js', 'index.js']:
                open(os.path.join(page, file), 'w').close()
            self.assertEqual(page_files(page), ['index.html', 'rocco.js', 'index.js', 'index.wasm', 'index.data.js'])


class CopyDefaultPageTest(unittest.TestCase):
    def test_copies_the_page_and_rocco_js_from_the_target(self):
        with tempfile.TemporaryDirectory() as target, tempfile.TemporaryDirectory() as page:
            for file in ['index.html', 'rocco.js', 'index.js']:
                with open(os.path.join(target, file), 'w') as f:
                    f.write(file)
            copy_default_page(target, page)
            self.assertEqual(sorted(os.listdir(page)), ['index.html', 'rocco.js'])
            with open(os.path.join(page, 'rocco.js')) as f:
                self.assertEqual(f.read(), 'rocco.js')


class GamePageFilesTest(unittest.TestCase):
    def test_lists_every_file_under_the_web_folder_except_dotfiles(self):
        with tempfile.TemporaryDirectory() as web:
            files = {'index.html': '', 'title.png': '', 'fonts/a.woff2': '', '.DS_Store': '', 'fonts/.hidden': ''}
            write_files(web, files)
            self.assertEqual(game_page_files(web), ['fonts/a.woff2', 'index.html', 'title.png'])


class GamePageProblemsTest(unittest.TestCase):
    def problems(self, files):
        with tempfile.TemporaryDirectory() as web:
            write_files(web, files)
            return [problem.replace(web, 'WEB') for problem in game_page_problems(web, game_page_files(web))]

    def test_a_page_with_the_canvas_and_rocco_js_has_no_problems(self):
        self.assertEqual(self.problems({'index.html': GOOD_PAGE, 'style.css': ''}), [])

    def test_accepts_single_quotes_and_a_dot_slash_path(self):
        page = "<canvas class='x' id='canvas'></canvas><script defer src='./rocco.js'></script>"
        self.assertEqual(self.problems({'index.html': page}), [])

    def test_names_each_file_with_a_reserved_name(self):
        problems = self.problems({'index.html': GOOD_PAGE, 'rocco.js': '', 'index.data': ''})
        self.assertEqual(problems, [
            'WEB/index.data has a name that the build writes. Rename it.',
            'WEB/rocco.js has a name that the build writes. Rename it.',
        ])

    def test_a_reserved_name_matches_in_any_case(self):
        self.assertEqual(self.problems({'index.html': GOOD_PAGE, 'Index.JS': ''}), [
            'WEB/Index.JS has a name that the build writes. Rename it.',
        ])

    def test_a_reserved_name_in_a_subfolder_is_allowed(self):
        self.assertEqual(self.problems({'index.html': GOOD_PAGE, 'lib/index.js': ''}), [])

    def test_names_a_missing_index_html(self):
        self.assertEqual(self.problems({'title.png': ''}), ['WEB/index.html is missing. The Page needs it.'])

    def test_names_a_missing_canvas(self):
        self.assertEqual(self.problems({'index.html': '<script src="rocco.js"></script>'}), [
            'WEB/index.html has no element with id="canvas". The game draws into it.',
        ])

    def test_a_canvas_id_inside_another_attribute_does_not_count(self):
        page = '<canvas data-id="canvas"></canvas><script src="rocco.js"></script>'
        self.assertEqual(self.problems({'index.html': page}), [
            'WEB/index.html has no element with id="canvas". The game draws into it.',
        ])

    def test_a_rocco_js_data_src_does_not_count(self):
        page = '<canvas id="canvas"></canvas><script data-src="rocco.js"></script>'
        self.assertEqual(self.problems({'index.html': page}), [
            'WEB/index.html does not load rocco.js. Add <script src="rocco.js"></script>.',
        ])

    def test_accepts_a_query_string_after_rocco_js(self):
        page = '<canvas id="canvas"></canvas><script src="rocco.js?v=2"></script>'
        self.assertEqual(self.problems({'index.html': page}), [])

    def test_a_page_that_is_not_utf8_is_still_checked(self):
        with tempfile.TemporaryDirectory() as web:
            with open(os.path.join(web, 'index.html'), 'wb') as f:
                f.write(b'<canvas id="canvas"></canvas>\xff<script src="rocco.js"></script>')
            self.assertEqual(game_page_problems(web, ['index.html']), [])

    def test_names_a_missing_rocco_js_script(self):
        self.assertEqual(self.problems({'index.html': '<canvas id="canvas"></canvas><p>rocco.js</p>'}), [
            'WEB/index.html does not load rocco.js. Add <script src="rocco.js"></script>.',
        ])


class CopyGamePageTest(unittest.TestCase):
    def test_copies_the_folder_over_the_default_page(self):
        with tempfile.TemporaryDirectory() as web, tempfile.TemporaryDirectory() as page:
            write_files(web, {'index.html': 'game page', 'img/title.png': 'png'})
            write_files(page, {'index.html': 'default page', 'rocco.js': 'engine'})
            copy_game_page(web, page, game_page_files(web))
            with open(os.path.join(page, 'index.html')) as f:
                self.assertEqual(f.read(), 'game page')
            with open(os.path.join(page, 'img', 'title.png')) as f:
                self.assertEqual(f.read(), 'png')
            with open(os.path.join(page, 'rocco.js')) as f:
                self.assertEqual(f.read(), 'engine')


class WriteZipTest(unittest.TestCase):
    def test_puts_the_page_files_at_the_top_of_the_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            for file in ['index.html', 'index.js', 'index.wasm']:
                with open(os.path.join(tmp, file), 'w') as f:
                    f.write(file)
            zip_path = os.path.join(tmp, 'game.zip')
            write_zip(zip_path, tmp, ['index.html', 'index.js', 'index.wasm'])
            with zipfile.ZipFile(zip_path) as z:
                self.assertEqual(z.namelist(), ['index.html', 'index.js', 'index.wasm'])
                self.assertEqual(z.read('index.html'), b'index.html')

    def test_keeps_the_folders_of_game_page_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_files(tmp, {'index.html': '', 'img/title.png': 'png'})
            zip_path = os.path.join(tmp, 'game.zip')
            write_zip(zip_path, tmp, ['index.html', 'img/title.png'])
            with zipfile.ZipFile(zip_path) as z:
                self.assertEqual(z.read('img/title.png'), b'png')


HASH = '6AcVMzPtbKbotTHWqn131CpxMhAXcSdwDfBYuMrC6Hby'
URL = f'https://github.com/Pixelsprout/rocco-engine/releases/download/v0.14.0/platform-{HASH}.tar.zst'


class PlatformSourceTest(unittest.TestCase):
    def test_reads_the_platform_string_from_the_header(self):
        header = f'app [init, launch] {{ mesh: "https://x/mesh-abc.tar.zst", pf: platform "{URL}", roc: "nightly" }}\n'
        self.assertEqual(platform_source(header), URL)

    def test_reads_a_local_platform_path(self):
        self.assertEqual(platform_source('app [init] { pf: platform "../../platform/main.roc" }'), '../../platform/main.roc')

    def test_a_header_with_no_platform_is_an_error(self):
        with self.assertRaises(BuildError):
            platform_source('module [thing]')


class RocCachesTest(unittest.TestCase):
    def test_lists_the_caches_in_the_order_roc_looks(self):
        env = {'ROC_CACHE_DIR': '/rc', 'XDG_CACHE_HOME': '/xdg', 'LOCALAPPDATA': '/local'}
        home = os.path.join(os.path.expanduser('~'), '.cache', 'roc')
        self.assertEqual(roc_caches(env), ['/rc', os.path.join('/xdg', 'roc'), home, os.path.join('/local', 'roc')])

    def test_with_no_variables_only_the_home_cache_is_left(self):
        self.assertEqual(roc_caches({}), [os.path.join(os.path.expanduser('~'), '.cache', 'roc')])


class PlatformDirsTest(unittest.TestCase):
    def test_a_local_path_names_the_folder_of_its_main_roc(self):
        self.assertEqual(platform_dirs('examples/pong', '../../platform/main.roc', {}), ['platform'])

    def test_a_url_names_the_bundle_hash_in_each_cache(self):
        dirs = platform_dirs('.', URL, {'ROC_CACHE_DIR': '/rc'})
        self.assertEqual(dirs[0], os.path.join('/rc', 'packages', HASH))
        self.assertTrue(all(dir.endswith(HASH) for dir in dirs))

    def test_a_url_with_no_hash_is_an_error(self):
        with self.assertRaises(BuildError):
            platform_dirs('.', 'https://example.com/platform.tar.zst', {})


class ShadersTest(unittest.TestCase):
    def test_runs_the_platform_shader_build_from_relative_paths(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, 'platform', 'shader-tools'))
            os.makedirs(os.path.join(root, 'examples', 'surface'))
            with open(os.path.join(root, 'platform', 'shader-tools', 'build.py'), 'w') as f:
                f.write("open('built', 'w').close()\n")
            open(os.path.join(root, 'examples', 'surface', 'shaders.json'), 'w').close()
            here = os.getcwd()
            os.chdir(root)
            try:
                self.assertTrue(shaders('platform', os.path.join('examples', 'surface')))
            finally:
                os.chdir(here)
            self.assertTrue(os.path.isfile(os.path.join(root, 'examples', 'surface', 'built')))

    def test_a_game_with_no_shaders_json_skips_the_build(self):
        with tempfile.TemporaryDirectory() as game:
            self.assertFalse(shaders('/no-platform', game))


class FindTargetTest(unittest.TestCase):
    def test_finds_the_first_platform_with_a_wasm32_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_files(tmp, {f'b/targets/wasm32/{file}': '' for file in ['index.html', 'rocco.js', 'index.js', 'reference.wasm']})
            dirs = [os.path.join(tmp, 'a'), os.path.join(tmp, 'b')]
            self.assertEqual(find_target(dirs), (dirs[1], os.path.join(dirs[1], 'targets', 'wasm32')))

    def test_a_target_from_before_v0_14_0_is_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_files(tmp, {'targets/wasm32/host.wasm': ''})
            with self.assertRaisesRegex(BuildError, 'v0.14.0'):
                find_target([tmp])

    def test_names_each_folder_it_tried(self):
        with self.assertRaisesRegex(BuildError, '/nowhere'):
            find_target(['/nowhere'])


class AssetFilesTest(unittest.TestCase):
    def test_lists_folders_and_files_as_fs_paths_without_dotfiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_files(tmp, {'assets/b.txt': 'b', 'assets/a.txt': 'a', 'assets/sky/x.png': 'x', 'assets/.DS_Store': '', 'assets/.git/y': ''})
            dirs, files = asset_files(os.path.join(tmp, 'assets'))
            self.assertEqual(dirs, [('/', 'assets'), ('/assets', 'sky')])
            self.assertEqual([path for path, _ in files], ['/assets/a.txt', '/assets/b.txt', '/assets/sky/x.png'])

    def test_leaves_out_the_compiled_shader_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_files(tmp, {'assets/shaders/Grass.shaderpack': 'p', 'assets/shaders/Grass.manifest.json': '{}', 'assets/shaders/Grass.sources/input.glsl': 'g'})
            dirs, files = asset_files(os.path.join(tmp, 'assets'))
            self.assertEqual(dirs, [('/', 'assets'), ('/assets', 'shaders')])
            self.assertEqual([path for path, _ in files], ['/assets/shaders/Grass.manifest.json', '/assets/shaders/Grass.shaderpack'])


class PackAssetsTest(unittest.TestCase):
    def test_joins_the_files_and_lists_each_one_with_its_offsets(self):
        with tempfile.TemporaryDirectory() as game, tempfile.TemporaryDirectory() as page:
            write_files(game, {'assets/a.txt': 'aa', 'assets/sky/x.png': 'xyz'})
            pack_assets(game, page)
            with open(os.path.join(page, 'index.data'), 'rb') as f:
                self.assertEqual(f.read(), b'aaxyz')
            with open(os.path.join(page, 'index.data.js')) as f:
                js = f.read()
            self.assertIn(json.dumps([['/assets/a.txt', 0, 2], ['/assets/sky/x.png', 2, 5]]), js)
            self.assertIn(json.dumps([['/', 'assets'], ['/assets', 'sky']]), js)
            self.assertIn('"rocco:stopped"', js)
            self.assertIn('fetch("index.data")', js)
            self.assertNotIn('locateFile', js)

    def test_a_game_with_no_assets_gets_an_empty_loader_and_no_data(self):
        with tempfile.TemporaryDirectory() as game, tempfile.TemporaryDirectory() as page:
            write_files(page, {'index.data': 'old'})
            pack_assets(game, page)
            self.assertEqual(sorted(os.listdir(page)), ['index.data.js'])
            self.assertEqual(os.path.getsize(os.path.join(page, 'index.data.js')), 0)


if __name__ == '__main__':
    unittest.main()
