"""Applies rocco's carried Roc patches to a copy of the pinned Roc.

    python3 scripts/roc_patches.py apply <out dir> [--roc-src <dir>]
    python3 scripts/roc_patches.py check [--roc-src <dir>]

apply copies the pinned Roc source into <out dir> and applies every patch in
tour/roc-patches/ in name order. check does the same in a temporary folder.
Both fail on the first patch that does not apply. Without --roc-src, the
pinned commit (ROC_COMMIT in scripts/linux/Dockerfile) is downloaded once
into build/roc-src/.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATCH_DIR = os.path.join(ROOT, 'tour', 'roc-patches')
DOCKERFILE = os.path.join(ROOT, 'scripts', 'linux', 'Dockerfile')
SOURCE_CACHE = os.path.join(ROOT, 'build', 'roc-src')


class PatchError(Exception):
    pass


def pin(name):
    prefix = f'ARG {name}='
    with open(DOCKERFILE) as f:
        for line in f:
            if line.startswith(prefix):
                return line[len(prefix):].strip()
    raise PatchError(f'{DOCKERFILE} has no {prefix} line')


def patches(patch_dir):
    names = sorted(n for n in os.listdir(patch_dir) if n.endswith('.patch'))
    if not names:
        raise PatchError(f'{patch_dir} holds no .patch file')
    for name in names:
        with open(os.path.join(patch_dir, name)) as f:
            header = []
            for line in f:
                if line.startswith(('--- ', 'diff ')):
                    break
                header.append(line)
        if not any(line.startswith('Upstream:') for line in header):
            raise PatchError(f'{name}: the header before the diff needs an Upstream: line')
    return names


def git_apply(roc_dir, patch, *flags):
    # The ceiling stops git from treating an enclosing repository as the
    # target, which would apply the patch relative to that repository's root.
    env = dict(os.environ, GIT_CEILING_DIRECTORIES=os.path.dirname(os.path.abspath(roc_dir)))
    return subprocess.run(['git', 'apply', *flags, patch], cwd=roc_dir, env=env, capture_output=True, text=True)


def copy_and_apply(roc_src, out, patch_dir=PATCH_DIR):
    names = patches(patch_dir)
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(roc_src, out, symlinks=True)
    for name in names:
        patch = os.path.join(patch_dir, name)
        for flags in (('--check',), ()):
            result = git_apply(out, patch, *flags)
            if result.returncode != 0:
                raise PatchError(f'{name} does not apply to the pinned Roc:\n{result.stderr.strip()}')
        print(f'applied {name}', flush=True)


def pinned_roc_source():
    commit = pin('ROC_COMMIT')
    src = os.path.join(SOURCE_CACHE, commit)
    if os.path.isfile(os.path.join(src, 'build.zig')):
        return src
    os.makedirs(SOURCE_CACHE, exist_ok=True)
    partial = src + '.partial'
    if os.path.exists(partial):
        shutil.rmtree(partial)
    url = f'https://codeload.github.com/roc-lang/roc/tar.gz/{commit}'
    print(f'== {url}', flush=True)
    with tempfile.TemporaryFile() as archive:
        with urllib.request.urlopen(url) as response:
            shutil.copyfileobj(response, archive)
        archive.seek(0)
        with tarfile.open(fileobj=archive, mode='r:gz') as tar:
            tar.extractall(partial, filter='tar')
    top, = os.listdir(partial)
    os.rename(os.path.join(partial, top), src)
    os.rmdir(partial)
    return src


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['apply', 'check'])
    parser.add_argument('out', nargs='?')
    parser.add_argument('--roc-src', help='an unpatched Roc tree at the pin, instead of the download')
    args = parser.parse_args(argv)
    if args.command == 'apply' and not args.out:
        parser.error('apply needs an <out dir>')
    try:
        src = args.roc_src or pinned_roc_source()
        if args.command == 'apply':
            copy_and_apply(src, args.out)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                copy_and_apply(src, os.path.join(tmp, 'roc'))
    except PatchError as e:
        print(f'roc_patches.py: {e}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
