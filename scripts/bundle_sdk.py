#!/usr/bin/env python3
"""Bundle the same explicit platform inputs for releases and CI candidates."""
import argparse
from pathlib import Path
import subprocess
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ("platform", "linalg", "mesh", "ui", "camera")


def bundle(out):
    out.mkdir(parents=True, exist_ok=True)
    archives = {}
    for name in PACKAGES:
        source = ROOT / ("platform" if name == "platform" else "packages/" + name)
        inputs = sorted(source.glob("*.roc"))
        if name == "platform":
            for directory in ("targets", "shader-tools"):
                inputs += sorted(path for path in (source / directory).rglob("*")
                                 if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pdb")
        with tempfile.TemporaryDirectory(prefix="rocco-bundle-") as temporary:
            subprocess.run(["roc", "bundle", *(str(path.relative_to(source)) for path in inputs),
                            "--output-dir", temporary], cwd=source, check=True)
            generated, = Path(temporary).glob("*.tar.zst")
            destination = out / (name + "-" + generated.name)
            shutil.move(str(generated), destination)
            archives[name] = destination
    return archives


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    for archive in bundle(args.out.resolve()).values():
        print(archive)
