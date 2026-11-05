#!/usr/bin/env python3
"""Prepare deterministic billboard sprites without an image library."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import zlib
import re
import zipfile

from prepare import IDENTITY, mul, read_accessor

OUT = Path(__file__).resolve().parents[1]
CHECKSUM = '2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d'


def png(path, size, alpha):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            opacity = max(0, min(1, alpha((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1)))
            rows.extend((255, 255, 255, round(opacity * 255)))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>2I5B', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))
    return {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'size': [size, size]}


def smoke(x, y):
    lobes = [(0, 0, 0.40), (-0.26, -0.1, 0.25), (0.24, 0.13, 0.28), (-0.05, 0.30, 0.25)]
    value = sum(math.exp(-((x - cx) ** 2 + (y - cy) ** 2) / radius ** 2 * 2) for cx, cy, radius in lobes)
    return min(1, value) * max(0, 1 - (x * x + y * y)) ** 2


def chimney(archive):
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == CHECKSUM
    root = 'cq-godot-3d-village-look/'
    with zipfile.ZipFile(archive) as source:
        text = source.read(root + 'scenes/world.tscn').decode()
        nodes = {}
        for header, body in re.findall(r'^\[node ([^\n]+)\]\n(.*?)(?=^\[|\Z)', text, re.M | re.S):
            parent = re.search('parent="([^"]+)"', header)
            if not parent:
                continue
            parent = parent[1]
            name = re.search('name="([^"]+)"', header)[1]
            path = name if parent == '.' else parent + '/' + name
            transform = re.search(r'transform = Transform3D\(([^)]+)\)', body)
            local = [float(x) for x in transform[1].split(',')] if transform else IDENTITY
            nodes[path] = mul(nodes.get(parent, IDENTITY), local)
        path = 'assets/village/Prop_Chimney.gltf'
        doc = json.loads(source.read(root + path))
        blob = source.read(root + str(Path(path).parent / doc['buffers'][0]['uri']))
        positions = {doc['materials'][p['material']]['name']: read_accessor(doc, blob, p['attributes']['POSITION']) for p in doc['meshes'][0]['primitives']}
        brick = positions['MI_Brick']
        top_y = max(v[1] for v in brick)
        top = sorted(set(v for v in brick if abs(v[1] - top_y) < 0.0001))
        center = [(min(v[k] for v in top) + max(v[k] for v in top)) / 2 for k in (0, 2)]
        assert max(abs(v) for v in center) < 0.0001
        rim_y = max(v[1] for v in positions['MI_RockTrim'])
        mouth = [0, 3.20, 0]
        assert mouth[1] > rim_y
        world = nodes['HouseA/Prop_Chimney2']
        return {'source': path, 'placement': 'HouseA/Prop_Chimney2', 'world_transform': world, 'brick_mouth_corners': top, 'rim_max_local_y': rim_y, 'emitter_local': mouth, 'emitter_world': [world[9 + r] + sum(world[k * 3 + r] * mouth[k] for k in range(3)) for r in range(3)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    mouth = chimney(args.archive)
    assets = {
        'image/village_smoke': png(OUT / 'assets/images/village_smoke.png', 128, smoke),
        'image/village_dust': png(OUT / 'assets/images/village_dust.png', 16, lambda x, y: max(0, 1 - x * x - y * y) ** 2),
    }
    (OUT / 'source/effects-manifest.json').write_text(json.dumps({'generator': 'source/prepare_effects.py', 'archive_sha256': CHECKSUM, 'chimney': mouth, 'assets': assets}, indent=2) + '\n')


if __name__ == '__main__':
    main()
