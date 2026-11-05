#!/usr/bin/env python3
"""Executable reference for the shader package contract, not the engine loader."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PIN = "11d0cf678105d614d675e6d9bd2aaf3eeff12f8c"
HEADER = struct.Struct("<8sHHIIIII32s32s")
MAGIC = b"RCSHADER"
BACKENDS = ("glsl430", "hlsl5", "metal_macos")
TYPES = {"F32": 1, "Vec2": 2, "Vec3": 3, "Vec4": 4, "Colour": 4, "Mat4": 16, "Bool": 1}
TEXT_EVIDENCE_SUFFIXES = {".yaml", ".glsl", ".hlsl", ".metal", ".h"}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def digest(value):
    return hashlib.sha256(value).digest()


def evidence_digest(name, contents):
    if Path(name).suffix in TEXT_EVIDENCE_SUFFIXES:
        contents = contents.replace(b"\r\n", b"\n")
    return hashlib.sha256(contents).hexdigest()


def parse_reflection(source):
    """Read only the compiler's indentation-only YAML subset; reject other YAML."""
    lines = [(len(s) - len(s.lstrip()), s.strip()) for s in source.splitlines() if s.strip()]

    def scalar(s):
        if s in ("true", "false"):
            return s == "true"
        if re.fullmatch(r"-?[0-9]+", s):
            return int(s)
        if not s or any(c in s for c in "{}[]&*!|>'\"#"):
            raise ValueError(f"unsupported reflection scalar: {s!r}")
        return s

    def block(i, indent):
        value = [] if lines[i][1] == "-" else {}
        while i < len(lines) and lines[i][0] == indent:
            _, s = lines[i]
            i += 1
            if isinstance(value, list):
                if s != "-" or i == len(lines) or lines[i][0] <= indent:
                    raise ValueError("invalid reflection list")
                child, i = block(i, lines[i][0])
                value.append(child)
            else:
                key, sep, rest = s.partition(":")
                if not sep or key in value:
                    raise ValueError("invalid reflection key")
                if rest.strip():
                    value[key] = scalar(rest.strip())
                else:
                    if i == len(lines) or lines[i][0] <= indent:
                        raise ValueError("empty reflection section")
                    value[key], i = block(i, lines[i][0])
        return value, i

    value, end = block(0, 0)
    if end != len(lines):
        raise ValueError("invalid reflection indentation")
    return value


def encode_parameter(kind, value):
    if kind not in TYPES or not isinstance(value, list) or len(value) != TYPES[kind]:
        raise ValueError("invalid parameter type or length")
    if kind == "Bool":
        if type(value[0]) is not bool:
            raise ValueError("Bool requires true or false")
        value = [float(value[0])]
    if any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > 3.4028234663852886e38 for v in value):
        raise ValueError("parameter requires finite F32 values")
    padded = value + [0] * ((-len(value)) % 4)
    return struct.pack("<" + "f" * len(padded), *padded)


