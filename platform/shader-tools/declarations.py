"""Strict author declarations with source diagnostics."""
import json
import math
from pathlib import Path
import re
import struct

TYPES = {"F32": 1, "Vec2": 2, "Vec3": 3, "Vec4": 4, "Colour": 4, "Bool": 1, "Mat4": 16}
NAME = re.compile(r"[a-z][a-z0-9_]*\Z")
MODULE = re.compile(r"[A-Z][A-Za-z0-9]*\Z")
RESERVED = {"app", "as", "break", "continue", "else", "expect", "for", "if", "import", "in", "match", "module", "package", "platform", "provides", "requires", "return", "where"}

class BuildError(ValueError):
    pass

class Document:
    def __init__(self, path):
        self.path = Path(path).resolve()
        self.text = self.path.read_text(encoding="utf-8")
        self.locations = {}
        self.pos = 0
        if len(self.text.encode()) > 1024 * 1024:
            raise BuildError(f"{self.path}:1:1: declaration exceeds 1 MiB")
        try:
            self.value = self.parse((), 0)
            self.space()
            if self.pos != len(self.text):
                self.fail((), "unexpected trailing JSON")
        except json.JSONDecodeError as error:
            raise BuildError(f"{self.path}:{error.lineno}:{error.colno}: {error.msg}") from error

    def space(self):
        while self.pos < len(self.text) and self.text[self.pos] in " \r\n\t":
            self.pos += 1

    def parse(self, path, depth):
        self.space()
        self.locations[path] = self.pos
        if depth > 32:
            self.fail(path, "declarations exceed maximum nesting")
        ch = self.text[self.pos:self.pos+1]
        if ch in ("{", "["):
            is_object = ch == "{"
            close = "}" if is_object else "]"
            self.pos += 1
            value = {} if is_object else []
            self.space()
            if self.text[self.pos:self.pos+1] == close:
                self.pos += 1
                return value
            while True:
                self.space()
                if is_object:
                    key, end = json.JSONDecoder().raw_decode(self.text, self.pos)
                    if not isinstance(key, str):
                        self.fail(path, "expected JSON object key")
                    self.locations[path + (key,)] = self.pos
                    if key in value:
                        self.fail(path + (key,), "duplicate declaration key")
                    self.pos = end
                    self.space()
                    if self.text[self.pos:self.pos+1] != ":":
                        self.fail(path + (key,), "expected ':'")
                    self.pos += 1
                    value[key] = self.parse(path + (key,), depth + 1)
                else:
                    value.append(self.parse(path + (len(value),), depth + 1))
                self.space()
                ch = self.text[self.pos:self.pos+1]
                self.pos += 1
                if ch == close:
                    return value
                if ch != ",":
                    self.fail(path, f"expected ',' or '{close}'")
        value, self.pos = json.JSONDecoder().raw_decode(self.text, self.pos)
        return value

    def fail(self, path, message):
        while path not in self.locations:
            path = path[:-1]
        at = self.locations[path]
        line = self.text.count("\n", 0, at) + 1
        column = at - self.text.rfind("\n", 0, at)
        pointer = "/" + "/".join(str(p) for p in path)
        raise BuildError(f"{self.path}:{line}:{column}: {pointer}: {message}")

    def object(self, value, path, required, optional=()):
        if not isinstance(value, dict):
            self.fail(path, "expected object")
        for key in required:
            if key not in value:
                self.fail(path, f"missing '{key}'")
        for key in value:
            if key not in set(required) | set(optional):
                self.fail(path + (key,), "unknown declaration")

    def array(self, value, path):
        if not isinstance(value, list):
            self.fail(path, "expected array")


def encode_parameter(kind, value):
    if not isinstance(kind, str) or kind not in TYPES or not isinstance(value, list) or len(value) != TYPES[kind]:
        raise BuildError("invalid parameter type or component count")
    if kind == "Bool":
        if type(value[0]) is not bool:
            raise BuildError("Bool requires true or false")
        value = [float(value[0])]
    for v in value:
        if type(v) not in (int, float) or abs(v) > 3.4028234663852886e38 or not math.isfinite(v):
            raise BuildError("expected finite binary32 components")
    return struct.pack("<" + "f" * max(4, len(value)), *(value + [0] * (-len(value) % 4)))


def source_path(doc, value, path):
    if type(value) is not str or not value or "\x00" in value:
        doc.fail(path, "expected source path")
    result = (doc.path.parent / value).resolve()
    if not result.is_file():
        doc.fail(path, f"missing source: {value}")
    return result


