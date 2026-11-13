import os
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from web_package import exported_global, link_problems, shift_asm_consts, write_zip


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


if __name__ == '__main__':
    unittest.main()
