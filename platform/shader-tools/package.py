"""Package format 2 encoding and pinned reflection validation."""
import hashlib
import json
import re
import struct
from declarations import BuildError

HEADER = struct.Struct("<8sHHIIIII32s32s")
BACKENDS = ("glsl430", "hlsl5", "metal_macos", "wgsl")
FORMAT = 2
BACKEND_MASK = 15
WGSL_SAMPLER_BASE = 32
# scene_depth and selection_depth, the R32F Post inputs.
UNFILTERABLE_POST_SLOTS = (1, 3)

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")

def digest(data):
    return hashlib.sha256(data).digest()

def fingerprint(manifest):
    def public(value):
        if isinstance(value, dict):
            return {k: public(v) for k, v in value.items() if k not in ("vertex_func", "fragment_func", "inst_name")}
        if isinstance(value, list):
            return [public(v) for v in value]
        return value
    layout = [{"slang": s["slang"], "programs": s["programs"]} for s in manifest["shaders"]]
    return digest(canonical(public({"interface": manifest["interface"], "layout": layout})))

def pack(manifest, payload):
    metadata = canonical(manifest)
    if len(metadata) > 1024 * 1024 or len(payload) > 16 * 1024 * 1024:
        raise BuildError("shader package exceeds contract size")
    return HEADER.pack(b"RCSHADER", FORMAT, 1, 96, len(metadata), len(payload), 0, BACKEND_MASK,
                       fingerprint(manifest), digest(metadata + payload)) + metadata + payload


def parse_reflection(source):
    """Parse the pinned tool's plain scalar, two-space YAML grammar; never execute YAML tags."""
    if len(source.encode()) > 1024 * 1024:
        raise BuildError("reflection exceeds 1 MiB")
    lines = []
    for number, line in enumerate(source.splitlines(), 1):
        if not line.strip():
            continue
        if "\t" in line or len(line) - len(line.lstrip()) > 24:
            raise BuildError(f"reflection:{number}: unsupported indentation")
        indent = len(line) - len(line.lstrip())
        if indent % 2:
            raise BuildError(f"reflection:{number}: indentation must use pairs of spaces")
        lines.append((indent, line.strip(), number))
    if not lines:
        raise BuildError("empty compiler reflection")

    def parse(index, indent):
        sequence = lines[index][1] == "-"
        result = [] if sequence else {}
        while index < len(lines) and lines[index][0] == indent:
            _, line, number = lines[index]
            index += 1
            if sequence:
                if line != "-" or index >= len(lines) or lines[index][0] != indent + 2:
                    raise BuildError(f"reflection:{number}: invalid sequence")
                value, index = parse(index, indent + 2)
                result.append(value)
                continue
            match = re.fullmatch(r"([a-z][a-z0-9_]*):(.*)", line)
            if not match or match[1] in result:
                raise BuildError(f"reflection:{number}: invalid or duplicate mapping key")
            key, scalar = match[1], match[2].strip()
            if not scalar:
                if index >= len(lines) or lines[index][0] != indent + 2:
                    raise BuildError(f"reflection:{number}: empty or misindented section")
                value, index = parse(index, indent + 2)
            elif scalar in ("true", "false"):
                value = scalar == "true"
            elif re.fullmatch(r"[0-9]+", scalar):
                value = int(scalar)
            elif re.fullmatch(r"[A-Za-z_][A-Za-z0-9_./:-]*|2d|2d_array|3d", scalar):
                value = scalar
            else:
                raise BuildError(f"reflection:{number}: unsupported scalar {scalar!r}")
            result[key] = value
        return result, index
    result, end = parse(0, 0)
    if end != len(lines):
        raise BuildError("reflection contains inconsistent indentation")
    return result


def fields(obj, required, optional=()):
    if not isinstance(obj, dict) or set(obj) - set(required) - set(optional) or set(required) - set(obj):
        raise BuildError(f"unsupported reflection fields: {obj!r}")

def integer(value, minimum=0, maximum=31):
    if type(value) is not int or not minimum <= value <= maximum:
        raise BuildError(f"invalid reflected integer: {value!r}")

