"""Turns the wasm that roc build wrote into a web page and an itch.io zip.

    python3 scripts/web_package.py <game dir> <page dir> <zip name>

<page dir> must hold the index.wasm that `roc build --target=wasm32` wrote.
The script adds the prebuilt page and loader from platform/targets/wasm32,
packs <game dir>/assets into index.data, and zips the page with index.html
at the top. Run it from the repository root with emcc on PATH.
"""

import os
import re
import shutil
import subprocess
import sys
import zipfile

TARGET = 'platform/targets/wasm32'
KINDS = {0: 'func', 1: 'table', 2: 'memory', 3: 'global', 4: 'tag'}
PAGE_FILES = ['index.html', 'index.js', 'index.wasm', 'index.data', 'index.data.js']


def read_leb(data, i):
    result = shift = 0
    while True:
        byte = data[i]
        i += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, i


def read_sleb(data, i):
    result = shift = 0
    while True:
        byte = data[i]
        i += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            if byte & 0x40:
                result -= 1 << shift
            return result, i


def read_name(data, i):
    length, i = read_leb(data, i)
    return data[i:i + length].decode(), i + length


def skip_limits(data, i):
    flags = data[i]
    _, i = read_leb(data, i + 1)
    if flags & 1:
        _, i = read_leb(data, i)
    return i


def skip_import_desc(data, kind, i):
    if kind == 0:
        _, i = read_leb(data, i)
    elif kind == 1:
        i = skip_limits(data, i + 1)
    elif kind == 2:
        i = skip_limits(data, i)
    elif kind == 3:
        i += 2
    elif kind == 4:
        _, i = read_leb(data, i + 1)
    return i


def sections(data):
    if data[:4] != b'\0asm':
        raise ValueError('not a wasm module')
    i = 8
    while i < len(data):
        kind = data[i]
        size, i = read_leb(data, i + 1)
        yield kind, i
        i += size


def imports_and_exports(data):
    """The imports as "kind module.name", the exports as name -> (kind, index),
    and the count of imported globals."""
    imports, exports, imported_globals = set(), {}, 0
    for kind, i in sections(data):
        if kind == 2:
            count, i = read_leb(data, i)
            for _ in range(count):
                module, i = read_name(data, i)
                field, i = read_name(data, i)
                desc = data[i]
                imported_globals += desc == 3
                i = skip_import_desc(data, desc, i + 1)
                imports.add(f'{KINDS[desc]} {module}.{field}')
        elif kind == 7:
            count, i = read_leb(data, i)
            for _ in range(count):
                field, i = read_name(data, i)
                desc = data[i]
                index, i = read_leb(data, i + 1)
                exports[field] = (desc, index)
    return imports, exports, imported_globals


def link_problems(reference, game):
    """The prebuilt loader was written for the reference link. It supplies only
    the reference imports, and it calls the reference exports."""
    ref_imports, ref_exports, _ = imports_and_exports(reference)
    game_imports, game_exports, _ = imports_and_exports(game)
    expected = {f'{KINDS[kind]} {field}' for field, (kind, _) in ref_exports.items()}
    found = {f'{KINDS[kind]} {field}' for field, (kind, _) in game_exports.items()}
    problems = [f'import the loader does not supply: {item}' for item in sorted(game_imports - ref_imports)]
    problems += [f'export the loader expects: {item}' for item in sorted(expected - found)]
    return problems


def exported_global(data, field):
    """The i32.const value of an exported global that the module defines."""
    _, exports, imported_globals = imports_and_exports(data)
    if exports.get(field, (None,))[0] != 3:
        raise ValueError(f'the module exports no global {field}')
    wanted = exports[field][1] - imported_globals
    for kind, i in sections(data):
        if kind != 6:
            continue
        count, i = read_leb(data, i)
        for index in range(count):
            i += 2  # value type and mutability
            if data[i] != 0x41:
                raise ValueError(f'global {field} is not an i32.const')
            value, i = read_sleb(data, i + 1)
            i += 1  # end
            if index == wanted:
                return value
    raise ValueError(f'the module defines no global {field}')


def shift_asm_consts(js, delta):
    """The loader finds each EM_ASM block by the address of its code string.
    The Roc link moves the strings, so each key moves by the same delta."""
    start = js.find('var ASM_CONSTS = {\n')
    if start < 0:
        return js
    end = js.index('\n};\n', start)
    body = re.sub(r'^(\s*)(\d+):', lambda m: f'{m.group(1)}{int(m.group(2)) + delta}:', js[start:end], flags=re.M)
    return js[:start] + body + js[end:]


def write_zip(zip_path, page_dir, files):
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
        for file in files:
            z.write(os.path.join(page_dir, file), file)


def pack_assets(game_dir, page_dir):
    assets = os.path.join(game_dir, 'assets')
    packager = os.path.join(os.path.dirname(shutil.which('emcc')), 'tools', 'file_packager')
    if not os.path.isdir(assets):
        raise SystemExit(f'web_package: {assets} does not exist')
    subprocess.run(
        [packager, 'index.data', '--preload', f'{os.path.abspath(assets)}@/assets', '--js-output=index.data.js'],
        cwd=page_dir,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main(game_dir, page_dir, zip_name):
    with open(os.path.join(TARGET, 'reference.wasm'), 'rb') as f:
        reference = f.read()
    with open(os.path.join(page_dir, 'index.wasm'), 'rb') as f:
        game = f.read()
    problems = link_problems(reference, game)
    for problem in problems:
        print(f'web_package: {problem}', file=sys.stderr)
    if problems:
        print('web_package: add each missing export to the wasm32 exports in platform/main.roc', file=sys.stderr)
        return 1
    delta = exported_global(game, '__start_em_asm') - exported_global(reference, '__start_em_asm')
    with open(os.path.join(TARGET, 'index.js')) as f:
        js = shift_asm_consts(f.read(), delta)
    with open(os.path.join(page_dir, 'index.js'), 'w') as f:
        f.write(js)
    shutil.copy(os.path.join(TARGET, 'index.html'), os.path.join(page_dir, 'index.html'))
    pack_assets(game_dir, page_dir)
    zip_path = os.path.join(page_dir, zip_name)
    write_zip(zip_path, page_dir, PAGE_FILES)
    print(f'== ready: {page_dir}, {zip_path}')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    sys.exit(main(*sys.argv[1:]))
