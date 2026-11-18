"""Builds the Tour host: the web host linked with Roc's wasm32 interpreter shim.

    python3 scripts/tour_host.py build [--out <dir>]
        writes the Preview folder <dir> (default build/tour/preview): host.html,
        preview.js, rocco.js, index.js, index.wasm, index.data and index.data.js.

It applies the carried Roc patches to the pinned Roc, builds the shim archive
with the pinned Zig, runs scripts/web/build-host.sh release (so the normal web
host in platform/targets/wasm32 is rebuilt, unchanged), then links the same
objects with the shim and tour/host/tour_glue.c. It fails if the Tour host has
a memory.grow instruction. Run it through scripts/toolchain.sh run, so odin and
emcc are the pins. On localhost, open host.html?image=<url> to run an image.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import roc_patches
import rocco_web
import tour_worker

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOST_DIR = os.path.join(ROOT, 'tour', 'host')
WORK = os.path.join(ROOT, 'build', 'tour')
DEFAULT_OUT = os.path.join(WORK, 'preview')
WEB_HOST_OBJECTS = os.path.join(ROOT, 'build', 'web-host')
SHIM = 'libroc_interpreter_shim_wasm32_freestanding.a'


class BuildError(Exception):
    pass


def write_shared_data(root, out):
    """One index.data for every Tour step: the union of the Tutorial steps' assets folders.
    The FS paths it holds, in order."""
    tutorial = os.path.join(root, 'examples', 'tutorial')
    dirs, files, owner = [], [], {}
    for step in sorted(os.listdir(tutorial)):
        assets = os.path.join(tutorial, step, 'assets')
        if not os.path.isdir(assets):
            continue
        step_dirs, step_files = rocco_web.asset_files(assets)
        dirs += [d for d in step_dirs if d not in dirs]
        for path, source in step_files:
            if path not in owner:
                owner[path] = (step, source)
                files.append((path, source))
                continue
            first_step, first = owner[path]
            with open(first, 'rb') as a, open(source, 'rb') as b:
                if a.read() != b.read():
                    raise BuildError(f'{path} differs between {first_step} and {step}. '
                                     'Every Tour step shares one data file, so give one of them another name.')
    entries, offset = [], 0
    with open(os.path.join(out, 'index.data'), 'wb') as data:
        for path, source in files:
            with open(source, 'rb') as f:
                chunk = f.read()
            data.write(chunk)
            entries.append([path, offset, offset + len(chunk)])
            offset += len(chunk)
    with open(os.path.join(out, 'index.data.js'), 'w') as f:
        f.write(rocco_web.data_loader([list(d) for d in dirs], entries))
    return [path for path, _ in files]


def wasm_dis():
    """emsdk's wasm-dis (binaryen), or None."""
    found = shutil.which('wasm-dis')
    if found:
        return found
    em_config = shutil.which('em-config')
    if not em_config:
        return None
    llvm = subprocess.run([em_config, 'LLVM_ROOT'], capture_output=True, text=True).stdout.strip()
    candidate = os.path.join(llvm, 'wasm-dis')
    return candidate if os.path.isfile(candidate) else None


def check_no_memory_grow(wasm):
    """emscripten grows memory only from JS. A memory.grow in wasm code takes
    pages behind its sbrk, and a later malloc hands the same pages out again."""
    dis = wasm_dis()
    if not dis:
        raise BuildError('wasm-dis is not on PATH. Run the build through scripts/toolchain.sh run.')
    text = subprocess.run([dis, wasm], check=True, capture_output=True, text=True).stdout
    count = text.count('memory.grow')
    if count:
        raise BuildError(f'{wasm} has {count} memory.grow instructions. Only emscripten may grow '
                         'the Tour host memory. Route the allocation to the host heap (memalign).')


def emscripten_env(env):
    """emscripten fails when EM_CACHE goes through a symlink, such as /tmp on macOS."""
    env = dict(env)
    if env.get('EM_CACHE'):
        env['EM_CACHE'] = os.path.realpath(env['EM_CACHE'])
    return env


def check_glue_abi(glue, abi):
    """Each ROC_TYPE in the glue must have the wasm32 size that the generated ABI asserts."""
    with open(abi) as f:
        sizes = dict(re.findall(r'#assert\(size_of\(([\w()]+)\) == \(\d+ when ROC_POINTER_64 else (\d+)\)\)', f.read()))
    sizes['Roc_List'] = sizes.get('Roc_List(u8)')
    with open(glue) as f:
        declared = re.findall(r'^ROC_TYPE\((\w+), (\d+)\);', f.read(), re.M)
    if not declared:
        raise BuildError(f'{glue} declares no ROC_TYPE')
    for name, size in declared:
        want = sizes.get(name)
        if want is None:
            raise BuildError(f'{abi} asserts no size for {name}')
        if size != want:
            raise BuildError(f'{name} is {size} bytes in {glue}, and {want} bytes on wasm32 in {abi}.')


