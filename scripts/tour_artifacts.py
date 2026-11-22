"""Builds the Tour artifacts into build/tour/, in the layout of the tour.tar.gz release asset.

    sh scripts/toolchain.sh run python3 scripts/tour_artifacts.py build [--out <dir>] [--tag <tag>] [--url platform=<url> ...]
    python3 scripts/tour_artifacts.py pack <dir> <tour.tar.gz> --tag <tag> --url platform=<url> ...
        writes the source bundle again with the release URLs and tars <dir>.
    python3 scripts/tour_artifacts.py check <tour.tar.gz> --tag <tag>
        checks a tarball against the contract with the site.

<dir> (default build/tour) then holds only:
    manifest.json     { "buildId", "tag", "rocNightly" }
    compile-worker/   compile-worker.wasm, compile-worker.mjs, source-bundle.json
    preview/          host.html, preview.js, rocco.js, index.js, index.wasm, index.data, index.data.js

The release job tars the contents of <dir> with no top-level folder. The
compile worker and the Preview get one build id, git describe --always --dirty.
The tag defaults to git describe --tags --always --dirty; the release job passes
the release tag. Each --url maps a pinned header URL to its bundle folder, the
same names as release.py docs. Intermediate files go to build/tour-work/.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import release
import roc_patches
import tour_host
import tour_worker

ROOT = tour_worker.ROOT
DEFAULT_OUT = os.path.join(ROOT, 'build', 'tour')
# The site serves the artifacts from a folder named after the tag.
SAFE_TAG = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')

BuildError = tour_host.BuildError

LAYOUT = frozenset(['manifest.json'] +
                   [f'compile-worker/{n}' for n in ('compile-worker.wasm', 'compile-worker.mjs', 'source-bundle.json')] +
                   [f'preview/{n}' for n in ('host.html', 'preview.js', 'rocco.js', 'index.js', 'index.wasm',
                                             'index.data', 'index.data.js')])
MANIFEST_KEYS = ('buildId', 'rocNightly', 'tag')
SOURCE_BUNDLE = 'compile-worker/source-bundle.json'


def check_build_id(out, build_id):
    """The site checks each image against preview.js, so the worker and the Preview must agree."""
    with open(os.path.join(out, 'compile-worker', 'compile-worker.wasm'), 'rb') as f:
        if build_id.encode() + b'\0' not in f.read():
            raise BuildError(f'compile-worker/compile-worker.wasm does not hold the build id {build_id}')
    with open(os.path.join(out, 'preview', 'preview.js')) as f:
        if f'var BUILD_ID = {json.dumps(build_id)};' not in f.read():
            raise BuildError(f'preview/preview.js does not hold the build id {build_id}')


def check_tag(tag):
    if not SAFE_TAG.match(tag):
        raise BuildError(f'The tag {tag} is not a safe folder name for the site')


def build(out, build_id, tag, roc_pin, urls,
          build_worker=tour_worker.build_worker, build_host=tour_host.build):
    check_tag(tag)
    if os.path.exists(out):
        shutil.rmtree(out)
    worker = os.path.join(out, 'compile-worker')
    build_worker(worker, build_id)
    tour_worker.write_source_bundle(ROOT, urls, os.path.join(worker, 'source-bundle.json'))
    build_host(os.path.join(out, 'preview'), build_id)
    check_build_id(out, build_id)
    with open(os.path.join(out, 'manifest.json'), 'w') as f:
        json.dump({'buildId': build_id, 'tag': tag, 'rocNightly': roc_pin}, f, indent=2)
        f.write('\n')


def check_layout(names):
    """The site extracts the tarball root to its tag folder, so the tarball holds exactly LAYOUT."""
    names = set(names)
    missing, extra = sorted(LAYOUT - names), sorted(names - LAYOUT)
    if missing or extra:
        raise BuildError('The Tour artifacts do not have the tour.tar.gz layout.'
                         + (f' Missing: {", ".join(missing)}.' if missing else '')
                         + (f' Not in the layout: {", ".join(extra)}.' if extra else ''))


def check_manifest(manifest, tag):
    """The site build fails on any other manifest.json shape."""
    if (not isinstance(manifest, dict) or tuple(sorted(manifest)) != MANIFEST_KEYS
            or not all(isinstance(v, str) and v for v in manifest.values())):
        raise BuildError(f'manifest.json must be {{"buildId", "tag", "rocNightly"}} with string values, not {manifest}')
    if manifest['tag'] != tag:
        raise BuildError(f'manifest.json has the tag {manifest["tag"]}, and the release tag is {tag}')
    check_tag(tag)


def check_source_bundle(bundle):
    mounted = set(bundle.get('urls', {}).values())
    want = {'/rocco/platform' if n == 'platform' else f'/rocco/packages/{n}' for n in release.DOCS_BUNDLES}
    if not want <= mounted:
        raise BuildError(f'{SOURCE_BUNDLE} mounts no URL at {", ".join(sorted(want - mounted))}')


def pack(out, tar_file, tag, urls):
    """Writes tour.tar.gz from a built folder: the source bundle with the release URLs of
    release.py docs, and the files at the root."""
    missing = [name for name in release.DOCS_BUNDLES if name not in urls]
    if missing:
        raise BuildError(f'pack needs --url for {", ".join(missing)}')
    names = [os.path.relpath(os.path.join(d, n), out).replace(os.sep, '/')
             for d, _, files in os.walk(out) for n in files]
    check_layout(names)
    with open(os.path.join(out, 'manifest.json')) as f:
        check_manifest(json.load(f), tag)
    tour_worker.write_source_bundle(ROOT, {name: urls[name] for name in release.DOCS_BUNDLES},
                                    os.path.join(out, SOURCE_BUNDLE))
    with tarfile.open(tar_file, 'w:gz') as tar:
        for name in sorted(names):
            tar.add(os.path.join(out, name), arcname=name)
    check(tar_file, tag)


def check(tar_file, tag):
    with tarfile.open(tar_file) as tar:
        members = {m.name: m for m in tar.getmembers() if m.isfile()}
        check_layout(members)
        check_manifest(json.load(tar.extractfile(members['manifest.json'])), tag)
        check_source_bundle(json.load(tar.extractfile(members[SOURCE_BUNDLE])))


def default_tag():
    return subprocess.run(['git', 'describe', '--tags', '--always', '--dirty'], cwd=ROOT, check=True,
                          capture_output=True, text=True).stdout.strip()


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    command = commands.add_parser('build')
    command.add_argument('--out', default=DEFAULT_OUT)
    command.add_argument('--tag')
    command.add_argument('--url', action='append', default=[])
    command = commands.add_parser('pack')
    command.add_argument('dir')
    command.add_argument('tar_file')
    command.add_argument('--tag', required=True)
    command.add_argument('--url', action='append', default=[])
    command = commands.add_parser('check')
    command.add_argument('tar_file')
    command.add_argument('--tag', required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == 'build':
            build(os.path.abspath(args.out), build_id=tour_worker.build_id(), tag=args.tag or default_tag(),
                  roc_pin=roc_patches.pin('ROC_PIN'), urls=release.parse_urls(args.url))
            print(f'== {args.out}')
        elif args.command == 'pack':
            pack(os.path.abspath(args.dir), args.tar_file, args.tag, release.parse_urls(args.url))
            print(f'== {args.tar_file}')
        else:
            check(args.tar_file, args.tag)
            print(f'{args.tar_file}: OK')
    except (BuildError, roc_patches.PatchError, OSError, tarfile.TarError, json.JSONDecodeError) as e:
        print(f'tour_artifacts.py: {e}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
