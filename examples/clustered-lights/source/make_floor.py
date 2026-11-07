#!/usr/bin/env python3
"""Build one checker floor mesh without an external asset tool."""

import json
import struct
from pathlib import Path


def build():
    positions, normals, colours, indices = [], [], [], []
    for z in range(10):
        for x in range(20):
            start = len(positions) // 3
            colour = 0.6 if (x + z) % 2 == 0 else 0.35
            for dx, dz in ((0, 0), (0, 2), (2, 2), (2, 0)):
                positions += [x * 2 - 20 + dx, 0, z * 2 - 10 + dz]
                normals += [0, 1, 0]
                colours += [colour, colour, colour, 1]
            indices += [start, start + 1, start + 2, start, start + 2, start + 3]
    blob = bytearray()
    views, accessors = [], []
    for values, format_, kind, width in ((positions, 'f', 'VEC3', 3), (normals, 'f', 'VEC3', 3), (colours, 'f', 'VEC4', 4), (indices, 'H', 'SCALAR', 1)):
        offset = len(blob)
        data = struct.pack('<' + format_ * len(values), *values)
        blob += data
        views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(data)})
        accessors.append({'bufferView': len(views) - 1, 'componentType': 5126 if format_ == 'f' else 5123, 'count': len(values) // width, 'type': kind})
    accessors[0].update(min=[-20, 0, -10], max=[20, 0, 10])
    gltf = {'asset': {'version': '2.0', 'generator': 'Rocco checker floor'}, 'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0}],
            'meshes': [{'name': 'floor', 'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'COLOR_0': 2}, 'indices': 3, 'material': 0}]}],
            'materials': [{'name': 'tiles', 'pbrMetallicRoughness': {'metallicFactor': 0, 'roughnessFactor': 1}}],
            'buffers': [{'byteLength': len(blob)}], 'bufferViews': views, 'accessors': accessors}
    metadata = json.dumps(gltf, sort_keys=True, separators=(',', ':')).encode()
    metadata += b' ' * (-len(metadata) % 4)
    blob += b'\0' * (-len(blob) % 4)
    return struct.pack('<III', 0x46546c67, 2, 28 + len(metadata) + len(blob)) + struct.pack('<II', len(metadata), 0x4e4f534a) + metadata + struct.pack('<II', len(blob), 0x004e4942) + blob


if __name__ == '__main__':
    destination = Path(__file__).resolve().parents[1] / 'assets/meshes/floor.glb'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(build())
