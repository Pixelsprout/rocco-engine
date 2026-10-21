"""Helpers for .github/workflows/release.yml.

Run from the repository root:
  python3 scripts/release.py app <app dir> <out dir> --url platform=<url> --url linalg=<url> ...
      writes the app's .roc files to <out dir> with its header on the bundle URLs.
      A package with no URL is copied beside the app.
  python3 scripts/release.py notes <tag> <roc nightly> --url platform=<url> ...
      prints the release notes.
  python3 scripts/release.py docs <api dir> <out file> <roc nightly> --url platform=<url> ...
      writes docs.tar.gz: the API HTML of each bundle and urls.json.
  python3 scripts/release.py check-docs <docs.tar.gz> <release download URL> <asset name>...
      fails if the tarball is malformed or a URL in urls.json names no asset of the release.
"""

import argparse
import io
import json
import re
import shutil
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS_BUNDLES = ["platform", "linalg", "mesh", "ui", "camera"]
# The keys of urls.json are the marker names in the guide pages, such as {{platform_url}}.
DOCS_MARKERS = [f"{name}_url" for name in DOCS_BUNDLES] + ["roc_nightly"]
LOCAL_PATH = re.compile(r'"(?:\.\./)+(platform|packages/([A-Za-z0-9_-]+))/main\.roc"')


def point_header(source, urls):
    copied = []
    found_platform = False

    def replace(match):
        nonlocal found_platform
        name = match.group(2) or "platform"
        if name in urls:
            found_platform = found_platform or name == "platform"
            return f'"{urls[name]}"'
        if name == "platform":
            raise ValueError("the platform has no URL")
        copied.append(name)
        return f'"{name}/main.roc"'

    pointed = LOCAL_PATH.sub(replace, source)
    if not found_platform:
        raise ValueError("the app header names no local platform")
    return pointed, copied


# Copies only .roc files, so built binaries stay behind.
def prepare_app(app_dir, out_dir, urls, packages_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    for path in sorted(app_dir.glob("*.roc")):
        text = path.read_text()
        if path.name == "main.roc":
            text, copied = point_header(text, urls)
            for name in copied:
                shutil.copytree(packages_dir / name, out_dir / name, dirs_exist_ok=True)
        (out_dir / path.name).write_text(text)


def notes(tag, nightly, urls):
    lines = [
        f"rocco {tag}",
        "",
        f"Built with the Roc nightly `{nightly}`. Use the same nightly to run an app on these bundles.",
        "",
        "| Bundle | URL |",
        "| --- | --- |",
    ]
    lines += [f"| {name} | {url} |" for name, url in urls.items()]
    return "\n".join(lines) + "\n"


def docs_markers(nightly, urls):
    missing = [name for name in DOCS_BUNDLES if name not in urls]
    if missing:
        raise ValueError(f"no URL for {', '.join(missing)}")
    markers = {f"{name}_url": urls[name] for name in DOCS_BUNDLES}
    markers["roc_nightly"] = nightly
    return markers


def add_bytes(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    tar.addfile(info, io.BytesIO(data))


def pack_docs(api_dir, out_file, nightly, urls):
    data = json.dumps(docs_markers(nightly, urls), indent=2).encode() + b"\n"
    missing = [name for name in DOCS_BUNDLES if not (api_dir / name / "index.html").is_file()]
    if missing:
        raise ValueError(f"no API HTML for {', '.join(missing)} in {api_dir}")
    with tarfile.open(out_file, "w:gz") as tar:
        for name in DOCS_BUNDLES:
            tar.add(api_dir / name, arcname=name)
        add_bytes(tar, "urls.json", data)


# Returns one line per problem.
def check_docs(docs_file, release_base, assets):
    with tarfile.open(docs_file) as tar:
        files = set(tar.getnames())
        if "urls.json" not in files:
            return ["the tarball has no urls.json"]
        markers = json.load(tar.extractfile("urls.json"))
    problems = [f"urls.json has no {key}" for key in DOCS_MARKERS if key not in markers]
    problems += [f"urls.json has the unknown key {key}" for key in markers if key not in DOCS_MARKERS]
    for name in DOCS_BUNDLES:
        if f"{name}/index.html" not in files:
            problems.append(f"the tarball has no {name}/index.html")
        key = f"{name}_url"
        if key not in markers:
            continue
        url = markers[key]
        folder, _, asset = url.rpartition("/")
        if folder != release_base or asset not in assets:
            problems.append(f"{key} {url} names no asset of {release_base}")
    return problems


def parse_urls(pairs):
    urls = {}
    for pair in pairs:
        name, sep, url = pair.partition("=")
        if not sep or not name or not url:
            raise SystemExit(f"--url takes name=url, not {pair}")
        urls[name] = url
    return urls


def main():
    parser = argparse.ArgumentParser(description="Helpers for the release workflow.")
    commands = parser.add_subparsers(dest="command", required=True)
    app = commands.add_parser("app")
    app.add_argument("app_dir", type=Path)
    app.add_argument("out_dir", type=Path)
    app.add_argument("--url", action="append", default=[])
    note = commands.add_parser("notes")
    note.add_argument("tag")
    note.add_argument("nightly")
    note.add_argument("--url", action="append", default=[])
    docs = commands.add_parser("docs")
    docs.add_argument("api_dir", type=Path)
    docs.add_argument("out_file", type=Path)
    docs.add_argument("nightly")
    docs.add_argument("--url", action="append", default=[])
    check = commands.add_parser("check-docs")
    check.add_argument("docs_file", type=Path)
    check.add_argument("release_base")
    check.add_argument("assets", nargs="+")
    args = parser.parse_args()

    if args.command == "check-docs":
        problems = check_docs(args.docs_file, args.release_base, args.assets)
        for problem in problems:
            print(problem, file=sys.stderr)
        sys.exit(1 if problems else 0)
    urls = parse_urls(args.url)
    if args.command == "app":
        prepare_app(args.app_dir, args.out_dir, urls, ROOT / "packages")
    elif args.command == "docs":
        pack_docs(args.api_dir, args.out_file, args.nightly, urls)
    else:
        sys.stdout.write(notes(args.tag, args.nightly, urls))


if __name__ == "__main__":
    main()