def patched_roc():
    """The pinned Roc with the carried patches, applied again only when a patch or the pin changes."""
    tree = os.path.join(WORK, 'roc')
    stamp = hashlib.sha256(roc_patches.pin('ROC_COMMIT').encode())
    for name in roc_patches.patches(roc_patches.PATCH_DIR):
        with open(os.path.join(roc_patches.PATCH_DIR, name), 'rb') as f:
            stamp.update(name.encode() + f.read())
    stamp_file = os.path.join(tree, '.rocco-patches')
    if os.path.isfile(stamp_file):
        with open(stamp_file) as f:
            if f.read() == stamp.hexdigest():
                return tree
    roc_patches.copy_and_apply(roc_patches.pinned_roc_source(), tree)
    with open(stamp_file, 'w') as f:
        f.write(stamp.hexdigest())
    return tree


def build_shim():
    zig = os.environ.get('ZIG', 'zig')
    tour_worker.check_zig(zig)
    tree = patched_roc()
    # An empty LLVM bundle skips the LLVM fetch. The shim links no LLVM.
    deps = os.path.join(WORK, 'roc-deps-empty')
    for sub in ('include', 'lib'):
        os.makedirs(os.path.join(deps, sub), exist_ok=True)
    print('== zig: wasm32 interpreter shim', flush=True)
    subprocess.run([zig, 'build', 'tour-shim-wasm32-freestanding', '-Doptimize=ReleaseFast', f'-Droc-deps-path={deps}'],
                   cwd=tree, check=True)
    return os.path.join(tree, 'zig-out', 'lib', SHIM)


def link_host(shim, out, env):
    """The emcc reference link of scripts/web/build-host.sh, with the shim and the glue
    defining the six game calls. So no symbol may stay undefined."""
    obj = WEB_HOST_OBJECTS
    glue = os.path.join(WORK, 'tour_glue.o')
    subprocess.run(['emcc', '-c', '-O2', os.path.join(HOST_DIR, 'tour_glue.c'), '-o', glue], check=True, env=env)
    objects = [os.path.join(obj, f'{name}.o') for name in (
        'main', 'rocco_web', 'engine', 'sokol_log', 'sokol_gfx', 'sokol_app', 'sokol_glue', 'miniaudio', 'stb_image')]
    objects.append(os.path.join(ROOT, 'clay', 'bindings', 'odin', 'clay-odin', 'wasm', 'clay.o'))
    print('== emcc: Tour host', flush=True)
    subprocess.run(['emcc', *objects, glue, shim, '-o', os.path.join(out, 'index.js'),
                    '--use-port=emdawnwebgpu', '-lwebsocket.js', '-sDEFAULT_TO_CXX', '-sALLOW_MEMORY_GROWTH=1',
                    '-sSTACK_SIZE=8MB', '-sFORCE_FILESYSTEM=1'], check=True, env=env)


def write_page(out, build_id):
    shutil.copyfile(os.path.join(HOST_DIR, 'host.html'), os.path.join(out, 'host.html'))
    shutil.copyfile(os.path.join(ROOT, 'scripts', 'web', 'rocco.js'), os.path.join(out, 'rocco.js'))
    with open(os.path.join(HOST_DIR, 'preview.js')) as f:
        loader = f.read()
    if '"@BUILD_ID@"' not in loader:
        raise BuildError('tour/host/preview.js has no "@BUILD_ID@" to fill in')
    with open(os.path.join(out, 'preview.js'), 'w') as f:
        f.write(loader.replace('"@BUILD_ID@"', json.dumps(build_id)))


def build(out):
    check_glue_abi(os.path.join(HOST_DIR, 'tour_glue.c'), os.path.join(ROOT, 'engine', 'roc_platform_abi.odin'))
    env = emscripten_env(os.environ)
    shim = build_shim()
    subprocess.run(['sh', 'scripts/web/build-host.sh', 'release'], cwd=ROOT, check=True, env=env)
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    link_host(shim, out, env)
    check_no_memory_grow(os.path.join(out, 'index.wasm'))
    write_page(out, tour_worker.build_id())
    write_shared_data(ROOT, out)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    command = commands.add_parser('build')
    command.add_argument('--out', default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    try:
        build(os.path.abspath(args.out))
    except (BuildError, roc_patches.PatchError) as e:
        print(f'tour_host.py: {e}', file=sys.stderr)
        return 1
    print(f'== {args.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
