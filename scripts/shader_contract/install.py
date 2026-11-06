#!/usr/bin/env python3
"""Fetch the exact compiler binary used by the portable shader proof."""
import hashlib
import json
from pathlib import Path
import platform
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
pins = json.loads((Path(__file__).parent / "compiler.json").read_text())
if sys.platform == "darwin":
    target = "osx_arm64" if platform.machine() == "arm64" else "osx"
elif sys.platform == "win32":
    target = "win32"
else:
    target = "linux_arm64" if platform.machine() in ("arm64", "aarch64") else "linux"
name = "sokol-shdc.exe" if target == "win32" else "sokol-shdc"
url = f"https://raw.githubusercontent.com/floooh/sokol-tools-bin/{pins['commit']}/bin/{target}/{name}"
data = urllib.request.urlopen(url, timeout=60).read()
if hashlib.sha256(data).hexdigest() != pins["sha256"][target]:
    raise SystemExit("pinned compiler checksum mismatch")
out = ROOT / "build/shader-tools" / name
out.parent.mkdir(parents=True, exist_ok=True)
out.write_bytes(data)
out.chmod(0o755)
print(out)