def validate(doc):
    root = doc.value
    doc.object(root, (), ("contract", "shaders"), ("meshes",))
    if type(root["contract"]) is not int or root["contract"] != 1:
        doc.fail(("contract",), "expected platform shader contract 1")
    modules = set()
    for group in ("shaders", "meshes"):
        doc.array(root.get(group, []), (group,))
        for index, item in enumerate(root.get(group, [])):
            path = (group, index)
            if group == "meshes":
                doc.object(item, path, ("name", "source"))
            else:
                doc.object(item, path, ("name", "kind"), ("vertex", "surface", "lighting", "post", "max_displacement", "skinning", "instancing", "parameters", "textures", "inputs", "locations"))
            name = item["name"]
            if not isinstance(name, str) or not MODULE.fullmatch(name) or name in modules or name in ("Shader", "Vocabulary", "Bool", "F32", "U32", "Str", "List", "Box", "Try", "Model"):
                doc.fail(path + ("name",), "expected unique Roc module name, for example Foliage")
            modules.add(name)
            if group == "meshes":
                source_path(doc, item["source"], path + ("source",))
                continue
            kind = item["kind"]
            if kind not in ("surface", "post"):
                doc.fail(path + ("kind",), "expected surface or post")
            if kind == "surface":
                if "max_displacement" not in item:
                    doc.fail(path, "Surface requires max_displacement")
                displacement = item["max_displacement"]
                if type(displacement) not in (int, float) or displacement < 0 or displacement > 3.4028234663852886e38 or not math.isfinite(displacement):
                    doc.fail(path + ("max_displacement",), "expected finite nonnegative displacement")
                if type(item.get("skinning", True)) is not bool:
                    doc.fail(path + ("skinning",), "expected boolean")
                if type(item.get("instancing", True)) is not bool:
                    doc.fail(path + ("instancing",), "expected boolean")
                forbidden = ("post", "inputs", "locations")
            else:
                forbidden = ("vertex", "surface", "lighting", "max_displacement", "skinning", "instancing")
                if "post" not in item:
                    doc.fail(path, "Post requires a post hook")
                for field, allowed in (("inputs", ("scene_colour", "scene_depth", "selection_coverage", "selection_depth")), ("locations", ("before_bloom", "after_tone_map"))):
                    values = item.get(field, [])
                    doc.array(values, path + (field,))
                    if not values or any(type(v) is not str or v not in allowed for v in values) or len(set(values)) != len(values):
                        doc.fail(path + (field,), "expected unique supported " + field)
            for field in forbidden:
                if field in item:
                    doc.fail(path + (field,), "not valid for this shader kind")
            for hook in ("vertex", "surface", "lighting", "post"):
                if hook in item:
                    source_path(doc, item[hook], path + (hook,))
            offsets = {"vertex": 0, "fragment": 0}
            for field in ("parameters", "textures"):
                names = set()
                entries = item.setdefault(field, [])
                doc.array(entries, path + (field,))
                if field == "textures" and len(entries) > 4:
                    doc.fail(path + (field,), "at most four game textures")
                for i, entry in enumerate(entries):
                    ep = path + (field, i)
                    required = ("name", "scope", "stage", "type", "default")
                    if field == "textures":
                        required += ("colour_space", "sampler_policy")
                    doc.object(entry, ep, required, ("optional",) if field == "textures" else ())
                    n = entry["name"]
                    if not isinstance(n, str) or not NAME.fullmatch(n) or n in names or n in RESERVED or n in ("shader", "scope", "parameters", "textures") or (field == "textures" and n in ("default", "with_textures", "textures_default")):
                        doc.fail(ep + ("name",), "invalid, reserved, or duplicate name")
                    names.add(n)
                    if entry["scope"] not in ("Scene", "Material", "Draw") or entry["stage"] not in ("vertex", "fragment"):
                        doc.fail(ep, "invalid scope or stage")
                    if kind == "post" and (entry["scope"] == "Material" or entry["stage"] != "fragment"):
                        doc.fail(ep, "Post accepts Scene or Draw fragment values")
                    if field == "parameters":
                        try:
                            data = encode_parameter(entry["type"], entry["default"])
                        except BuildError as error:
                            doc.fail(ep + ("default",), str(error))
                        stage = entry["stage"]
                        entry["offset"] = offsets[stage]
                        offsets[stage] += len(data)
                        if offsets[stage] > 256:
                            doc.fail(ep, "parameter exceeds 256-byte stage block")
                    else:
                        validate_texture(doc, entry, ep, kind)
                        entry.update(view=8 + i, sampler=8 + i, sample_type="float")
    return root


def validate_texture(doc, entry, ep, kind):
    if entry["type"] not in ("2d", "cube") or entry["colour_space"] not in ("linear", "srgb"):
        doc.fail(ep, "invalid texture dimension or colour space")
    policy = entry["sampler_policy"]
    doc.object(policy, ep + ("sampler_policy",), ("min", "mag", "wrap"))
    if policy["min"] not in ("nearest", "linear") or policy["mag"] not in ("nearest", "linear") or policy["wrap"] not in ("clamp", "repeat", "mirror"):
        doc.fail(ep + ("sampler_policy",), "invalid sampler policy")
    if type(entry.get("optional", False)) is not bool:
        doc.fail(ep + ("optional",), "expected boolean")
    default = entry["default"]
    if not isinstance(default, dict):
        doc.fail(ep + ("default",), "texture requires a default source")
    if set(default) == {"constant"}:
        if entry.get("optional") is not True:
            doc.fail(ep + ("default",), "constant requires optional texture")
        try:
            encode_parameter("Vec4", default["constant"])
        except BuildError as error:
            doc.fail(ep + ("default",), str(error))
    elif set(default) == {"imported"}:
        if kind != "surface" or entry["scope"] != "Material" or entry["type"] != "2d" or default["imported"] not in ("base_colour", "metallic_roughness", "emissive", "normal", "occlusion"):
            doc.fail(ep + ("default",), "invalid imported texture default")
        colour_space = "srgb" if default["imported"] in ("base_colour", "emissive") else "linear"
        if entry["colour_space"] != colour_space:
            doc.fail(ep + ("colour_space",), "colour space differs from imported semantic")
    elif set(default) == {"pack", "asset"}:
        if any(type(v) is not str or not v or "\x00" in v for v in default.values()):
            doc.fail(ep + ("default",), "invalid Pack asset reference")
    else:
        doc.fail(ep + ("default",), "unknown texture default source")
