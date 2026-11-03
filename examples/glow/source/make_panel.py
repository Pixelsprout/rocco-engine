# Builds panel.glb, a ribbed metal-look plate with a normal map and an
# occlusion map, into the glow example's assets. Run from the repository root:
#   python3 examples/glow/source/make_panel.py
#
# One height field gives both maps, so the occlusion darkens the same seams
# and rivet rims that the normal map draws. The plate is dielectric paint:
# metallic 0 and roughness 0.45. It writes TANGENT, so the host makes none.

import json
import math
import os
import struct
import zlib

GLOW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(GLOW, "assets", "meshes", "panel.glb")

# Linear base colour, a cool grey paint.
PAINT = [0.32, 0.34, 0.38, 1.0]
ROUGHNESS = 0.45

SIZE = 0.9
HALF = SIZE / 2
THICKNESS = 0.02
MAP = 256
TEXEL = SIZE / MAP

# Heights in metres, on the plate's face. x is right and y is up.
BEVEL_WIDTH = 0.03
BEVEL_HEIGHT = 0.015
RIB_CENTRES = [-0.255, -0.085, 0.085, 0.255]
RIB_WIDTH = 0.13
RIB_LENGTH = 0.6
RIB_CAP = 0.03
RIB_HEIGHT = 0.035
SEAM_AT = 0.36
SEAM_HALF_WIDTH = 0.004
SEAM_DEPTH = 0.003
RIVET_AT = 0.39
RIVET_RADIUS = 0.012
RIVET_HEIGHT = 0.006
RIVETS = [(sx * RIVET_AT, sy * RIVET_AT) for sx in (-1, 0, 1) for sy in (-1, 0, 1) if (sx, sy) != (0, 0)]

# Occlusion: how far a texel sits below the average of its neighbours.
CAVITY_RADIUS = 5
CAVITY_GAIN = 250.0
CAVITY_FLOOR = 0.2

# The sides sample this UV, a flat texel in the gap between the middle ribs.
SIDE_UV = (0.5, 0.5)

FLOAT = 5126
UNSIGNED_SHORT = 5123
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963
LINEAR = 9729
LINEAR_MIPMAP_LINEAR = 9987
CLAMP_TO_EDGE = 33071


def bevel(x, y):
    edge = HALF - max(abs(x), abs(y))
    return BEVEL_HEIGHT * min(max(edge / BEVEL_WIDTH, 0.0), 1.0)


# A cosine profile across the rib, so each half of a rib is one flank. The
# ends round off over RIB_CAP.
def ribs(x, y):
    end = (RIB_LENGTH / 2 - abs(y)) / RIB_CAP
    if end <= 0.0:
        return 0.0
    cap = math.sin(min(end, 1.0) * math.pi / 2)
    height = 0.0
    for centre in RIB_CENTRES:
        across = abs(x - centre) / (RIB_WIDTH / 2)
        if across < 1.0:
            height += RIB_HEIGHT * 0.5 * (1.0 + math.cos(math.pi * across)) * cap
    return height


# A groove that frames the ribs.
def seams(x, y):
    off_x = abs(abs(x) - SEAM_AT) if abs(y) <= SEAM_AT else math.inf
    off_y = abs(abs(y) - SEAM_AT) if abs(x) <= SEAM_AT else math.inf
    off = min(off_x, off_y) / SEAM_HALF_WIDTH
    if off >= 1.0:
        return 0.0
    return -SEAM_DEPTH * 0.5 * (1.0 + math.cos(math.pi * off))


def rivets(x, y):
    for rx, ry in RIVETS:
        r = math.hypot(x - rx, y - ry) / RIVET_RADIUS
        if r < 1.0:
            return RIVET_HEIGHT * math.sqrt(1.0 - r * r)
    return 0.0


def height_field():
    rows = []
    for row in range(MAP):
        y = HALF - (row + 0.5) * TEXEL
        line = []
        for col in range(MAP):
            x = -HALF + (col + 0.5) * TEXEL
            line.append(bevel(x, y) + ribs(x, y) + seams(x, y) + rivets(x, y))
        rows.append(line)
    return rows


