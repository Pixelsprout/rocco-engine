"""Helpers for .github/workflows/release.yml.

Run from the repository root:
  python3 scripts/release.py app <app dir> <out dir> --url platform=<url> --url linalg=<url> ...
      writes the app's .roc files to <out dir> with its header on the bundle URLs.
      A package with no URL is copied beside the app.
  python3 scripts/release.py notes <tag> <roc nightly> --url platform=<url> ...
      prints the release notes.
"""

import argparse
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
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
    args = parser.parse_args()

    urls = parse_urls(args.url)
    if args.command == "app":
        prepare_app(args.app_dir, args.out_dir, urls, ROOT / "packages")
    else:
        sys.stdout.write(notes(args.tag, args.nightly, urls))


if __name__ == "__main__":
    main()
