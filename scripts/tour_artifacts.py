"""Builds the Tour artifacts into build/tour/, in the layout of the tour.tar.gz release asset.

    sh scripts/toolchain.sh run python3 scripts/tour_artifacts.py build [--out <dir>] [--tag <tag>] [--url platform=<url> ...]

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


def check_build_id(out, build_id):
    """The site checks each image against preview.js, so the worker and the Preview must agree."""
    with open(os.path.join(out, 'compile-worker', 'compile-worker.wasm'), 'rb') as f:
        if build_id.encode() + b'\0' not in f.read():
            raise BuildError(f'compile-worker/compile-worker.wasm does not hold the build id {build_id}')
    with open(os.path.join(out, 'preview', 'preview.js')) as f:
        if f'var BUILD_ID = {json.dumps(build_id)};' not in f.read():
            raise BuildError(f'preview/preview.js does not hold the build id {build_id}')


def build(out, build_id, tag, roc_nightly, urls,
          build_worker=tour_worker.build_worker, build_host=tour_host.build):
    if not SAFE_TAG.match(tag):
        raise BuildError(f'The tag {tag} is not a safe folder name for the site')
    if os.path.exists(out):
        shutil.rmtree(out)
    worker = os.path.join(out, 'compile-worker')
    build_worker(worker, build_id)
    tour_worker.write_source_bundle(ROOT, urls, os.path.join(worker, 'source-bundle.json'))
    build_host(os.path.join(out, 'preview'), build_id)
    check_build_id(out, build_id)
    with open(os.path.join(out, 'manifest.json'), 'w') as f:
        json.dump({'buildId': build_id, 'tag': tag, 'rocNightly': f'nightly-{roc_nightly}'}, f, indent=2)
        f.write('\n')


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
    args = parser.parse_args(argv)
    out = os.path.abspath(args.out)
    try:
        build(out, build_id=tour_worker.build_id(), tag=args.tag or default_tag(),
              roc_nightly=roc_patches.pin('ROC_NIGHTLY'), urls=release.parse_urls(args.url))
    except (BuildError, roc_patches.PatchError) as e:
        print(f'tour_artifacts.py: {e}', file=sys.stderr)
        return 1
    print(f'== {args.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