def validate_parameters(interface):
    for kind in ("surface", "post"):
        occupied = set()
        names = set()
        for p in interface[kind]["parameters"]:
            if p["name"] in names or not re.fullmatch(r"[a-z][a-z0-9_]*", p["name"]):
                raise ValueError("invalid or duplicate parameter name")
            names.add(p["name"])
            if p["scope"] not in ("Scene", "Material", "Draw") or p["stage"] not in ("vertex", "fragment"):
                raise ValueError("invalid parameter scope or stage")
            if kind == "post" and (p["scope"] == "Material" or p["stage"] == "vertex"):
                raise ValueError("Post parameters require Scene or Draw scope in the fragment stage")
            data = encode_parameter(p["type"], p["default"])
            offset = p["offset"]
            if type(offset) is not int or offset < 0 or offset % 16 or offset + len(data) > 256:
                raise ValueError("parameter exceeds aligned 256-byte block")
            for lane in range(offset // 16, (offset + len(data)) // 16):
                key = (p["stage"], lane)
                if key in occupied:
                    raise ValueError("overlapping parameter")
                occupied.add(key)
    for kind in ("surface", "post"):
        textures = interface[kind].get("textures", [])
        if len(textures) > 4:
            raise ValueError("game texture capacity exceeded")
        names, slots = set(), set()
        for texture in textures:
            if texture["name"] in names or not re.fullmatch(r"[a-z][a-z0-9_]*", texture["name"]):
                raise ValueError("invalid or duplicate texture name")
            names.add(texture["name"])
            slot = texture["view"]
            if type(slot) is not int or slot not in range(8, 12) or texture["sampler"] != slot or slot in slots:
                raise ValueError("invalid or duplicate game texture binding")
            slots.add(slot)
            if texture["scope"] not in ("Scene", "Material", "Draw") or texture["stage"] not in ("vertex", "fragment"):
                raise ValueError("invalid texture scope or stage")
            if kind == "post" and (texture["scope"] == "Material" or texture["stage"] == "vertex"):
                raise ValueError("invalid Post texture scope or stage")
            if texture["type"] not in ("2d", "cube") or texture["sample_type"] != "float":
                raise ValueError("unsupported game texture type")
            if texture["colour_space"] not in ("linear", "srgb"):
                raise ValueError("invalid texture colour space")
            policy = texture["sampler_policy"]
            if policy.get("min") not in ("nearest", "linear") or policy.get("mag") not in ("nearest", "linear") or policy.get("wrap") not in ("clamp", "repeat", "mirror"):
                raise ValueError("invalid sampler policy")
            default = texture.get("default")
            if default is not None:
                if set(default) == {"constant"}:
                    if texture.get("optional") is not True:
                        raise ValueError("constant texture default requires an optional declaration")
                    encode_parameter("Vec4", default["constant"])
                elif set(default) == {"imported"}:
                    if texture["scope"] != "Material" or default["imported"] not in ("base_colour", "metallic_roughness", "emissive", "normal", "occlusion"):
                        raise ValueError("invalid imported texture default")
                elif set(default) == {"pack", "asset"}:
                    if any(not isinstance(default[k], str) or not default[k] for k in default):
                        raise ValueError("invalid Pack texture reference")
                else:
                    raise ValueError("invalid texture default")
    displacement = interface["surface"]["max_displacement"]
    if type(displacement) not in (int, float) or not math.isfinite(displacement) or displacement < 0:
        raise ValueError("invalid maximum displacement")


def interface_hash(manifest):
    layout = []
    for shader in manifest["shaders"]:
        programs = []
        for p in shader["programs"]:
            programs.append({k: v for k, v in p.items() if k not in ("vertex_func", "fragment_func")})
        layout.append({"slang": shader["slang"], "programs": programs})
    def public(value):
        if isinstance(value, dict):
            return {k: public(v) for k, v in value.items() if k != "inst_name"}
        if isinstance(value, list):
            return [public(v) for v in value]
        return value
    return digest(canonical(public({"interface": manifest["interface"], "layout": layout})))


def pack(manifest, payload):
    metadata = canonical(manifest)
    return HEADER.pack(MAGIC, 1, 1, HEADER.size, len(metadata), len(payload), 0, 7,
                       interface_hash(manifest), digest(metadata + payload)) + metadata + payload


def unpack(data):
    if len(data) < HEADER.size:
        raise ValueError("truncated shader header")
    magic, fmt, contract, header, metadata_size, payload_size, flags, mask, fingerprint, checksum = HEADER.unpack_from(data)
    if (magic, fmt, contract, header, flags, mask) != (MAGIC, 1, 1, HEADER.size, 0, 7):
        raise ValueError("incompatible shader contract")
    if metadata_size > 1024 * 1024 or payload_size > 16 * 1024 * 1024 or len(data) != header + metadata_size + payload_size:
        raise ValueError("invalid shader package size")
    body = data[header:]
    if digest(body) != checksum:
        raise ValueError("shader package checksum mismatch")
    manifest = json.loads(body[:metadata_size])
    if canonical(manifest) != body[:metadata_size] or interface_hash(manifest) != fingerprint:
        raise ValueError("shader interface fingerprint mismatch")
    validate_parameters(manifest["interface"])
    payload = body[metadata_size:]
    for shader in manifest["shaders"]:
        for program in shader["programs"]:
            for name in ("vertex_func", "fragment_func"):
                f = program[name]
                start, size = f["offset"], f["size"]
                if type(start) is not int or type(size) is not int or start < 0 or size <= 0 or start + size > len(payload):
                    raise ValueError("invalid shader source range")
                source = payload[start:start + size]
                source.decode("utf-8")
                if b"\0" in source:
                    raise ValueError("shader source contains NUL")
    return manifest, payload


def budget(program):
    blocks = program.get("uniform_blocks", [])
    return {
        "uniform_bytes": sum((b["size"] + 255) // 256 * 256 for b in blocks),
        "vertex_components": sum((b["size"] + 15) // 16 * 4 for b in blocks if b["stage"] == "vertex"),
        "fragment_components": sum((b["size"] + 15) // 16 * 4 for b in blocks if b["stage"] == "fragment"),
        "attributes": len(program.get("attrs", [])),
        "views": len(program.get("views", [])),
        "storage_buffers": sum("storage_buffer" in v for v in program.get("views", [])),
        "texture_views": sum("texture" in v for v in program.get("views", [])),
        "samplers": len(program.get("samplers", [])),
        "pairs": len(program.get("texture_sampler_pairs", [])),
    }


def check_bindings(manifest):
    if tuple(s["slang"] for s in manifest["shaders"]) != BACKENDS:
        raise ValueError("missing shader backend")
    reference = None
    for shader in manifest["shaders"]:
        summaries = {}
        for p in shader["programs"]:
            b = budget(p)
            if b["attributes"] > 7 or b["views"] > 15 or b["texture_views"] > 12 or b["samplers"] > 12 or b["pairs"] > 12:
                raise ValueError("shader exceeds portable resource limits")
            for block in p.get("uniform_blocks", []):
                if block["slot"] not in range(6):
                    raise ValueError("invalid uniform slot")
                if block["slot"] in (4, 5) and block["size"] > 256:
                    raise ValueError("game uniform block exceeds budget")
                for mapping in ("msl_buffer_n", "hlsl_register_b_n"):
                    if mapping in block and block[mapping] != block["slot"]:
                        raise ValueError("unexpected backend uniform mapping")
            for view in p.get("views", []):
                if "texture" in view:
                    if view["texture"]["slot"] not in range(12):
                        raise ValueError("unexpected texture view")
                elif "storage_buffer" in view:
                    storage = view["storage_buffer"]
                    if storage["slot"] not in range(12, 15) or not storage["readonly"] or storage["stage"] != "fragment":
                        raise ValueError("unexpected storage buffer view")
                    if "glsl_binding_n" in storage and storage["glsl_binding_n"] != storage["slot"] - 12:
                        raise ValueError("GL storage mapping is not compact")
                else:
                    raise ValueError("unexpected resource view")
            for sampler in p.get("samplers", []):
                if sampler["slot"] not in range(12):
                    raise ValueError("invalid sampler slot")
            summaries[p["name"]] = b
        if len(summaries) != 8:
            raise ValueError("incomplete pass variants")
        if reference is not None and summaries != reference:
            raise ValueError("backend resource budgets differ")
        reference = summaries
    return reference


def remap_gl_storage(program, source):
    text = source.decode("utf-8")
    for view in program.get("views", []):
        if "storage_buffer" not in view:
            continue
        buffer = view["storage_buffer"]
        old = buffer["glsl_binding_n"]
        new = buffer["slot"] - 12
        if new not in range(3):
            raise ValueError("unsupported GL storage slot")
        declaration = f"layout(binding = {old}, std430) readonly buffer {buffer['struct_name']}\n"
        if text.count(declaration) != 1:
            raise ValueError("GL storage declaration does not match reflection")
        text = text.replace(declaration, f"layout(binding = {new}, std430) readonly buffer {buffer['struct_name']}\n")
        buffer["glsl_binding_n"] = new
    return text.encode("utf-8")


def emit_c(manifest, payload, path):
    lines = ["/* Generated from the decoded shader package. */", "#include <string.h>",
             "#define PROOF_PROGRAM_COUNT 8", "static const char *proof_names[] = {" +
             ",".join(json.dumps(p["name"]) for p in manifest["shaders"][0]["programs"]) + "};",
             "static sg_shader_desc proof_desc(int index, sg_backend backend) {", "sg_shader_desc d = {0};"]
    backend_ids = {"glsl430": "SG_BACKEND_GLCORE", "hlsl5": "SG_BACKEND_D3D11", "metal_macos": "SG_BACKEND_METAL_MACOS"}
    for shader in manifest["shaders"]:
        lines.append(f"if (backend == {backend_ids[shader['slang']]}) {{ switch(index) {{")
        for index, p in enumerate(shader["programs"]):
            lines.append(f"case {index}: d.label = proof_names[index];")
            for name in ("vertex_func", "fragment_func"):
                f = p[name]
                source = payload[f["offset"]:f["offset"] + f["size"]].decode()
                lines.append(f"d.{name}.source = {json.dumps(source)};")
                lines.append(f"d.{name}.entry = {json.dumps(f['entry_point'])};")
                if "d3d11_target" in f:
                    lines.append(f"d.{name}.d3d11_target = {json.dumps(f['d3d11_target'])};")
            for a in p.get("attrs", []):
                prefix = f"d.attrs[{a['slot']}]"
                for key in ("glsl_name", "hlsl_sem_name", "hlsl_sem_index"):
                    if key in a:
                        lines.append(f"{prefix}.{key} = {json.dumps(a[key])};")
                lines.append(f"{prefix}.base_type = SG_SHADERATTRBASETYPE_{a['base_type'].upper()};")
            for b in p.get("uniform_blocks", []):
                prefix = f"d.uniform_blocks[{b['slot']}]"
                lines.extend([f"{prefix}.stage = SG_SHADERSTAGE_{b['stage'].upper()};", f"{prefix}.size = {b['size']};", f"{prefix}.layout = SG_UNIFORMLAYOUT_STD140;"])
                for key in ("msl_buffer_n", "hlsl_register_b_n"):
                    if key in b:
                        lines.append(f"{prefix}.{key} = {b[key]};")
                for n, u in enumerate(b.get("glsl_uniforms", [])):
                    lines.extend([f"{prefix}.glsl_uniforms[{n}].type = SG_UNIFORMTYPE_FLOAT4;", f"{prefix}.glsl_uniforms[{n}].array_count = {u['array_count']};", f"{prefix}.glsl_uniforms[{n}].glsl_name = {json.dumps(u['glsl_name'])};"])
            for v in p.get("views", []):
                if "storage_buffer" in v:
                    b = v["storage_buffer"]
                    prefix = f"d.views[{b['slot']}].storage_buffer"
                    lines.extend([f"{prefix}.stage = SG_SHADERSTAGE_FRAGMENT;", f"{prefix}.readonly = true;"])
                    for key in ("msl_buffer_n", "hlsl_register_t_n", "glsl_binding_n"):
                        if key in b:
                            lines.append(f"{prefix}.{key} = {b[key]};")
                    continue
                t = v["texture"]
                prefix = f"d.views[{t['slot']}].texture"
                lines.extend([f"{prefix}.stage = SG_SHADERSTAGE_{t['stage'].upper()};", f"{prefix}.image_type = SG_IMAGETYPE_2D;", f"{prefix}.sample_type = SG_IMAGESAMPLETYPE_FLOAT;"])
                for key in ("msl_texture_n", "hlsl_register_t_n"):
                    if key in t:
                        lines.append(f"{prefix}.{key} = {t[key]};")
            for s in p.get("samplers", []):
                prefix = f"d.samplers[{s['slot']}]"
                lines.extend([f"{prefix}.stage = SG_SHADERSTAGE_{s['stage'].upper()};", f"{prefix}.sampler_type = SG_SAMPLERTYPE_FILTERING;"])
                for key in ("msl_sampler_n", "hlsl_register_s_n"):
                    if key in s:
                        lines.append(f"{prefix}.{key} = {s[key]};")
            for pair in p.get("texture_sampler_pairs", []):
                prefix = f"d.texture_sampler_pairs[{pair['slot']}]"
                lines.extend([f"{prefix}.stage = SG_SHADERSTAGE_{pair['stage'].upper()};", f"{prefix}.view_slot = {pair['view_slot']};", f"{prefix}.sampler_slot = {pair['sampler_slot']};"])
                if "glsl_name" in pair:
                    lines.append(f"{prefix}.glsl_name = {json.dumps(pair['glsl_name'])};")
            lines.append("break;")
        lines.append("} }")
    lines.append("return d; }")
    path.write_bytes(("\n".join(lines) + "\n").encode("utf-8"))


def build(compiler, out):
    pins = json.loads((ROOT / "scripts/shader_contract/compiler.json").read_text())
    compiler_sha = hashlib.sha256(Path(compiler).read_bytes()).hexdigest()
    if compiler_sha not in pins["sha256"].values():
        raise ValueError("compiler does not match the pinned tool binaries")
    out.mkdir(parents=True, exist_ok=True)
    relative = out.relative_to(ROOT).as_posix()
    command = [str(compiler), "-i", "scripts/shader_contract/proof.glsl", "-o", relative + "/proof",
               "-l", "metal_macos:glsl430:hlsl5", "-f", "bare_yaml", "--no-log-cmdline"]
    subprocess.run(command, cwd=ROOT, check=True)
    invalid = out / "invalid.glsl"
    source = (ROOT / "scripts/shader_contract/proof.glsl").read_text()
    source = source.replace("sin(render_time.x + p.y)", "undefined_wind(render_time.x + p.y)")
    invalid.write_text(source)
    bad_command = command.copy()
    bad_command[2] = relative + "/invalid.glsl"
    bad = subprocess.run(bad_command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / "invalid-source.log").write_text(bad.stdout)
    line = next(i for i, s in enumerate(source.splitlines(), 1) if "undefined_wind" in s)
    if bad.returncode == 0 or f"invalid.glsl:{line}:" not in bad.stdout or "undefined_wind" not in bad.stdout:
        raise ValueError("compiler did not preserve the invalid source diagnostic")
    reflection = parse_reflection((out / "proof_reflection.yaml").read_text())
    interface = json.loads((ROOT / "scripts/shader_contract/interface.json").read_text())
    validate_parameters(interface)
    payload = bytearray()
    for shader in reflection["shaders"]:
        for p in shader["programs"]:
            for name in ("vertex_func", "fragment_func"):
                f = p[name]
                code = (ROOT / f.pop("path")).read_bytes()
                if shader["slang"] == "glsl430" and name == "fragment_func":
                    code = remap_gl_storage(p, code)
                f.update(offset=len(payload), size=len(code))
                payload.extend(code)
    manifest = {"compiler": {"repository": "floooh/sokol-tools-bin", "commit": PIN},
                "backend_transform": "gl_ssbo_compact_v1",
                "interface": interface, "shaders": reflection["shaders"]}
    blob = pack(manifest, payload)
    manifest, payload = unpack(blob)
    budgets = check_bindings(manifest)
    (out / "proof.shaderpack").write_bytes(blob)
    (out / "manifest.json").write_bytes(canonical(manifest) + b"\n")
    emit_c(manifest, payload, out / "proof_bindings.h")
    hashes = {p.name: evidence_digest(p.name, p.read_bytes()) for p in sorted(out.iterdir())
              if p.name.startswith("proof") and p.suffix not in (".bin", ".exe")}
    evidence = {"compiler_commit": PIN, "compiler_sha256": hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
                "cross_compilation": list(BACKENDS), "native_execution": "not run by build", "budgets": budgets,
                "backend_transform": manifest["backend_transform"],
                "storage_bindings": {shader["slang"]: {
                    p["name"]: [v["storage_buffer"] for v in p.get("views", []) if "storage_buffer" in v]
                    for p in shader["programs"] if any("storage_buffer" in v for v in p.get("views", []))}
                    for shader in manifest["shaders"]},
                "sha256": hashes}
    (out / "evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    return evidence


def native_compile_command(out, sokol, platform):
    binary = out / ("native.exe" if platform == "win32" else "native.bin")
    command = [os.environ.get("CC", "clang"), "-std=c11", "-O0", "-g", "-I" + str(sokol / "sokol/c"),
               "-I" + str(out), str(ROOT / "scripts/shader_contract/native.c"), "-o", str(binary)]
    if platform == "linux":
        command[1:1] = ["-D_POSIX_C_SOURCE=200809L"]
    elif platform == "darwin":
        command[1:1] = ["-x", "objective-c", "-fobjc-arc"]
        command.extend(["-framework", "Cocoa", "-framework", "QuartzCore", "-framework", "Metal", "-framework", "MetalKit"])
    elif platform == "win32":
        command.extend(["-luser32", "-lshell32", "-lgdi32", "-ld3d11", "-ldxgi"])
    else:
        command.extend(["-lX11", "-lXi", "-lXcursor", "-lGL", "-ldl", "-lpthread", "-lm"])
    return command


def run_native(out, sokol):
    binary = out / ("native.exe" if sys.platform == "win32" else "native.bin")
    command = native_compile_command(out, sokol, sys.platform)
    subprocess.run(command, cwd=ROOT, check=True)
    try:
        result = subprocess.run([str(binary)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    except subprocess.TimeoutExpired as error:
        (out / "native.log").write_bytes(error.stdout or b"")
        raise
    print(result.stdout, end="")
    (out / "native.log").write_text(result.stdout)
    result.check_returncode()
    if "PASS: 8 package shader variants" not in result.stdout:
        raise RuntimeError("native binding proof did not finish")
    (out / "native-evidence.json").write_text(json.dumps({
        "host": sys.platform, "result": "passed", "variants": 8, "frames": 3,
        "package_sha256": hashlib.sha256((out / "proof.shaderpack").read_bytes()).hexdigest(),
        "log": result.stdout,
    }, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shdc", default=shutil.which("sokol-shdc"))
    parser.add_argument("--out", type=Path, default=Path("build/shader-contract"))
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--sokol", type=Path, default=ROOT / "sokol-odin")
    args = parser.parse_args()
    if not args.shdc:
        parser.error("set --shdc to the pinned sokol-shdc executable")
    out = (ROOT / args.out).resolve()
    evidence = build(Path(args.shdc).resolve(), out)
    if args.check:
        golden = json.loads((ROOT / "scripts/shader_contract/expected.json").read_text())
        if golden != {key: evidence[key] for key in ("budgets", "sha256")}:
            raise ValueError("compiler outputs differ from the recorded proof")
    print(json.dumps({"cross_compilation": evidence["cross_compilation"], "budgets": evidence["budgets"]}, indent=2))
    if args.run:
        run_native(out, args.sokol.resolve())


if __name__ == "__main__":
    main()