def text(value):
    if type(value) is not str or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value):
        raise BuildError(f"invalid reflected identifier: {value!r}")

def budget(program):
    blocks = program.get("uniform_blocks", [])
    return {"uniform_bytes": sum((b["size"] + 255) // 256 * 256 for b in blocks),
            "vertex_components": sum(b["size"] // 4 for b in blocks if b["stage"] == "vertex"),
            "fragment_components": sum(b["size"] // 4 for b in blocks if b["stage"] == "fragment"),
            "attributes": len(program.get("attrs", [])),
            "texture_views": sum("texture" in v for v in program.get("views", [])),
            "storage_buffers": sum("storage_buffer" in v for v in program.get("views", [])),
            "samplers": len(program.get("samplers", [])), "pairs": len(program.get("texture_sampler_pairs", []))}


def validate_reflection(reflection, declaration, contract):
    fields(reflection, ("shaders",))
    shaders = reflection["shaders"]
    if not isinstance(shaders, list) or tuple(s.get("slang") for s in shaders) != BACKENDS:
        raise BuildError("compiler did not emit all four backends in contract order")
    expected = contract["surface_programs"] if declaration["kind"] == "surface" else [contract["post_programs"][p] for p in declaration["locations"]]
    if declaration["kind"] == "surface" and not declaration.get("skinning", True):
        expected = [p for p in expected if not p.startswith("skinned")]
    if declaration["kind"] == "surface" and not declaration.get("instancing", True):
        expected = [p for p in expected if not p.startswith("instanced")]
    summaries = None
    for shader in shaders:
        fields(shader, ("slang", "programs"))
        if not isinstance(shader["programs"], list) or sorted(p.get("name", "") for p in shader["programs"]) != sorted(expected):
            raise BuildError("compiler emitted incomplete or unexpected pass variants")
        current = {}
        for program in shader["programs"]:
            validate_program(program, shader["slang"], declaration, contract)
            current[program["name"]] = budget(program)
        if summaries is not None and current != summaries:
            raise BuildError("backend resource budgets differ")
        summaries = current
    return summaries


def validate_program(p, backend, declaration, contract):
    fields(p, ("name", "vertex_func", "fragment_func"), ("attrs", "uniform_blocks", "views", "samplers", "texture_sampler_pairs"))
    for key in ("vertex_func", "fragment_func"):
        f = p[key]
        fields(f, ("path", "is_binary", "entry_point"), ("d3d11_target",))
        if f["is_binary"] is not False or not isinstance(f["path"], str) or not re.fullmatch(r"compiled_[A-Za-z0-9_]+\.(glsl|hlsl|metal|wgsl)", f["path"]):
            raise BuildError("invalid reflected source path or format")
        text(f["entry_point"])
        if backend == "hlsl5" and f.get("d3d11_target") != ("vs_5_0" if key == "vertex_func" else "ps_5_0"):
            raise BuildError("invalid D3D shader target")
    for key in ("attrs", "uniform_blocks", "views", "samplers", "texture_sampler_pairs"):
        if key in p and not isinstance(p[key], list):
            raise BuildError("reflected resource list is invalid")
    attrs = p.get("attrs", [])
    expected_attrs = ("vec3", "vec4", "vec3", "vec2", "vec4", "uvec4", "vec4")
    if p["name"].startswith("instanced"):
        expected_attrs = ("vec3", "vec4", "vec3", "vec2", "vec4") + ("vec4",) * 4 + ("vec3",) * 3 + ("vec4",)
    ceiling = 0 if declaration["kind"] == "post" else (13 if p["name"].startswith("instanced") else 7 if p["name"].startswith("skinned") else 5)
    used = set()
    for a in attrs:
        fields(a, ("slot", "type", "base_type"), ("glsl_name", "hlsl_sem_name", "hlsl_sem_index"))
        integer(a["slot"], 0, ceiling - 1)
        if a["slot"] in used or a["type"] != expected_attrs[a["slot"]] or a["base_type"] != ("UInt" if p["name"].startswith("skinned") and a["slot"] == 5 else "Float"):
            raise BuildError("Surface vertex layout differs from platform contract")
        used.add(a["slot"])
        for field in ("glsl_name", "hlsl_sem_name"):
            if field in a:
                text(a[field])
        if "hlsl_sem_index" in a:
            integer(a["hlsl_sem_index"], 0, 15)
    sizes = contract["post_uniform_sizes"] if declaration["kind"] == "post" else contract["uniform_sizes"]
    used = set()
    for b in p.get("uniform_blocks", []):
        fields(b, ("slot", "stage", "size", "struct_name", "inst_name"), ("glsl_uniforms", "hlsl_register_b_n", "msl_buffer_n", "wgsl_group0_binding_n"))
        slot = b["slot"]
        integer(slot, 0, 5)
        if slot in used or str(slot) not in sizes or b["size"] != sizes[str(slot)] or b["stage"] != ("vertex" if slot in (0, 3, 4) else "fragment"):
            raise BuildError("uniform block differs from platform contract")
        used.add(slot)
        text(b["struct_name"]); text(b["inst_name"])
        for field in ("hlsl_register_b_n", "msl_buffer_n", "wgsl_group0_binding_n"):
            if field in b and b[field] != slot:
                raise BuildError("unexpected backend uniform mapping")
        if backend == "glsl430":
            uniforms = b.get("glsl_uniforms")
            if not isinstance(uniforms, list) or len(uniforms) != 1:
                raise BuildError("unsupported GL uniform flattening")
            u = uniforms[0]
            fields(u, ("type", "array_count", "offset", "glsl_name"))
            if u["type"] != "vec4" or u["array_count"] * 16 != b["size"] or u["offset"] != 0:
                raise BuildError("invalid flattened GL uniform size")
            text(u["glsl_name"])
    textures, samplers, storage = {}, {}, {}
    declared = {t["view"]: t for t in declaration["textures"]}
    for view in p.get("views", []):
        if not isinstance(view, dict) or len(view) != 1:
            raise BuildError("invalid reflection view")
        if "storage_buffer" in view:
            b = view["storage_buffer"]
            fields(b, ("slot", "stage", "size", "align", "struct_name", "inst_name", "inner_struct_name", "readonly"), ("glsl_binding_n", "hlsl_register_t_n", "msl_buffer_n", "wgsl_group1_binding_n"))
            slot = b["slot"]
            integer(slot, 12, 14)
            if slot in storage or b["stage"] != "fragment" or b["readonly"] is not True or b["size"] != (32 if slot == 12 else 16) or b["align"] != 16 or declaration["kind"] != "surface":
                raise BuildError("invalid clustered storage layout")
            for field in ("struct_name", "inst_name", "inner_struct_name"):
                text(b[field])
            if backend == "glsl430" and b.get("glsl_binding_n") != slot:
                raise BuildError("unexpected original GL storage binding")
            storage[slot] = b
        elif "texture" in view:
            t = view["texture"]
            fields(t, ("slot", "stage", "name", "multisampled", "type", "sample_type"), ("hlsl_register_t_n", "msl_texture_n", "wgsl_group1_binding_n"))
            slot = t["slot"]
            integer(slot, 0, 11)
            text(t["name"])
            if slot in textures or t["multisampled"] is not False or t["stage"] not in ("vertex", "fragment"):
                raise BuildError("invalid texture binding")
            if slot >= 8:
                d = declared.get(slot)
                if d is None or t["stage"] != d["stage"] or t["type"] != d["type"] or t["sample_type"] != "float":
                    raise BuildError("game texture differs from declaration")
            elif t["stage"] != "fragment":
                raise BuildError("engine textures belong to fragment stage")
            else:
                if declaration["kind"] == "surface":
                    semantics = {0: ("base_tex", "2d", "float"), 1: ("metallic_roughness_tex", "2d", "float"), 2: ("shadow_tex", "array", "depth"), 3: ("emissive_tex", "2d", "float"), 4: ("normal_tex", "2d", "float"), 5: ("occlusion_tex", "2d", "float"), 6: ("env_diffuse_tex", "cube", "float"), 7: ("env_specular_tex", "cube", "float")}
                    expected = semantics.get(slot)
                else:
                    names = ("scene_colour", "scene_depth", "selection_coverage", "selection_depth")
                    sample = "unfilterable_float" if slot in UNFILTERABLE_POST_SLOTS else "float"
                    expected = (names[slot], "2d", sample) if slot < 4 and names[slot] in declaration["inputs"] else None
                if expected != (t["name"], t["type"], t["sample_type"]):
                    raise BuildError("engine texture differs from its reserved semantic")
            if declaration["kind"] == "post" and slot < 8 and slot >= 4:
                raise BuildError("invalid Post input binding")
            textures[slot] = t
        else:
            raise BuildError("unsupported reflected resource kind")
    for s in p.get("samplers", []):
        fields(s, ("slot", "stage", "name", "sampler_type"), ("hlsl_register_s_n", "msl_sampler_n", "wgsl_group1_binding_n"))
        slot = s["slot"]
        integer(slot, 0, 11)
        text(s["name"])
        expected = ("nonfiltering",) if declaration["kind"] == "post" and slot in UNFILTERABLE_POST_SLOTS else ("filtering", "comparison")
        if slot in samplers or slot not in textures or s["stage"] != textures[slot]["stage"] or s["sampler_type"] not in expected:
            raise BuildError("invalid sampler binding")
        samplers[slot] = s
    used = set()
    for pair in p.get("texture_sampler_pairs", []):
        fields(pair, ("slot", "stage", "name", "view_name", "sampler_name", "view_slot", "sampler_slot"), ("glsl_name",))
        integer(pair["slot"], 0, 11)
        if pair["slot"] in used:
            raise BuildError("duplicate texture/sampler pair")
        used.add(pair["slot"])
        t = textures.get(pair["view_slot"])
        s = samplers.get(pair["sampler_slot"])
        if t is None or s is None or t["slot"] != s["slot"] or pair["stage"] != t["stage"] or pair["view_name"] != t["name"] or pair["sampler_name"] != s["name"]:
            raise BuildError("texture/sampler pair differs from resource declarations")
    if len(textures) > 12 or len(storage) > 3 or len(samplers) > 12 or len(used) > 12:
        raise BuildError("portable resource capacity exceeded")
    if backend == "wgsl":
        # sokol WGPU binds views at their slot and samplers after the views.
        for resources, base in ((textures, 0), (storage, 0), (samplers, WGSL_SAMPLER_BASE)):
            for slot, resource in resources.items():
                if resource.get("wgsl_group1_binding_n") != base + slot:
                    raise BuildError("unexpected WGSL resource binding")
        for b in p.get("uniform_blocks", []):
            if b.get("wgsl_group0_binding_n") != b["slot"]:
                raise BuildError("unexpected WGSL uniform binding")
    for resources, field in ((textures, "msl_texture_n" if backend == "metal_macos" else "hlsl_register_t_n"), (storage, "msl_buffer_n" if backend == "metal_macos" else "hlsl_register_t_n"), (samplers, "msl_sampler_n" if backend == "metal_macos" else "hlsl_register_s_n")):
        if backend in ("glsl430", "wgsl"):
            continue
        for resource in resources.values():
            integer(resource.get(field), 0, 127)
    if backend == "hlsl5":
        bindings = [(t["stage"], t["hlsl_register_t_n"]) for t in list(textures.values()) + list(storage.values())]
        if len(set(bindings)) != len(bindings):
            raise BuildError("D3D texture and storage registers overlap")


def compact_gl(program, source):
    code = source.decode("utf-8")
    for view in program.get("views", []):
        if "storage_buffer" not in view:
            continue
        b = view["storage_buffer"]
        original = f"layout(binding = {b['glsl_binding_n']}, std430) readonly buffer {b['struct_name']}\n"
        replacement = f"layout(binding = {b['slot'] - 12}, std430) readonly buffer {b['struct_name']}\n"
        if code.count(original) != 1:
            raise BuildError("GL storage declaration does not match compiler reflection")
        code = code.replace(original, replacement)
        b["glsl_binding_n"] = b["slot"] - 12
    return code.encode("utf-8")
