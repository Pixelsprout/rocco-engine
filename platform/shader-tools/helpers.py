"""Generate public typed values from shader declarations and source material identities."""
import json
from pathlib import Path
import re
import struct
from declarations import BuildError

ROC_TYPES = {"F32": "F32", "Bool": "Bool", "Vec2": "Shader.Vec2", "Vec3": "Shader.Vec3", "Vec4": "Shader.Vec4", "Colour": "Shader.Colour", "Mat4": "Shader.Mat4"}
TAGS = {"F32": "Scalar", "Bool": "Boolean", "Vec2": "Vector2", "Vec3": "Vector3", "Vec4": "Vector4", "Colour": "LinearColour", "Mat4": "Matrix4"}

def number(value):
    return repr(float(value))

def literal(kind, values):
    if kind == "F32":
        return number(values[0])
    if kind == "Bool":
        return "Bool.True" if values[0] else "Bool.False"
    if kind == "Mat4":
        return "{ " + ", ".join(f"c{i}: {literal('Vec4', values[i*4:i*4+4])}" for i in range(4)) + " }"
    names = ("r", "g", "b", "a") if kind == "Colour" else ("x", "y", "z", "w")
    return "{ " + ", ".join(f"{k}: {number(v)}" for k, v in zip(names, values)) + " }"

def module_source(lines):
    result = []
    for line in lines:
        if line.startswith("\t##") and result and result[-1] and not result[-1].startswith("\t##"):
            result.append("")
        result.append(line)
    return "\n".join(result)


def shader_module(declaration):
    name = declaration["name"]
    lines = ["import pf.Shader", "", f"{name} := [].{{", "\t## The shader asset key within the supplied Pack.", "\tasset : Str -> Shader.Asset", f'\tasset = |pack| {{ pack, asset: "shader/{name}" }}']
    for scope in ("Scene", "Material", "Draw"):
        if declaration["kind"] == "post" and scope == "Material":
            continue
        params = [p for p in declaration["parameters"] if p["scope"] == scope]
        key = scope.lower()
        fields = ", ".join(f"{p['name']} : {ROC_TYPES[p['type']]}" for p in params)
        lines += [f"\t## Numeric {scope} values. Start from {key}_default for declared defaults.", f"\t{scope}Parameters : {{ {fields} }}" if fields else f"\t{scope}Parameters : {{}}"]
        defaults = ", ".join(f"{p['name']}: {literal(p['type'], p['default'])}" for p in params)
        lines += [f"\t## Declared numeric defaults for {scope} scope.", f"\t{key}_default : {scope}Parameters", f"\t{key}_default = {{ {defaults} }}" if defaults else f"\t{key}_default = {{}}"]
        assignments = ", ".join(f'{{ name: "{p["name"]}", value: {TAGS[p["type"]]}(values.{p["name"]}) }}' for p in params)
        arg = "values" if params else "_values"
        lines += [f"\t## Assign numeric values only to {scope} scope.", f"\t{key} : Str, {scope}Parameters -> Shader.Values", f"\t{key} = |pack, {arg}| {{ shader: asset(pack), scope: {scope}, parameters: [{assignments}], textures: [] }}"]
        textures = [t for t in declaration["textures"] if t["scope"] == scope]
        if textures:
            texture_fields = ", ".join(f"{t['name']} : [Default, {'Image2D' if t['type'] == '2d' else 'Cubemap'}(Shader.Asset)]" for t in textures)
            lines += [f"\t## Explicit textures for {scope} scope. Numeric-only assignments retain texture defaults.", f"\t{scope}Textures : {{ {texture_fields} }}", f"\t## Keep all declared texture defaults in {scope} scope.", f"\t{key}_textures_default : {scope}Textures", f"\t{key}_textures_default = {{ " + ", ".join(t["name"] + ": Default" for t in textures) + " }", f"\t## Assign numeric values and textures together in {scope} scope.", f"\t{key}_with_textures : Str, {scope}Parameters, {scope}Textures -> Shader.Values", f"\t{key}_with_textures = |pack, values, textures| {{", f"\t\t..{key}(pack, values),", "\t\ttextures: List.join(["]
            for texture in textures:
                tag = "Image2D" if texture["type"] == "2d" else "Cubemap"
                lines += [f"\t\t\tmatch textures.{texture['name']} {{", "\t\t\t\tDefault => []", f"\t\t\t\t{tag}(reference) => [{{ name: \"{texture['name']}\", texture: {tag}(reference) }}]", "\t\t\t},"]
            lines += ["\t\t]),", "\t}"]
        for texture in declaration["textures"]:
            if texture["scope"] != scope:
                continue
            method = key + "_" + texture["name"]
            tag = "Image2D" if texture["type"] == "2d" else "Cubemap"
            lines += [f"\t## Replace {texture['name']} in {scope} scope.", f"\t{method} : Str, [{tag}(Shader.Asset)] -> Shader.Values", f"\t{method} = |pack, texture| {{", "\t\tshader: asset(pack),", f"\t\tscope: {scope},", "\t\tparameters: [],", "\t\ttextures: [", "\t\t\t{", f"\t\t\t\tname: \"{texture['name']}\",", "\t\t\t\ttexture: match texture {", f"\t\t\t\t\t{tag}(reference) => {tag}(reference)", "\t\t\t\t},", "\t\t\t},", "\t\t],", "\t}"]
    lines += ["}", ""]
    return module_source(lines)