def at(h, row, col):
    return h[min(max(row, 0), MAP - 1)][min(max(col, 0), MAP - 1)]


# Tangent space follows glTF: red is +u, to the right, and green is up the
# image, towards decreasing v.
def normal_pixels(h):
    pixels = []
    for row in range(MAP):
        line = bytearray()
        for col in range(MAP):
            dx = (at(h, row, col + 1) - at(h, row, col - 1)) / (2 * TEXEL)
            dy = (at(h, row - 1, col) - at(h, row + 1, col)) / (2 * TEXEL)
            n = [-dx, -dy, 1.0]
            length = math.sqrt(sum(c * c for c in n))
            line += bytes(to_byte(c / length * 0.5 + 0.5) for c in n)
        pixels.append(bytes(line))
    return pixels


def box_blur(h):
    def blur_rows(grid):
        out = []
        for line in grid:
            sums = [0.0]
            for v in line:
                sums.append(sums[-1] + v)
            blurred = []
            for col in range(MAP):
                lo = max(col - CAVITY_RADIUS, 0)
                hi = min(col + CAVITY_RADIUS + 1, MAP)
                blurred.append((sums[hi] - sums[lo]) / (hi - lo))
            out.append(blurred)
        return out

    def transpose(grid):
        return [list(column) for column in zip(*grid)]

    return transpose(blur_rows(transpose(blur_rows(h))))


# Red is the occlusion. Green and blue are the constant roughness and
# metallic that metallicRoughnessTexture reads.
def orm_pixels(h):
    blurred = box_blur(h)
    pixels = []
    for row in range(MAP):
        line = bytearray()
        for col in range(MAP):
            cavity = max(blurred[row][col] - h[row][col], 0.0)
            ao = max(1.0 - CAVITY_GAIN * cavity, CAVITY_FLOOR)
            line += bytes([to_byte(ao), to_byte(ROUGHNESS), 0])
        pixels.append(bytes(line))
    return pixels


def to_byte(value):
    return min(max(int(value * 255.0 + 0.5), 0), 255)


