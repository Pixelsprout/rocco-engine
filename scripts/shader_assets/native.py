#!/usr/bin/env python3
"""Execute production rigid, skinned, instanced and Post assets on the native backend."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "platform/shader-tools"))
import build as asset_build
from package import HEADER, canonical, digest, fingerprint
sys.path.insert(0, str(ROOT / "scripts/shader_contract"))
import contract as proof


def decode(path):
    data = path.read_bytes()
    magic, fmt, version, header, metadata, payload, flags, mask, interface, checksum = HEADER.unpack_from(data)
    if (magic, fmt, version, header, flags, mask) != (b"RCSHADER", 1, 1, 96, 0, 7) or len(data) != header + metadata + payload or digest(data[header:]) != checksum:
        raise ValueError("invalid production shader package")
    manifest = json.loads(data[header:header + metadata])
    if canonical(manifest) != data[header:header + metadata] or fingerprint(manifest) != interface:
        raise ValueError("invalid production shader interface")
    return manifest, data[header + metadata:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shdc", type=Path, required=True)
    parser.add_argument("--sokol", type=Path, default=ROOT / "sokol-odin")
    parser.add_argument("--out", type=Path, default=ROOT / "build/shader-assets-native")
    args = parser.parse_args()
    out = args.out.resolve()
    assets = out / "assets"
    asset_build.build(ROOT / "scripts/shader_assets/example/shaders.json", assets, out / "helpers", compiler=args.shdc)
    combined = {"shaders": [{"slang": backend, "programs": []} for backend in proof.BACKENDS]}
    payload = bytearray()
    hashes = {}
    for name in ("Foliage", "Outline"):
        path = assets / (name + ".shaderpack")
        manifest, code = decode(path)
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        for shader, target in zip(manifest["shaders"], combined["shaders"]):
            for program in shader["programs"]:
                program = copy.deepcopy(program)
                for stage in ("vertex_func", "fragment_func"):
                    program[stage]["offset"] += len(payload)
                target["programs"].append(program)
        payload.extend(code)
    proof.emit_c(combined, payload, out / "proof_bindings.h")
    command = proof.native_compile_command(out, args.sokol.resolve(), sys.platform)
    command[command.index(str(ROOT / "scripts/shader_contract/native.c"))] = str(ROOT / "scripts/shader_assets/native.c")
    subprocess.run(command, check=True)
    try:
        result = subprocess.run([str(out / ("native.exe" if sys.platform == "win32" else "native.bin"))], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    except subprocess.TimeoutExpired as error:
        (out / "native.log").write_bytes(error.stdout or b"")
        raise RuntimeError("production shader proof timed out; see native.log") from error
    (out / "native.log").write_text(result.stdout)
    print(result.stdout, end="")
    result.check_returncode()
    if "PASS: 11 production shader variants" not in result.stdout:
        raise RuntimeError("production shader proof did not finish")
    (out / "native-evidence.json").write_text(json.dumps({"host": sys.platform, "result": "passed", "variants": 11,
        "instanced_attributes": 13, "frames": 3, "packages": hashes, "log": result.stdout}, indent=2) + "\n")

if __name__ == "__main__":
    main()
