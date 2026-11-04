# Builds the mask example's meshes into its assets. Run from the repository
# root:
#   python3 examples/mask/source/make_props.py
#
# fence.glb and fence_one_sided.glb are a chain-link panel, Mask with the
# default cutoff of 0.5. Only fence.glb is double-sided. leaf.glb is a
# double-sided Mask leaf on a plane. pip_holes.glb is the tutorial's Pip with
# a round hole in every cell of a grid over its height, double-sided.
# A rerun writes the same bytes.

import json
import math
import os
import struct
import zlib

MASK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MESHES = os.path.join(MASK, "assets", "meshes")
PIP = os.path.join(MASK, "..", "tutorial", "04-lights", "assets", "meshes", "pip.glb")

FLOAT = 5126
UNSIGNED_SHORT = 5123
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963
LINEAR = 9729
LINEAR_MIPMAP_LINEAR = 9987

FENCE_WIDTH = 2.4
FENCE_HEIGHT = 1.4
# One diamond of the chain-link is this wide, in metres.
LINK = 0.15
LINK_MAP = 64
WIRE = 0.09

LEAF_SIZE = 0.9
LEAF_MAP = 128

HOLE_MAP = 32
HOLE_RADIUS = 0.32
# Pip's height holds this many rows of holes.
HOLE_ROWS = 9.0


def png(width, height, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * width * 4:(y + 1) * width * 4]) for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def to_byte(v):
    return max(0, min(255, round(v * 255)))


# Linear 0 to 1 over one texel either side of the edge, so the cutoff edge
# stays smooth under LINEAR filtering.
def coverage(distance_inside, texel):
    return max(0.0, min(1.0, 0.5 + distance_inside / texel))


# Two sets of diagonal wires. The texture repeats every LINK_MAP texels.
def chain_link():
    pixels = []
    texel = 1.0 / LINK_MAP
    for y in range(LINK_MAP):
        for x in range(LINK_MAP):
            u, v = (x + 0.5) / LINK_MAP, (y + 0.5) / LINK_MAP
            near = 1.0
            for d in (u + v, u - v):
                f = d - math.floor(d)
                near = min(near, min(f, 1.0 - f) / math.sqrt(2))
            alpha = coverage(WIRE / 2 - near, texel)
            shine = 0.75 + 0.25 * math.cos(near / (WIRE / 2) * math.pi / 2)
            pixels += [to_byte(shine), to_byte(shine), to_byte(shine * 1.02), to_byte(alpha)]
    return png(LINK_MAP, LINK_MAP, pixels)


# A pointed leaf along v, with a midrib and side veins drawn darker.
def leaf():
    pixels = []
    texel = 2.0 / LEAF_MAP
    for y in range(LEAF_MAP):
        for x in range(LEAF_MAP):
            u = (x + 0.5) / LEAF_MAP * 2.0 - 1.0
            v = (y + 0.5) / LEAF_MAP * 2.0 - 1.0
            half_width = 0.55 * max(0.0, 1.0 - v * v) ** 0.7
            blade = half_width - abs(u)
            stem = 0.03 - abs(u) if v > 0.9 else -1.0
            alpha = coverage(max(blade, stem), texel)
            vein = abs(u) < 0.025 or (abs(((v + abs(u) * 0.8) * 5.0) % 1.0 - 0.5) < 0.06 and blade > 0.04)
            shade = 0.6 if vein else 1.0
            pixels += [to_byte(0.18 * shade), to_byte(0.55 * shade), to_byte(0.12 * shade), to_byte(alpha)]
    return png(LEAF_MAP, LEAF_MAP, pixels)


# White with one round hole in the middle of the cell.
def holes():
    pixels = []
    texel = 1.0 / HOLE_MAP
    for y in range(HOLE_MAP):
        for x in range(HOLE_MAP):
            u, v = (x + 0.5) / HOLE_MAP - 0.5, (y + 0.5) / HOLE_MAP - 0.5
            alpha = coverage(math.hypot(u, v) - HOLE_RADIUS, texel)
            pixels += [255, 255, 255, to_byte(alpha)]
    return png(HOLE_MAP, HOLE_MAP, pixels)


