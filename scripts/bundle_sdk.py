#!/usr/bin/env python3
"""Bundle the same explicit platform inputs for releases and CI candidates."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# A package comes after each package that it imports.
PACKAGES = ("platform", "linalg", "mesh", "ui", "camera", "collide", "controller")
SIBLING = re.compile(r'"\.\./([A-Za-z0-9_-]+)/main\.roc"')


# roc bundle refuses a file outside the package folder, so a bundled package
# names each sibling that it imports by the sibling's release URL. Without
# `base`, such a package is skipped.
def bundle(out, base=None):
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="rocco-cache-") as cache:
        return bundle_into(out, base, Path(cache))


# roc bundle downloads each URL that a header names, but the release is not
# published yet. Roc looks in its cache by hash first, so each bundle is
# unpacked into a private cache before a later package names it.
def bundle_into(out, base, cache):
    packages = cache / "roc" / "packages"
    packages.mkdir(parents=True)
    env = dict(os.environ, XDG_CACHE_HOME=str(cache))
    archives = {}
    for name in PACKAGES:
        source = ROOT / ("platform" if name == "platform" else "packages/" + name)
        inputs = sorted(source.glob("*.roc"))
        if name == "platform":
            for directory in ("targets", "shader-tools"):
                inputs += sorted(path for path in (source / directory).rglob("*")
                                 if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pdb")
        header = (source / "main.roc").read_text()
        siblings = SIBLING.findall(header)
        if siblings and base is None:
            continue
        with tempfile.TemporaryDirectory(prefix="rocco-bundle-") as temporary:
            cwd = source
            if siblings:
                cwd = Path(temporary) / "source" / name
                cwd.mkdir(parents=True)
                for path in inputs:
                    shutil.copy(path, cwd / path.name)
                urls = {sibling: base + "/" + archives[sibling].name for sibling in siblings}
                (cwd / "main.roc").write_text(SIBLING.sub(lambda match: '"' + urls[match.group(1)] + '"', header))
            output = Path(temporary) / "output"
            output.mkdir()
            subprocess.run(["roc", "bundle", *(str(path.relative_to(source)) for path in inputs),
                            "--output-dir", str(output)], cwd=cwd, check=True, env=env)
            generated, = output.glob("*.tar.zst")
            destination = out / (name + "-" + generated.name)
            shutil.move(str(generated), destination)
            archives[name] = destination
        if name == "platform":
            continue
        cached = packages / generated.name
        shutil.copy(destination, cached)
        subprocess.run(["roc", "unbundle", cached.name], cwd=packages, check=True, env=env)
        shutil.move(str(cached), packages / generated.name.removesuffix(".tar.zst") / cached.name)
    return archives


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    parser.add_argument("--base", help="the release download URL that holds the bundles")
    args = parser.parse_args()
    for archive in bundle(args.out.resolve(), args.base).values():
        print(archive)
