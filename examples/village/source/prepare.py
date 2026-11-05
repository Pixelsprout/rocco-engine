#!/usr/bin/env python3
"""Prepare the verified village subset; optional texture resizing uses Blender."""
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

def prepare(root, blender, maximum):
    text = (root / 'scenes/world.tscn').read_text()
    resources = dict(((i, p) for p, i in re.findall('\\[ext_resource type="PackedScene" path="res://([^"]+)" id="([^"]+)"\\]', text)))
    nodes = {}
    rows = []
    assets = {}
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
        inst = re.search('instance=ExtResource\\("([^"]+)"\\)', header)
        if not inst:
            continue
        pos, rot, scale = decompose(world)
        keep = path.split('/')[0] in ('Lane', 'HouseA', 'HouseB') or ('lanterns' in header and abs(pos[0]) < 9 and (-4 < pos[2] < 12)) or (parent == 'Trees' and math.hypot(pos[0], pos[2] - 4) < 23)
        if not keep:
            continue
        src = resources[inst[1]]
        key = Path(src).stem
        assets[key] = src
        group = 10 if path.startswith('HouseA/') else 20 if path.startswith('HouseB/') else 0
        rows.append({'id': 100 + len(rows), 'name': path, 'asset': key, 'pos': vec(pos), 'rot': dict(zip('xyzw', rot)), 'scale': vec(scale), 'group': group})
    images = sorted({str((root / src).parent / img['uri']) for src in assets.values() for img in json.loads((root / src).read_text()).get('images', []) if 'uri' in img})
    image_sources = {str(Path(p).relative_to(root)): hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in images}
    if maximum:
        image_list = root / 'prepare-images.json'
        image_list.write_text(json.dumps(images))
        subprocess.run([blender, '--background', '--python', str(OUT / 'source/resize_textures.py'), '--', str(image_list), str(maximum)], check=True)
    report = {name: pack(root / src, OUT / 'assets/meshes' / f'{name}.glb') for name, src in sorted(assets.items())}
    (OUT / 'source/manifest.json').write_text(json.dumps({'archive_sha256': CHECKSUM, 'texture_max_side': maximum, 'original_texture_sha256': image_sources, 'assets': report, 'placements': rows}, indent=2) + '\n')
    (OUT / 'Layout.roc').write_text('# Generated by source/prepare.py from world.tscn.\nLayout := [].{\n\tassets : List(Str)\n\tassets = ' + roc(sorted(assets)) + '\n\tplacements : List({ id : U64, name : Str, asset : Str, pos : { x : F32, y : F32, z : F32 }, rot : { x : F32, y : F32, z : F32, w : F32 }, scale : { x : F32, y : F32, z : F32 }, group : U64 })\n\tplacements = ' + roc(rows) + '\n}\n')
    subprocess.run(['roc', 'fmt', str(OUT / 'Layout.roc')], check=True)
    manifest = json.loads((OUT / 'source/manifest.json').read_text())
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
    parser.add_argument('--max-texture-side', type=int, default=512)
    args = parser.parse_args()
    assert hashlib.sha256(args.archive.read_bytes()).hexdigest() == CHECKSUM, 'Source archive checksum differs'
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(args.archive) as archive:
            archive.extractall(tmp)
        prepare(Path(tmp) / 'cq-godot-3d-village-look', args.blender, args.max_texture_side)
if __name__ == '__main__':
    main()
