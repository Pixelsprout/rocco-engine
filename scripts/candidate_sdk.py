#!/usr/bin/env python3
"""Publish candidate SDK inputs and a self-contained external authoring fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile

from bundle_sdk import ROOT, bundle

FIXTURE_FILES = (
    "main.roc", "shaders.json", "wind.glsl", "leaves.glsl", "outline.glsl", "selection.glsl",
    "proof.py", "bridge.py", "README.md", "assets/meshes/tree.glb", "source/make_tree.py",
)


def candidate(out):
    for target, host in (('arm64mac', 'libhost.a'), ('x64glibc', 'libhost.a'), ('x64win', 'host.lib')):
        path = ROOT / 'platform/targets' / target / host
        if not path.is_file():
            raise FileNotFoundError('candidate requires ordinary release target: ' + str(path))
    archives = bundle(out)
    fixture = ROOT / "examples/authoring"
    with tarfile.open(out / "authoring-fixture.tar.gz", "w:gz") as archive:
        for name in FIXTURE_FILES:
            archive.add(fixture / name, arcname="authoring/" + name)
    pin = next(line.split("=", 1)[1] for line in (ROOT / "scripts/linux/Dockerfile").read_text().splitlines()
               if line.startswith("ARG ROC_NIGHTLY="))
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    metadata = dict(kind="draft-PR candidate; not a stable release", commit=commit, roc_nightly=pin,
                    run_id=os.environ.get("GITHUB_RUN_ID"), run_attempt=os.environ.get("GITHUB_RUN_ATTEMPT"),
                    repository=os.environ.get("GITHUB_REPOSITORY"),
                    run_url=f"https://github.com/{os.environ.get('GITHUB_REPOSITORY')}/actions/runs/{os.environ.get('GITHUB_RUN_ID')}",
                    bundles={name: path.name for name, path in archives.items()},
                    fixture="authoring-fixture.tar.gz", targets="ordinary release host; no Spans")
    (out / "candidate.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (out / "SHA256SUMS").write_text("".join(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n"
                                          for path in sorted(out.iterdir()) if path.is_file() and path.name != "SHA256SUMS"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    candidate(args.out.resolve())