def png(rows):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    raw = b"".join(b"\x00" + line for line in rows)
    header = struct.pack(">IIBBBBB", MAP, MAP, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


# Each face is a quad: its corners, its normal, its tangent and its UVs. The
# front face spans the whole map with u to the right and v down, so its
# tangent is +x with w 1.
def faces():
    front = [(-HALF, HALF, THICKNESS), (-HALF, -HALF, THICKNESS), (HALF, -HALF, THICKNESS), (HALF, HALF, THICKNESS)]
    front_uv = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
    quads = [(front, (0.0, 0.0, 1.0), (1.0, 0.0, 0.0, 1.0), front_uv)]
    for axis, sign in ((0, 1.0), (0, -1.0), (1, 1.0), (1, -1.0)):
        normal = [0.0, 0.0, 0.0]
        normal[axis] = sign
        along = [0.0, 0.0, 0.0]
        along[1 - axis] = HALF
        outer = [0.0, 0.0, 0.0]
        outer[axis] = sign * HALF
        corners = []
        for a, z in ((-1.0, 0.0), (-1.0, THICKNESS), (1.0, THICKNESS), (1.0, 0.0)):
            corners.append((outer[0] + a * along[0], outer[1] + a * along[1], z))
        # Keep the winding counter-clockwise seen from outside.
        if (axis == 0) == (sign > 0):
            corners.reverse()
        tangent = (0.0, 0.0, 1.0, 1.0)
        quads.append((corners, tuple(normal), tangent, [SIDE_UV] * 4))
    return quads


def mesh_bytes():
    positions, normals, tangents, uvs, indices = [], [], [], [], []
    for corners, normal, tangent, quad_uvs in faces():
        base = len(positions)
        positions += corners
        normals += [normal] * 4
        tangents += [tangent] * 4
        uvs += quad_uvs
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    return positions, normals, tangents, uvs, indices


def pack_floats(rows):
    return b"".join(struct.pack(f"<{len(r)}f", *r) for r in rows)


def pad(data, fill=b"\x00"):
    return data + fill * (-len(data) % 4)


def build():
    h = height_field()
    normal_png = png(normal_pixels(h))
    orm_png = png(orm_pixels(h))
    positions, normals, tangents, uvs, indices = mesh_bytes()
    count = len(positions)

    blobs = [
        (pack_floats(positions), ARRAY_BUFFER),
        (pack_floats(normals), ARRAY_BUFFER),
        (pack_floats(tangents), ARRAY_BUFFER),
        (pack_floats(uvs), ARRAY_BUFFER),
        (struct.pack(f"<{len(indices)}H", *indices), ELEMENT_ARRAY_BUFFER),
        (normal_png, None),
        (orm_png, None),
    ]
    buffer = b""
    views = []
    for data, target in blobs:
        view = {"buffer": 0, "byteOffset": len(buffer), "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        views.append(view)
        buffer += pad(data)

    lo = [min(p[i] for p in positions) for i in range(3)]
    hi = [max(p[i] for p in positions) for i in range(3)]
    accessors = [
        {"bufferView": 0, "componentType": FLOAT, "count": count, "type": "VEC3", "min": lo, "max": hi},
        {"bufferView": 1, "componentType": FLOAT, "count": count, "type": "VEC3"},
        {"bufferView": 2, "componentType": FLOAT, "count": count, "type": "VEC4"},
        {"bufferView": 3, "componentType": FLOAT, "count": count, "type": "VEC2"},
        {"bufferView": 4, "componentType": UNSIGNED_SHORT, "count": len(indices), "type": "SCALAR"},
    ]
    gltf = {
        "asset": {"version": "2.0", "generator": "examples/glow/source/make_panel.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "panel", "mesh": 0}],
        "meshes": [{"name": "panel", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TANGENT": 2, "TEXCOORD_0": 3}, "indices": 4, "material": 0}]}],
        "materials": [
            {
                "name": "panel",
                "pbrMetallicRoughness": {"baseColorFactor": PAINT, "metallicFactor": 0.0, "roughnessFactor": 1.0, "metallicRoughnessTexture": {"index": 1}},
                "normalTexture": {"index": 0, "scale": 1.0},
                "occlusionTexture": {"index": 1, "strength": 1.0},
            }
        ],
        "textures": [{"source": 0, "sampler": 0}, {"source": 1, "sampler": 0}],
        "images": [{"bufferView": 5, "mimeType": "image/png"}, {"bufferView": 6, "mimeType": "image/png"}],
        "samplers": [{"magFilter": LINEAR, "minFilter": LINEAR_MIPMAP_LINEAR, "wrapS": CLAMP_TO_EDGE, "wrapT": CLAMP_TO_EDGE}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(buffer)}],
    }
    text = pad(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(text) + 8 + len(buffer)
    return struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(text), 0x4E4F534A) + text + struct.pack("<II", len(buffer), 0x004E4942) + buffer


def glb_json(data):
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A, "the first chunk is not JSON"
    return json.loads(data[20 : 20 + length])


# Reads the JSON chunk back, so a change that drops a map, the shared ORM
# texture or TANGENT fails the run.
def check(data):
    gltf = glb_json(data)
    material = gltf["materials"][0]
    pbr = material["pbrMetallicRoughness"]
    assert material["occlusionTexture"]["index"] == pbr["metallicRoughnessTexture"]["index"], "the occlusion and the metallic-roughness do not share the ORM texture"
    assert material["normalTexture"]["index"] != material["occlusionTexture"]["index"], "the normal map is the ORM texture"
    assert "baseColorTexture" not in pbr and pbr["metallicFactor"] == 0.0, "the plate is not plain dielectric paint"
    primitive = gltf["meshes"][0]["primitives"][0]
    assert "TANGENT" in primitive["attributes"], "no TANGENT"
    print(f"panel.glb: {len(data)} bytes, {gltf['accessors'][0]['count']} vertices, normal map and ORM map {MAP} x {MAP}")


data = build()
check(data)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(os.path.normpath(OUT), "wb") as f:
    f.write(data)
