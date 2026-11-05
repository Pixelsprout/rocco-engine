#!/usr/bin/env python3
"""Generate the built-in shaders with compact portable GL storage bindings."""

import argparse
import re
import subprocess
from pathlib import Path

STORAGE = {"engine_points": (12, 0), "engine_clusters": (13, 1), "engine_indices": (14, 2)}


def compact_source(source):
    for name, (logical, physical) in STORAGE.items():
        pattern = rf"layout\(binding = {logical}, std430\) readonly buffer {name}"
        source, count = re.subn(pattern, f"layout(binding = {physical}, std430) readonly buffer {name}", source)
        if count != 1:
            raise ValueError(f"{name}: expected one GL storage declaration, found {count}")
    return source


def compact_odin(text):
    pattern = re.compile(r"(\w+_source_glsl430) := \[(\d+)\]u8 \{\n(.*?)\n\}", re.S)
    changed = 0

    def replace(match):
        nonlocal changed
        data = bytes(int(value, 16) for value in re.findall(r"0x([0-9a-f]{2})", match[3]))
        if len(data) != int(match[2]) or not data.endswith(b"\0"):
            raise ValueError("unexpected generated GL source encoding")
        source = data[:-1].decode()
        if "readonly buffer engine_points" not in source:
            return match[0]
        output = compact_source(source).encode() + b"\0"
        rows = ["    " + "".join(f"0x{byte:02x}," for byte in output[at:at + 16]) for at in range(0, len(output), 16)]
        changed += 1
        return f"{match[1]} := [{len(output)}]u8 {{\n" + "\n".join(rows) + "\n}"

    text = pattern.sub(replace, text)
    if changed != 3:
        raise ValueError(f"expected three shared clustered fragment sources, found {changed}")
    for name, (logical, physical) in STORAGE.items():
        pattern = rf"(desc\.views\[{logical}\]\.storage_buffer\.glsl_binding_n = ){logical}\n"
        text, count = re.subn(pattern, rf"\g<1>{physical}\n", text)
        if count != 6:
            raise ValueError(f"{name}: expected six reflected bindings, found {count}")
        text = text.replace(f"layout(binding = {logical}, std430) readonly buffer {name}", f"layout(binding = {physical}, std430) readonly buffer {name}")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shdc", default="sokol-shdc")
    args = parser.parse_args()
    output = Path("engine/shader_basic.odin")
    previous = output.read_bytes()
    particles = Path("engine/shader_particles.odin")
    previous_particles = particles.read_bytes()
    try:
        subprocess.run([args.shdc, "-i", "engine/shaders/basic.glsl", "-o", str(output), "-l", "metal_macos:glsl430:hlsl5", "-f", "sokol_odin"], check=True)
        generated = compact_odin(output.read_text())
        subprocess.run([args.shdc, "-i", "engine/shaders/particles.glsl", "-o", str(particles), "-l", "metal_macos:glsl430:hlsl5", "-f", "sokol_odin"], check=True)
    except BaseException:
        output.write_bytes(previous)
        particles.write_bytes(previous_particles)
        raise
    output.write_text(generated)


if __name__ == "__main__":
    main()
