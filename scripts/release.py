"""Helpers for .github/workflows/release.yml.

Run from the repository root:
  python3 scripts/release.py app <app dir> <out dir> --url platform=<url> --url linalg=<url> ...
      writes the app's .roc files to <out dir> with its header on the bundle URLs.
      A package with no URL is copied beside the app.
  python3 scripts/release.py notes <tag> <roc pin> --url platform=<url> ...
      prints the release notes.
  python3 scripts/release.py docs <api dir> <out file> <roc pin> --url platform=<url> ...
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
DOCS_BUNDLES = ["platform", "linalg", "mesh", "ui", "camera", "collide", "controller"]
# Release assets that the guide links but that have no API pages.
DOCS_TOOLS = ["rocco_web"]
# The keys of urls.json are the marker names in the guide pages, such as {{platform_url}}.
DOCS_MARKERS = [f"{name}_url" for name in DOCS_BUNDLES + DOCS_TOOLS] + ["roc_nightly"]
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


def notes(tag, roc_pin, urls):
    lines = [
        f"rocco {tag}",
        "",
        f"Built with Roc `{roc_pin}`. Use the same Roc to run an app on these bundles.",
        "",
        "| Bundle | URL |",
        "| --- | --- |",
    ]
    lines += [f"| {name} | {url} |" for name, url in urls.items()]
    return "\n".join(lines) + "\n"


def docs_markers(roc_pin, urls):
    missing = [name for name in DOCS_BUNDLES + DOCS_TOOLS if name not in urls]
    if missing:
        raise ValueError(f"no URL for {', '.join(missing)}")
    markers = {f"{name}_url": urls[name] for name in DOCS_BUNDLES + DOCS_TOOLS}
    # The site reads this key, so it keeps its nightly-era name.
    markers["roc_nightly"] = roc_pin
    return markers


def add_bytes(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    tar.addfile(info, io.BytesIO(data))


def pack_docs(api_dir, out_file, roc_pin, urls):
    data = json.dumps(docs_markers(roc_pin, urls), indent=2).encode() + b"\n"
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
    for name in DOCS_BUNDLES + DOCS_TOOLS:
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
    note.add_argument("roc_pin")
    note.add_argument("--url", action="append", default=[])
    docs = commands.add_parser("docs")
    docs.add_argument("api_dir", type=Path)
    docs.add_argument("out_file", type=Path)
    docs.add_argument("roc_pin")
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
        pack_docs(args.api_dir, args.out_file, args.roc_pin, urls)
    else:
        sys.stdout.write(notes(args.tag, args.roc_pin, urls))


if __name__ == "__main__":
    main()
