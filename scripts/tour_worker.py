"""Builds the Tour compile worker and its source bundle.

    python3 scripts/tour_worker.py build [--out <dir>] [--url platform=<url> ...]
        writes <dir>/compile-worker.wasm, <dir>/compile-worker.mjs and
        <dir>/source-bundle.json. The default <dir> is build/tour/compile-worker.
    python3 scripts/tour_worker.py bundle <out.json> [--url platform=<url> ...]
        writes only the source bundle.

Each --url maps a pinned header URL to the bundle folder of that package, so a
Tour step can name the release URLs. It needs the pinned Zig (ZIG_VERSION in
scripts/linux/Dockerfile) on PATH, or in ZIG. The first build downloads the
pinned Roc package and takes a few minutes.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import release
import roc_patches

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKER_DIR = os.path.join(ROOT, 'tour', 'compile-worker')
ZON = os.path.join(WORKER_DIR, 'build.zig.zon')
DEFAULT_OUT = os.path.join(ROOT, 'build', 'tour', 'compile-worker')
# Intermediate files stay out of build/tour/, which holds only the Tour artifacts.
WORK = os.path.join(ROOT, 'build', 'tour-work')
# The root the worker mounts the bundle at. App headers resolve against it.
BUNDLE_ROOT = '/rocco'
# Host link inputs and tools, not Roc modules of the platform or a package.
SKIPPED_DIRS = {'targets', 'shader-tools', 'assets'}
ROC_URL = re.compile(r'\.url\s*=\s*"https://codeload\.github\.com/roc-lang/roc/tar\.gz/([0-9a-f]+)"')


def zon_roc_commit(text=None):
    if text is None:
        with open(ZON) as f:
            text = f.read()
    match = ROC_URL.search(text)
    if not match:
        raise ValueError(f'{ZON} has no roc-lang/roc codeload URL')
    return match.group(1)


def package_dirs(root):
    dirs = {'platform': 'platform'}
    packages = os.path.join(root, 'packages')
    for name in sorted(os.listdir(packages)):
        if os.path.isfile(os.path.join(packages, name, 'main.roc')):
            dirs[name] = f'packages/{name}'
    return dirs


def roc_files(root, rel_dir):
    for dirpath, dirnames, filenames in os.walk(os.path.join(root, rel_dir)):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIPPED_DIRS)
        for name in sorted(filenames):
            if name.endswith('.roc'):
                yield os.path.relpath(os.path.join(dirpath, name), root).replace(os.sep, '/')


def source_bundle(root, urls):
    dirs = package_dirs(root)
    unknown = sorted(set(urls) - set(dirs))
    if unknown:
        raise ValueError(f'no platform or package folder for --url {", ".join(unknown)}')
    files = {}
    for rel_dir in dirs.values():
        for rel in roc_files(root, rel_dir):
            with open(os.path.join(root, rel), encoding='utf-8') as f:
                files[f'{BUNDLE_ROOT}/{rel}'] = f.read()
    mounts = {url: f'{BUNDLE_ROOT}/{dirs[name]}' for name, url in urls.items()}
    return {'files': dict(sorted(files.items())), 'urls': mounts}


def write_source_bundle(root, urls, out):
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(source_bundle(root, urls), f, separators=(',', ':'), sort_keys=True)
        f.write('\n')


def build_id():
    return subprocess.run(['git', 'describe', '--always', '--dirty'], cwd=ROOT, check=True,
                          capture_output=True, text=True).stdout.strip()


def check_zig(zig):
    want = roc_patches.pin('ZIG_VERSION')
    got = subprocess.run([zig, 'version'], check=True, capture_output=True, text=True).stdout.strip()
    if got != want:
        raise SystemExit(f'tour_worker.py: {zig} is Zig {got}, the pin is ZIG_VERSION={want}')


def empty_roc_deps():
    """Roc's build.zig needs an LLVM bundle at configure time unless it gets a
    local one. The Tour links no LLVM, so an empty bundle skips the fetch."""
    deps = os.path.join(WORK, 'roc-deps-empty')
    for sub in ('include', 'lib'):
        os.makedirs(os.path.join(deps, sub), exist_ok=True)
    return deps


def build_worker(out, build_id):
    zig = os.environ.get('ZIG', 'zig')
    check_zig(zig)
    deps = empty_roc_deps()
    prefix = os.path.join(WORK, 'zig-out')
    subprocess.run([zig, 'build', '--prefix', prefix, f'-Droc-deps-path={deps}', f'-Dbuild-id={build_id}'],
                   cwd=WORKER_DIR, check=True)
    os.makedirs(out, exist_ok=True)
    shutil.copyfile(os.path.join(prefix, 'compile-worker.wasm'), os.path.join(out, 'compile-worker.wasm'))
    shutil.copyfile(os.path.join(WORKER_DIR, 'js', 'compile-worker.mjs'), os.path.join(out, 'compile-worker.mjs'))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('build')
    build.add_argument('--out', default=DEFAULT_OUT)
    build.add_argument('--url', action='append', default=[])
    bundle = commands.add_parser('bundle')
    bundle.add_argument('out')
    bundle.add_argument('--url', action='append', default=[])
    args = parser.parse_args(argv)
    urls = release.parse_urls(args.url)
    if args.command == 'build':
        build_worker(args.out, build_id())
        write_source_bundle(ROOT, urls, os.path.join(args.out, 'source-bundle.json'))
        print(f'== {args.out}')
    else:
        write_source_bundle(ROOT, urls, args.out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
