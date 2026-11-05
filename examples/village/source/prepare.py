#!/usr/bin/env python3
"""Prepare the complete verified village and its seeded source-scale grass field."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import zipfile
CHECKSUM = '2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d'
OUT = Path(__file__).resolve().parents[1]
IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]

def mul(a, b):
    return [sum((a[k * 3 + r] * b[c * 3 + k] for k in range(3))) for c in range(3) for r in range(3)] + [a[9 + r] + sum((a[k * 3 + r] * b[9 + k] for k in range(3))) for r in range(3)]

def decompose(m):
    scale = [math.sqrt(sum((m[c * 3 + r] ** 2 for r in range(3)))) for c in range(3)]
    r = [[m[c * 3 + i] / scale[c] for c in range(3)] for i in range(3)]
    for i in range(3):
        for j in range(3):
            assert abs(sum((r[k][i] * r[k][j] for k in range(3))) - (i == j)) < 1e-05, 'Sheared scene transform needs explicit support'
    trace = sum((r[i][i] for i in range(3)))
    if trace > 0:
        s = math.sqrt(trace + 1) * 2
        q = [(r[2][1] - r[1][2]) / s, (r[0][2] - r[2][0]) / s, (r[1][0] - r[0][1]) / s, s / 4]
    else:
        i = max(range(3), key=lambda i: r[i][i])
        j = (i + 1) % 3
        k = (i + 2) % 3
        s = math.sqrt(1 + r[i][i] - r[j][j] - r[k][k]) * 2
        q = [0, 0, 0, (r[k][j] - r[j][k]) / s]
        q[i] = s / 4
        q[j] = (r[j][i] + r[i][j]) / s
        q[k] = (r[k][i] + r[i][k]) / s
    return (m[9:], q, scale)

def read_accessor(doc, blob, idx):
    a = doc['accessors'][idx]
    v = doc['bufferViews'][a['bufferView']]
    formats = {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    fmt = '<' + formats[a['componentType']] * n
    size = struct.calcsize(fmt)
    start = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    return [struct.unpack_from(fmt, blob, start + i * v.get('byteStride', size)) for i in range(a['count'])]

def add_tangents(doc, blob):
    added = 0
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            at = p['attributes']
            if 'TANGENT' in at or 'TEXCOORD_0' not in at:
                continue
            pos = read_accessor(doc, blob, at['POSITION'])
            normals = read_accessor(doc, blob, at['NORMAL'])
            uv = read_accessor(doc, blob, at['TEXCOORD_0'])
            indices = [x[0] for x in read_accessor(doc, blob, p['indices'])] if 'indices' in p else list(range(len(pos)))
            tan = [[0.0, 0.0, 0.0] for _ in pos]
            bit = [[0.0, 0.0, 0.0] for _ in pos]
            for i in range(0, len(indices), 3):
                a, b, c = indices[i:i + 3]
                e1 = [pos[b][k] - pos[a][k] for k in range(3)]
                e2 = [pos[c][k] - pos[a][k] for k in range(3)]
                u1, v1 = [uv[b][k] - uv[a][k] for k in range(2)]
                u2, v2 = [uv[c][k] - uv[a][k] for k in range(2)]
                det = u1 * v2 - u2 * v1
                if abs(det) < 1e-12:
                    continue
                for vertex in (a, b, c):
                    for k in range(3):
                        tan[vertex][k] += (e1[k] * v2 - e2[k] * v1) / det
                        bit[vertex][k] += (e2[k] * u1 - e1[k] * u2) / det
            data = bytearray()
            for n, t, b in zip(normals, tan, bit):
                dot = sum((n[k] * t[k] for k in range(3)))
                t = [t[k] - n[k] * dot for k in range(3)]
                length = math.sqrt(sum((x * x for x in t)))
                if length < 1e-12:
                    axis = [1, 0, 0] if abs(n[0]) < 0.9 else [0, 1, 0]
                    dot = sum((n[k] * axis[k] for k in range(3)))
                    t = [axis[k] - n[k] * dot for k in range(3)]
                    length = math.sqrt(sum((x * x for x in t)))
                t = [x / length for x in t]
                cross = [n[1] * t[2] - n[2] * t[1], n[2] * t[0] - n[0] * t[2], n[0] * t[1] - n[1] * t[0]]
                data.extend(struct.pack('<4f', *t, -1.0 if sum((cross[k] * b[k] for k in range(3))) < 0 else 1.0))
            blob.extend(b'\x00' * (-len(blob) % 4))
            view = len(doc['bufferViews'])
            doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data), 'target': 34962})
            blob.extend(data)
            at['TANGENT'] = len(doc['accessors'])
            doc['accessors'].append({'bufferView': view, 'componentType': 5126, 'count': len(pos), 'type': 'VEC4'})
            added += 1
    return added

def pack(src, dest):
    doc = json.loads(src.read_text())
    old = copy.deepcopy(doc)
    blob = bytearray()
    offsets = []
    for buf in doc['buffers']:
        blob.extend(b'\x00' * (-len(blob) % 4))
        offsets.append(len(blob))
        blob.extend((src.parent / buf['uri']).read_bytes())
    for v in doc['bufferViews']:
        v['byteOffset'] = v.get('byteOffset', 0) + offsets[v['buffer']]
        v['buffer'] = 0
    tangents = add_tangents(doc, blob)
    for img in doc.get('images', []):
        if 'uri' not in img:
            continue
        payload = (src.parent / img.pop('uri')).read_bytes()
        blob.extend(b'\x00' * (-len(blob) % 4))
        img['bufferView'] = len(doc['bufferViews'])
        img['mimeType'] = 'image/png'
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(payload)})
        blob.extend(payload)
    doc['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(doc, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    blob.extend(b'\x00' * (-len(blob) % 4))
    dest.write_bytes(struct.pack('<III', 1179937895, 2, 28 + len(js) + len(blob)) + struct.pack('<II', len(js), 1313821514) + js + struct.pack('<II', len(blob), 5130562) + blob)
    assert doc['nodes'] == old['nodes'] and doc['materials'] == old['materials']
    return {'source': str(src).split('cq-godot-3d-village-look/')[-1], 'sha256': hashlib.sha256(dest.read_bytes()).hexdigest(), 'bytes': dest.stat().st_size, 'material_names': [m.get('name', '') for m in doc['materials']], 'vertex_colour_primitives': sum(('COLOR_0' in p['attributes'] for m in doc['meshes'] for p in m['primitives'])), 'generated_tangent_primitives': tangents}

def roc(v):
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return '[' + ', '.join((roc(x) for x in v)) + ']'
    if isinstance(v, dict):
        return '{ ' + ', '.join((k + ': ' + roc(x) for k, x in v.items())) + ' }'
    return str(float(v)) if isinstance(v, float) else str(v)

def vec(v):
    return dict(zip('xyz', v))

def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


class SourceRandom:
    """Godot 4.5 RandomPCG float sampling; see source/README-FOLIAGE.md."""

    def __init__(self, seed):
        self.state = 0
        self.increment = (1442695040888963407 << 1) | 1
        self.integer()
        self.state = (self.state + seed) & ((1 << 64) - 1)
        self.integer()

    def integer(self):
        old = self.state
        self.state = (old * 6364136223846793005 + self.increment) & ((1 << 64) - 1)
        value = (((old >> 18) ^ old) >> 27) & 0xffffffff
        rotation = old >> 59
        return ((value >> rotation) | (value << ((-rotation) & 31))) & 0xffffffff

    def unit(self):
        exponent = self.integer()
        if not exponent:
            return 0.0
        return f32(math.ldexp(f32(self.integer() | 0x80000001), -32 - (32 - exponent.bit_length())))

    def between(self, lo, hi):
        return f32(f32(self.unit() * f32(f32(hi) - f32(lo))) + f32(lo))


def field(root, count=22000):
    keep = json.loads((root / 'scenes/layout_data.json').read_text())['keep_out']
    kinds = [('Grass_Common_Short', .34), ('Grass_Common_Tall', .2), ('Grass_Wispy_Short', .24), ('Grass_Wispy_Tall', .12), ('Flower_3_Single', .03), ('Flower_4_Single', .03), ('Clover_1', .04)]
    rng = SourceRandom(777)
    rows = []
    tries = 0
    while len(rows) < count and tries < count * 4:
        tries += 1
        x, z = rng.between(-48, 48), rng.between(-56, 40)
        distance = math.hypot(x, z + 2)
        if distance > 26 and rng.unit() > 1 + (distance - 26) / 30 * (.15 - 1):
            continue
        if any(a - .15 <= x < a + w + .15 and b - .15 <= z < b + h + .15 for a, b, w, h in keep):
            continue
        roll, accumulated, kind = rng.unit(), 0.0, 0
        for i, (_, weight) in enumerate(kinds):
            accumulated += weight
            if roll <= accumulated:
                kind = i
                break
        scale = rng.between(.28, .48) if kind < 4 else rng.between(.24, .34)
        angle = rng.unit() * math.tau
        yscale = scale * rng.between(.85, 1.2)
        rows.append({'id': 100000 + len(rows), 'asset': kinds[kind][0], 'pos': vec([x, 0.0, z]), 'rot': dict(zip('xyzw', [0.0, math.sin(angle / 2), 0.0, math.cos(angle / 2)])), 'scale': vec([scale, yscale, scale])})
    assert len(rows) == count, 'Source field exhausted its placement budget'
    return rows, tries


def mesh_info(src, category):
    doc = json.loads(src.read_text())
    buffers = [(src.parent / b['uri']).read_bytes() for b in doc['buffers']]
    assert len(buffers) == 1
    leaves = [{'name': m.get('name', ''), 'index': i} for i, m in enumerate(doc['materials']) if 'Leaves' in m.get('name', '') or m.get('name') == 'Flowers']
    leaf_points, points = [], []
    has_weights = True
    parts = 0
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            positions = read_accessor(doc, buffers[0], primitive['attributes']['POSITION'])
            points.extend(positions)
            if primitive['material'] in [slot['index'] for slot in leaves]:
                leaf_points.extend(positions)
            has_weights = has_weights and 'COLOR_0' in primitive['attributes']
            material = doc['materials'][primitive['material']]
            parts += 2 if material.get('alphaMode') == 'BLEND' and material.get('doubleSided') else 1
    leaf_points = leaf_points or points
    lo = [min(p[i] for p in leaf_points) for i in range(3)]
    hi = [max(p[i] for p in leaf_points) for i in range(3)]
    return {'asset': src.stem, 'kind': category, 'leaves': leaves, 'canopy_center': vec([(a + b) / 2 for a, b in zip(lo, hi)]), 'canopy_radius': max((hi[0] - lo[0]) / 2, (hi[2] - lo[2]) / 2, .3), 'canopy_base': lo[1], 'plant_height': max(p[1] for p in points), 'vertex_weights': has_weights, 'parts': parts}


def prepare(root, blender, maximum):
    text = (root / 'scenes/world.tscn').read_text()
    resources = dict(((i, p) for p, i in re.findall('\\[ext_resource type="PackedScene" path="res://([^"]+)" id="([^"]+)"\\]', text)))
    nodes = {}
    rows = []
    assets = {}
    categories = {}
    baseline = {p['name']: p['id'] for p in json.loads((OUT / 'source/manifest.json').read_text())['placements']}
    boxes = []
    shapes = {name: [float(v) / 2 for v in size.split(',')] for name, size in re.findall(r'\[sub_resource type="BoxShape3D" id="([^"]+)"\]\nsize = Vector3\(([^)]+)\)', text)}
    for header, body in re.findall('^\\[node ([^\\n]+)\\]\\n(.*?)(?=^\\[|\\Z)', text, re.M | re.S):
        name = re.search('name="([^"]+)"', header)[1]
        parent = re.search('parent="([^"]+)"', header)
        if not parent:
            continue
        parent = parent[1]
        path = name if parent == '.' else parent + '/' + name
        transform = re.search('transform = Transform3D\\(([^)]+)\\)', body)
        local = [float(x) for x in transform[1].split(',')] if transform else IDENTITY
        world = mul(nodes.get(parent, IDENTITY), local)
        nodes[path] = world
        if parent == 'Colliders':
            shape = re.search(r'shape = SubResource\("([^"]+)"\)', body)
            pos, rot, scale = decompose(world)
            boxes.append({'id': 10 + len(boxes) * 10, 'pos': vec(pos), 'rot': dict(zip('xyzw', rot)), 'half': vec([v * s for v, s in zip(shapes[shape[1]], scale)])})
        inst = re.search('instance=ExtResource\\("([^"]+)"\\)', header)
        if not inst:
            continue
        pos, rot, scale = decompose(world)
        src = resources[inst[1]]
        key = Path(src).stem
        assets[key] = src
        categories[key] = 'Canopy' if any(g in header for g in ('"trees"', '"bushes"')) else 'Plant' if '"grass"' in header else categories.get(key, 'Static')
        group = {'HouseA': 10, 'HouseB': 20, 'HouseC': 30, 'HouseD': 40}.get(path.split('/')[0], 0)
        rows.append({'id': baseline.get(path, 10000 + len(rows)), 'name': path, 'asset': key, 'pos': vec(pos), 'rot': dict(zip('xyzw', rot)), 'scale': vec(scale), 'group': group})
    field_rows, field_tries = field(root)
    for row in field_rows:
        assets[row['asset']] = f"assets/nature/{row['asset']}.gltf"
        categories[row['asset']] = 'Plant'
    info = [mesh_info(root / src, categories[name]) for name, src in sorted(assets.items())]
    parts = {item['asset']: item['parts'] for item in info}
    capacities = {'meshes': len(assets), 'layout_draws': len(rows), 'field_draws': len(field_rows), 'layout_parts': sum(parts[row['asset']] for row in rows), 'field_parts': sum(parts[row['asset']] for row in field_rows)}
    capacities['total_parts'] = capacities['layout_parts'] + capacities['field_parts'] + 1
    print('Required capacities:', json.dumps(capacities), flush=True)
    images = sorted({str((root / src).parent / img['uri']) for src in assets.values() for img in json.loads((root / src).read_text()).get('images', []) if 'uri' in img})
    image_sources = {str(Path(p).relative_to(root)): hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in images}
    decoded_images = {}
    decoded_metadata = {}
    for image in images:
        payload = Path(image).read_bytes()
        if payload.startswith(b'\xff\xd8'):
            from PIL import Image, features, __version__ as pillow_version
            with Image.open(image) as original:
                pixels = original.tobytes()
                size, mode = original.size, original.mode
                original.save(image, format='PNG')
            with Image.open(image) as prepared:
                assert prepared.size == size and prepared.mode == mode and prepared.tobytes() == pixels
            relative = str(Path(image).relative_to(root))
            decoded_images[relative] = hashlib.sha256(Path(image).read_bytes()).hexdigest()
            decoded_metadata[relative] = {'decoder': 'Pillow', 'version': pillow_version, 'jpeg_codec': features.version_codec('jpg'), 'size': list(size), 'mode': mode, 'decoded_pixel_sha256': hashlib.sha256(pixels).hexdigest(), 'pixel_equality': True}
    if maximum:
        image_list = root / 'prepare-images.json'
        image_list.write_text(json.dumps(images))
        subprocess.run([blender, '--background', '--python', str(OUT / 'source/resize_textures.py'), '--', str(image_list), str(maximum)], check=True)
    report = {name: pack(root / src, OUT / 'assets/meshes' / f'{name}.glb') for name, src in sorted(assets.items())}
    (OUT / 'source/manifest.json').write_text(json.dumps({'archive_sha256': CHECKSUM, 'texture_max_side': maximum, 'original_texture_sha256': image_sources, 'decoded_texture_sha256': decoded_images, 'decoded_texture_metadata': decoded_metadata, 'assets': report, 'placements': rows, 'mesh_info': info, 'colliders': boxes, 'field': {'seed': 777, 'tries': field_tries, 'placements': field_rows}, 'capacities': capacities}, indent=2) + '\n')
    placement_type = '{ id : U64, name : Str, asset : Str, pos : { x : F32, y : F32, z : F32 }, rot : { x : F32, y : F32, z : F32, w : F32 }, scale : { x : F32, y : F32, z : F32 }, group : U64 }'
    vector_type = '{ x : F32, y : F32, z : F32 }'
    info_type = '{ asset : Str, kind : [Canopy, Plant, Static], leaves : List({ name : Str, index : U32 }), canopy_center : ' + vector_type + ', canopy_radius : F32, canopy_base : F32, plant_height : F32, vertex_weights : Bool, parts : U64 }'
    info_roc = roc(info)
    for category in ('Canopy', 'Plant', 'Static'):
        info_roc = info_roc.replace('"' + category + '"', category)
    info_roc = info_roc.replace('True', 'Bool.True').replace('False', 'Bool.False')
    box_type = '{ id : U64, pos : ' + vector_type + ', rot : { x : F32, y : F32, z : F32, w : F32 }, half : ' + vector_type + ' }'
    (OUT / 'Layout.roc').write_text('# Generated by source/prepare.py from world.tscn.\nLayout := [].{\n\tassets : List(Str)\n\tassets = ' + roc(sorted(assets)) + '\n\tPlacement : ' + placement_type + '\n\tplacements : List(Placement)\n\tplacements = ' + roc(rows) + '\n\tMeshInfo : ' + info_type + '\n\tmesh_info : List(MeshInfo)\n\tmesh_info = ' + info_roc + '\n\tcolliders : List(' + box_type + ')\n\tcolliders = ' + roc(boxes) + '\n}\n')
    field_type = '{ id : U64, asset : Str, pos : ' + vector_type + ', rot : { x : F32, y : F32, z : F32, w : F32 }, scale : ' + vector_type + ' }'
    (OUT / 'Field.roc').write_text('# Generated by source/prepare.py with the source field recipe and seed 777.\nField := [].{\n\tPlacement : ' + field_type + '\n\tplacements : List(Placement)\n\tplacements = ' + roc(field_rows) + '\n}\n')
    subprocess.run(['roc', 'fmt', str(OUT / 'Field.roc')], check=True)
    subprocess.run(['roc', 'fmt', str(OUT / 'Layout.roc')], check=True)
    manifest = json.loads((OUT / 'source/manifest.json').read_text())
    manifest['field_sha256'] = hashlib.sha256((OUT / 'Field.roc').read_bytes()).hexdigest()
    manifest['layout_sha256'] = hashlib.sha256((OUT / 'Layout.roc').read_bytes()).hexdigest()
    (OUT / 'source/manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    for src, dest in [('README.md', 'UPSTREAM-README.md'), ('assets/LICENSE_CC0_Quaternius.txt', 'LICENSE_CC0_Quaternius.txt')]:
        content = (root / src).read_bytes()
        if dest == 'LICENSE_CC0_Quaternius.txt':
            content = ('\n'.join(line.rstrip() for line in content.decode().strip().splitlines()) + '\n').encode()
        (OUT / 'source' / dest).write_bytes(content)
    print(f'Prepared {len(assets)} meshes and {len(rows)} placements')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    parser.add_argument('--blender', default='/Applications/Blender.app/Contents/MacOS/Blender')
    parser.add_argument('--max-texture-side', type=int, default=0)
    args = parser.parse_args()
    assert hashlib.sha256(args.archive.read_bytes()).hexdigest() == CHECKSUM, 'Source archive checksum differs'
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(args.archive) as archive:
            archive.extractall(tmp)
        prepare(Path(tmp) / 'cq-godot-3d-village-look', args.blender, args.max_texture_side)
if __name__ == '__main__':
    main()