def mesh_materials(path):
    data = Path(path).read_bytes()
    if Path(path).suffix.lower() == ".glb":
        if len(data) < 20 or data[:4] != b"glTF" or struct.unpack_from("<II", data, 4) != (2, len(data)):
            raise BuildError(f"{path}:1:1: invalid GLB header")
        at, source = 12, None
        while at < len(data):
            if at + 8 > len(data):
                raise BuildError(f"{path}:1:1: truncated GLB chunk")
            size, kind = struct.unpack_from("<II", data, at)
            at += 8
            if size % 4 or at + size > len(data):
                raise BuildError(f"{path}:1:1: invalid GLB chunk size")
            if source is None:
                if kind != 0x4E4F534A:
                    raise BuildError(f"{path}:1:1: first GLB chunk must be JSON")
                source = data[at:at+size]
            elif kind == 0x4E4F534A:
                raise BuildError(f"{path}:1:1: duplicate GLB JSON chunk")
            at += size
        value = json.loads(source)
    elif Path(path).suffix.lower() == ".gltf":
        value = json.loads(data)
    else:
        raise BuildError(f"{path}:1:1: mesh helpers require glTF or GLB")
    materials = value.get("materials", [])
    if not isinstance(materials, list):
        raise BuildError(f"{path}:1:1: invalid source material array")
    names, identifiers, result = set(), set(), []
    for index, material in enumerate(materials):
        if not isinstance(material, dict) or not isinstance(material.get("name", ""), str):
            raise BuildError(f"{path}:1:1: invalid material at /materials/{index}")
        name = material.get("name", "")
        if not name:
            continue
        identifier = re.sub(r"[^a-z0-9]+", "_", re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()).strip("_")
        if not identifier or not identifier[0].isalpha() or name in names or identifier in identifiers:
            raise BuildError(f"{path}:1:1: /materials/{index}/name: duplicate, empty, or colliding Roc slot name {name!r}")
        names.add(name); identifiers.add(identifier)
        result.append({"name": name, "identifier": identifier, "source_material": index})
    return result


def mesh_module(name, source, materials):
    lines = ["import pf.Shader", "", f"{name} := [].{{"]
    asset = Path(source).stem
    for material in materials:
        key, slot = material["identifier"], material["source_material"]
        lines += [f"\t## Source material {json.dumps(material['name'])}; independent of Mesh part order.", f"\tslot_{key} : Str -> Shader.Slot", f'\tslot_{key} = |pack| {{ mesh: {{ pack, asset: {json.dumps(asset)} }}, source_material: {slot} }}', f"\t## Assign this source material's Surface values.", f"\t{key} : Str, Shader.Values -> Shader.SlotAssignment", f"\t{key} = |pack, values| {{ slot: slot_{key}(pack), values }}"]
    if not materials:
        lines += ["\t## This source has no named materials.", "\tnamed_count : U32", "\tnamed_count = 0"]
    lines += ["}", ""]
    return module_source(lines)
