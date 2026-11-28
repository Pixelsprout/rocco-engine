"""Builds a rocco game for the web: a page folder and a zip for itch.io.

    python3 rocco_web.py [<game dir>] [--out <page dir>] [--platform <dir>] [--roc <roc>]

Run it with no arguments in a game's folder. It writes build/web/ there.

The script runs `roc build --target=wasm32`, then adds the loader, rocco.js and
the Default page from the platform's targets/wasm32 folder. It packs
<game dir>/assets into index.data and zips the page with index.html at the top.
If <game dir>/web exists, its files are copied over the Default page.

It finds the platform through the platform string in <game dir>/main.roc: a
local path, or a release URL that Roc has unpacked into its cache. It needs
Roc and Python 3, and no rocco checkout or emscripten.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

KINDS = {0: 'func', 1: 'table', 2: 'memory', 3: 'global', 4: 'tag'}
PAGE_FILES = ['index.html', 'rocco.js', 'index.js', 'index.wasm', 'index.data', 'index.data.js']
BUILD_FILES = [file for file in PAGE_FILES if file != 'index.html']
TARGET_FILES = ['index.html', 'rocco.js', 'index.js', 'reference.wasm']
CANVAS_ID = re.compile(r'''(?<![\w-])id\s*=\s*["']canvas["']''')
ROCCO_SCRIPT = re.compile(r'''<script\b[^>]*(?<![\w-])src\s*=\s*["'](\./)?rocco\.js([?#][^"']*)?["']''')
PLATFORM = re.compile(r'''\bplatform\s+"([^"]+)"''')
# Roc names a bundle by the base58 hash of its contents.
BUNDLE_HASH = re.compile(r'([1-9A-HJ-NP-Za-km-z]{32,})\.tar\.(?:zst|br|gz)$')


class BuildError(Exception):
    pass


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
        shutil.copyfile(os.path.join(target, file), os.path.join(page_dir, file))


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


def platform_source(main_roc):
    """The string after `platform` in an app header."""
    match = PLATFORM.search(main_roc)
    if not match:
        raise BuildError('main.roc names no platform. Its header needs pf: platform "...".')
    return match.group(1)


def roc_caches(env):
    """The folders Roc may keep its cache in, in the order Roc looks."""
    caches = []
    if env.get('ROC_CACHE_DIR'):
        caches.append(env['ROC_CACHE_DIR'])
    if env.get('XDG_CACHE_HOME'):
        caches.append(os.path.join(env['XDG_CACHE_HOME'], 'roc'))
    caches.append(os.path.join(os.path.expanduser('~'), '.cache', 'roc'))
    if env.get('LOCALAPPDATA'):
        caches.append(os.path.join(env['LOCALAPPDATA'], 'roc'))
    return caches


def platform_dirs(game_dir, source, env):
    """The folders that may hold the platform, most likely first."""
    if '://' not in source:
        return [os.path.dirname(os.path.normpath(os.path.join(game_dir, source)))]
    match = BUNDLE_HASH.search(source)
    if not match:
        raise BuildError(f'the platform URL {source} does not end in <hash>.tar.zst.')
    return [os.path.join(cache, 'packages', match.group(1)) for cache in roc_caches(env)]


def find_target(dirs):
    """The targets/wasm32 folder of the first platform folder that has one."""
    for platform in dirs:
        target = os.path.join(platform, 'targets', 'wasm32')
        if os.path.isdir(target):
            missing = [file for file in TARGET_FILES if not os.path.isfile(os.path.join(target, file))]
            if missing:
                raise BuildError(f'{target} has no {", ".join(missing)}. Web builds need rocco v0.14.0 or later.')
            return platform, target
    tried = ''.join(f'\n  {platform}' for platform in dirs)
    raise BuildError(f'no platform with a targets/wasm32 folder. Tried:{tried}\nPass --platform <dir> to name it.')


def asset_files(assets):
    """The folders and files under assets as FS paths below /assets, without dotfiles.
    The engine never reads a shaders/<name>.sources folder, so a page leaves it out."""
    dirs, files = [], []
    shaders = os.path.join(assets, 'shaders')
    for root, names, file_names in os.walk(assets):
        names[:] = sorted(name for name in names if not name.startswith('.') and not (root == shaders and name.endswith('.sources')))
        parent = '/' + os.path.relpath(root, os.path.dirname(assets)).replace(os.sep, '/')
        dirs += [(parent, name) for name in names]
        files += [(f'{parent}/{name}', os.path.join(root, name)) for name in sorted(file_names) if not name.startswith('.')]
    return [('/', 'assets')] + dirs, files


def data_loader(dirs, entries, locate_file=False):
    """index.data.js: it fetches index.data at once, then fills the Emscripten FS in preRun,
    before main runs. index.js reads Module.preRun when it loads, after this script.
    With locate_file, the Tour's Preview loader names index.data and index.wasm through
    globalThis.tourLocateFile. index.js reads Module.locateFile when it loads."""
    url = 'Module["locateFile"]("index.data", "")' if locate_file else '"index.data"'
    locate = ('''
	Module["locateFile"] = globalThis.tourLocateFile;''' if locate_file else '')
    return f'''(function () {{
	var Module = window.Module;{locate}
	var dirs = {json.dumps(dirs)};
	var files = {json.dumps(entries)};
	var data = fetch({url}).then(function (response) {{
		if (!response.ok) {{
			throw new Error(response.status + " " + response.url);
		}}
		return response.arrayBuffer();
	}});
	Module["preRun"] = Module["preRun"] || [];
	Module["preRun"].push(function () {{
		Module["addRunDependency"]("index.data");
		data.then(function (buffer) {{
			var bytes = new Uint8Array(buffer);
			dirs.forEach(function (dir) {{ Module["FS_createPath"](dir[0], dir[1], true, true); }});
			files.forEach(function (file) {{ Module["FS_createDataFile"](file[0], null, bytes.subarray(file[1], file[2]), true, true, true); }});
			Module["removeRunDependency"]("index.data");
		}}, function (error) {{
			console.error(error);
			window.dispatchEvent(new CustomEvent("rocco:stopped", {{ detail: {{ reason: "load", message: "The page could not load index.data." }} }}));
		}});
	}});
}})();
'''


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
    dirs, files = asset_files(assets)
    entries, offset = [], 0
    with open(os.path.join(page_dir, 'index.data'), 'wb') as out:
        for path, source in files:
            with open(source, 'rb') as f:
                data = f.read()
            out.write(data)
            entries.append([path, offset, offset + len(data)])
            offset += len(data)
    with open(os.path.join(page_dir, 'index.data.js'), 'w') as f:
        f.write(data_loader([list(dir) for dir in dirs], entries))


# roc build exits with 2 when the game has warnings and still writes the wasm.
def roc_build(roc, game_dir, page_dir):
    command = [roc, 'build', '--target=wasm32', f'--output={os.path.abspath(page_dir)}/index.wasm', 'main.roc']
    try:
        code = subprocess.run(command, cwd=game_dir).returncode
    except FileNotFoundError:
        raise BuildError(f'{roc} is not on PATH. Install the Roc nightly that the game header names, or pass --roc.')
    if code not in (0, 2):
        raise BuildError(f'roc build stopped with exit code {code}.')


def shaders(platform, game_dir):
    """Builds the game's shader packs, if it has a shaders.json. True if it did."""
    if not os.path.isfile(os.path.join(game_dir, 'shaders.json')):
        return False
    build = os.path.join(os.path.abspath(platform), 'shader-tools', 'build.py')
    if subprocess.run([sys.executable, build], cwd=game_dir).returncode != 0:
        raise BuildError('the shader build stopped. Its output above says why.')
    return True


