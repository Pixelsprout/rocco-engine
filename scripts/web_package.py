"""Turns the wasm that roc build wrote into a web page and an itch.io zip.

    python3 scripts/web_package.py <game dir> <page dir> <zip name>

<page dir> must hold the index.wasm that `roc build --target=wasm32` wrote.
The script adds the prebuilt page, rocco.js and loader from platform/targets/wasm32,
packs <game dir>/assets, if there is one, into index.data, and zips the page with index.html
at the top. If <game dir>/web exists, its files are copied over the Default page.
Run it from the repository root with emcc on PATH.
"""

import os
import re
import shutil
import subprocess
import sys
import zipfile

TARGET = 'platform/targets/wasm32'
KINDS = {0: 'func', 1: 'table', 2: 'memory', 3: 'global', 4: 'tag'}
PAGE_FILES = ['index.html', 'rocco.js', 'index.js', 'index.wasm', 'index.data', 'index.data.js']
BUILD_FILES = [file for file in PAGE_FILES if file != 'index.html']
CANVAS_ID = re.compile(r'''(?<![\w-])id\s*=\s*["']canvas["']''')
ROCCO_SCRIPT = re.compile(r'''<script\b[^>]*(?<![\w-])src\s*=\s*["'](\./)?rocco\.js([?#][^"']*)?["']''')


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


def copy_default_page(target, page_dir):
    for file in ['index.html', 'rocco.js']:
        shutil.copy(os.path.join(target, file), os.path.join(page_dir, file))


def game_page_files(web_dir):
    """Every file under web_dir as a path with / separators, without dotfiles."""
    files = []
    for root, dirs, names in os.walk(web_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for name in names:
            if not name.startswith('.'):
                files.append(os.path.relpath(os.path.join(root, name), web_dir).replace(os.sep, '/'))
    return sorted(files)


# Names compare in any case, because macOS and Windows file names do.
def game_page_problems(web_dir, files):
    problems = [f'{web_dir}/{file} has a name that the build writes. Rename it.' for file in files if file.lower() in BUILD_FILES]
    if 'index.html' not in files:
        return problems + [f'{web_dir}/index.html is missing. The Page needs it.']
    with open(os.path.join(web_dir, 'index.html'), encoding='utf-8', errors='replace') as f:
        html = f.read()
    if not CANVAS_ID.search(html):
        problems.append(f'{web_dir}/index.html has no element with id="canvas". The game draws into it.')
    if not ROCCO_SCRIPT.search(html):
        problems.append(f'{web_dir}/index.html does not load rocco.js. Add <script src="rocco.js"></script>.')
    return problems


def copy_game_page(web_dir, page_dir, files):
    for file in files:
        target = os.path.join(page_dir, file)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy(os.path.join(web_dir, file), target)


def page_files(page_dir):
    return [file for file in PAGE_FILES if os.path.exists(os.path.join(page_dir, file))]


# A game with no assets folder gets no index.data, as a native game finds no
# folder. The page always loads index.data.js, so that file is written empty.
def pack_assets(game_dir, page_dir):
    assets = os.path.join(os.path.abspath(game_dir), 'assets')
    for file in ['index.data', 'index.data.js']:
        if os.path.exists(os.path.join(page_dir, file)):
            os.remove(os.path.join(page_dir, file))
    if not os.path.isdir(assets):
        open(os.path.join(page_dir, 'index.data.js'), 'w').close()
        return
    packager = os.path.join(os.path.dirname(shutil.which('emcc')), 'tools', 'file_packager')
    subprocess.run(
        [packager, 'index.data', '--preload', f'{assets}@/assets', '--js-output=index.data.js'],
        cwd=page_dir,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main(game_dir, page_dir, zip_name):
    web_dir = os.path.join(game_dir, 'web')
    web_files = []
    if os.path.isdir(web_dir):
        web_files = game_page_files(web_dir)
        problems = game_page_problems(web_dir, web_files)
        for problem in problems:
            print(f'web_package: {problem}', file=sys.stderr)
        if problems:
            return 1
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
    copy_default_page(TARGET, page_dir)
    copy_game_page(web_dir, page_dir, web_files)
    pack_assets(game_dir, page_dir)
    zip_path = os.path.join(page_dir, zip_name)
    # page_files already holds index.html, at the top of the zip.
    write_zip(zip_path, page_dir, page_files(page_dir) + [file for file in web_files if file != 'index.html'])
    print(f'== ready: {page_dir}, {zip_path}')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    sys.exit(main(*sys.argv[1:]))