class Glb:
    def __init__(self, gltf=None, binary=b""):
        self.gltf = gltf or {"asset": {"version": "2.0", "generator": "examples/mask/source/make_props.py"}, "buffers": [{"byteLength": 0}]}
        self.binary = bytearray(binary)
        for key in ("bufferViews", "accessors", "images", "samplers", "textures", "materials", "meshes"):
            self.gltf.setdefault(key, [])

    def view(self, data, target=None):
        while len(self.binary) % 4:
            self.binary.append(0)
        entry = {"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(data)}
        if target:
            entry["target"] = target
        self.binary += data
        self.gltf["bufferViews"].append(entry)
        return len(self.gltf["bufferViews"]) - 1

    def accessor(self, values, kind, width, component=FLOAT, target=ARRAY_BUFFER, bounds=False):
        fmt = "<H" if component == UNSIGNED_SHORT else "<" + "f" * width
        data = b"".join(struct.pack(fmt, *v) if width > 1 else struct.pack(fmt, v) for v in values)
        entry = {"bufferView": self.view(data, target), "componentType": component, "count": len(values), "type": kind}
        if bounds:
            entry["min"] = [min(v[i] for v in values) for i in range(width)]
            entry["max"] = [max(v[i] for v in values) for i in range(width)]
        self.gltf["accessors"].append(entry)
        return len(self.gltf["accessors"]) - 1

    def texture(self, image):
        self.gltf["images"].append({"bufferView": self.view(image), "mimeType": "image/png"})
        self.gltf["samplers"].append({"magFilter": LINEAR, "minFilter": LINEAR_MIPMAP_LINEAR})
        self.gltf["textures"].append({"source": len(self.gltf["images"]) - 1, "sampler": len(self.gltf["samplers"]) - 1})
        return len(self.gltf["textures"]) - 1

    def write(self, path):
        while len(self.binary) % 4:
            self.binary.append(0)
        self.gltf["buffers"][0]["byteLength"] = len(self.binary)
        for key in [k for k, v in self.gltf.items() if v == []]:
            del self.gltf[key]
        text = json.dumps(self.gltf, separators=(",", ":")).encode()
        while len(text) % 4:
            text += b" "
        out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(self.binary))
        out += struct.pack("<II", len(text), 0x4E4F534A) + text
        out += struct.pack("<II", len(self.binary), 0x004E4942) + bytes(self.binary)
        with open(path, "wb") as f:
            f.write(out)


# A quad in x-y, facing +z, with its bottom edge on y = bottom.
def quad_mesh(name, width, height, bottom, uv_scale, image, material):
    glb = Glb()
    x, top = width / 2, bottom + height
    positions = [(-x, bottom, 0.0), (x, bottom, 0.0), (x, top, 0.0), (-x, top, 0.0)]
    normals = [(0.0, 0.0, 1.0)] * 4
    su, sv = uv_scale
    uvs = [(0.0, sv), (su, sv), (su, 0.0), (0.0, 0.0)]
    material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": glb.texture(image)}
    glb.gltf["materials"].append(material)
    primitive = {
        "attributes": {
            "POSITION": glb.accessor(positions, "VEC3", 3, bounds=True),
            "NORMAL": glb.accessor(normals, "VEC3", 3),
            "TEXCOORD_0": glb.accessor(uvs, "VEC2", 2),
        },
        "indices": glb.accessor([0, 1, 2, 0, 2, 3], "SCALAR", 1, UNSIGNED_SHORT, ELEMENT_ARRAY_BUFFER),
        "material": 0,
    }
    glb.gltf["meshes"].append({"name": name, "primitives": [primitive]})
    glb.gltf["nodes"] = [{"mesh": 0, "name": name}]
    glb.gltf["scenes"] = [{"nodes": [0]}]
    glb.gltf["scene"] = 0
    return glb


def fence(double_sided):
    material = {"name": "chain-link", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.82, 1.0], "metallicFactor": 1.0, "roughnessFactor": 0.4}, "alphaMode": "MASK", "doubleSided": double_sided}
    return quad_mesh("fence", FENCE_WIDTH, FENCE_HEIGHT, 0.0, (FENCE_WIDTH / LINK, FENCE_HEIGHT / LINK), chain_link(), material)


def leaf_mesh():
    material = {"name": "leaf", "pbrMetallicRoughness": {"baseColorFactor": [1.0, 1.0, 1.0, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.6}, "alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True}
    return quad_mesh("leaf", LEAF_SIZE, LEAF_SIZE, -LEAF_SIZE / 2, (1.0, 1.0), leaf(), material)


# Planar UVs from Pip's x and y, so the holes run in a grid up its body.
def pip_holes():
    with open(PIP, "rb") as f:
        data = f.read()
    json_length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + json_length])
    start = 20 + json_length
    bin_length = struct.unpack("<I", data[start:start + 4])[0]
    glb = Glb(gltf, data[start + 8:start + 8 + bin_length])
    texture = glb.texture(holes())
    lo = min(gltf["accessors"][p["attributes"]["POSITION"]]["min"][1] for m in gltf["meshes"] for p in m["primitives"])
    hi = max(gltf["accessors"][p["attributes"]["POSITION"]]["max"][1] for m in gltf["meshes"] for p in m["primitives"])
    cell = (hi - lo) / HOLE_ROWS
    for m in gltf["meshes"]:
        for p in m["primitives"]:
            accessor = gltf["accessors"][p["attributes"]["POSITION"]]
            view = gltf["bufferViews"][accessor["bufferView"]]
            stride = view.get("byteStride", 12)
            base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
            uvs = []
            for i in range(accessor["count"]):
                x, y, z = struct.unpack_from("<fff", glb.binary, base + i * stride)
                uvs.append(((x + z * 0.5) / cell, (y - lo) / cell))
            p["attributes"]["TEXCOORD_0"] = glb.accessor(uvs, "VEC2", 2)
    for material in gltf["materials"]:
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": texture}
        material["alphaMode"] = "MASK"
        material["doubleSided"] = True
    gltf["asset"]["generator"] = "examples/mask/source/make_props.py from tutorial/04-lights pip.glb"
    return glb


def main():
    os.makedirs(MESHES, exist_ok=True)
    fence(True).write(os.path.join(MESHES, "fence.glb"))
    fence(False).write(os.path.join(MESHES, "fence_one_sided.glb"))
    leaf_mesh().write(os.path.join(MESHES, "leaf.glb"))
    pip_holes().write(os.path.join(MESHES, "pip_holes.glb"))


main()