def package(game_dir, page_dir, target):
    web_dir = os.path.join(game_dir, 'web')
    web_files = []
    if os.path.isdir(web_dir):
        web_files = game_page_files(web_dir)
        problems = game_page_problems(web_dir, web_files)
        if problems:
            raise BuildError('\n'.join(problems))
    with open(os.path.join(target, 'reference.wasm'), 'rb') as f:
        reference = f.read()
    with open(os.path.join(page_dir, 'index.wasm'), 'rb') as f:
        game = f.read()
    problems = link_problems(reference, game)
    if problems:
        problems.append('add each missing export to the wasm32 exports in platform/main.roc')
        raise BuildError('\n'.join(problems))
    delta = exported_global(game, '__start_em_asm') - exported_global(reference, '__start_em_asm')
    with open(os.path.join(target, 'index.js')) as f:
        js = shift_asm_consts(f.read(), delta)
    with open(os.path.join(page_dir, 'index.js'), 'w') as f:
        f.write(js)
    copy_default_page(target, page_dir)
    copy_game_page(web_dir, page_dir, web_files)
    pack_assets(game_dir, page_dir)
    zip_name = f'{os.path.basename(os.path.abspath(game_dir))}-web.zip'
    zip_path = os.path.join(page_dir, zip_name)
    # page_files already holds index.html, at the top of the zip.
    write_zip(zip_path, page_dir, page_files(page_dir) + [file for file in web_files if file != 'index.html'])
    return zip_path


def main(argv, env):
    parser = argparse.ArgumentParser(description='Build a rocco game for the web.')
    parser.add_argument('game_dir', nargs='?', default='.', help='the folder with main.roc (default: .)')
    parser.add_argument('--out', help='the page folder (default: <game dir>/build/web)')
    parser.add_argument('--platform', help='the platform folder, if the script cannot find it')
    parser.add_argument('--roc', default='roc', help='the roc to build with (default: roc)')
    args = parser.parse_args(argv)
    game_dir = args.game_dir
    page_dir = args.out or os.path.join(game_dir, 'build', 'web')
    main_roc = os.path.join(game_dir, 'main.roc')
    try:
        if not os.path.isfile(main_roc):
            raise BuildError(f'{main_roc} does not exist.')
        with open(main_roc, encoding='utf-8') as f:
            source = platform_source(f.read())
        os.makedirs(page_dir, exist_ok=True)
        dirs = [args.platform] if args.platform else platform_dirs(game_dir, source, env)
        built = False
        # A URL platform is in the Roc cache only after roc has fetched it.
        if not any(os.path.isdir(os.path.join(dir, 'targets', 'wasm32')) for dir in dirs):
            roc_build(args.roc, game_dir, page_dir)
            built = True
        platform, target = find_target(dirs)
        # The shader build writes Roc modules too, so roc builds after it.
        if shaders(platform, game_dir) or not built:
            roc_build(args.roc, game_dir, page_dir)
        zip_path = package(game_dir, page_dir, target)
    except BuildError as error:
        print(f'rocco_web: {error}', file=sys.stderr)
        return 1
    print(f'== ready: {page_dir}, {zip_path}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:], os.environ))
