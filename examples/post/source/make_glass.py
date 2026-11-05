"""Build the synthetic alpha-zero, double-sided glass pane."""
import json
from pathlib import Path
import struct

positions = [(-.5, -.5, 0), (.5, -.5, 0), (.5, .5, 0), (-.5, .5, 0)]
data = struct.pack('<12f', *(n for p in positions for n in p))
data += struct.pack('<12f', *([0, 0, 1] * 4))
data += struct.pack('<8f', 0, 0, 1, 0, 1, 1, 0, 1)
data += struct.pack('<6H', 0, 1, 2, 0, 2, 3)
gltf = {
    'asset': {'version': '2.0', 'generator': 'examples/post/source/make_glass.py'},
    'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0}],
    'buffers': [{'byteLength': len(data)}],
    'bufferViews': [{'buffer': 0, 'byteOffset': 0, 'byteLength': 48}, {'buffer': 0, 'byteOffset': 48, 'byteLength': 48}, {'buffer': 0, 'byteOffset': 96, 'byteLength': 32}, {'buffer': 0, 'byteOffset': 128, 'byteLength': 12}],
    'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': 4, 'type': 'VEC3', 'min': [-.5, -.5, 0], 'max': [.5, .5, 0]}, {'bufferView': 1, 'componentType': 5126, 'count': 4, 'type': 'VEC3'}, {'bufferView': 2, 'componentType': 5126, 'count': 4, 'type': 'VEC2'}, {'bufferView': 3, 'componentType': 5123, 'count': 6, 'type': 'SCALAR'}],
    'materials': [{'name': 'Glass', 'alphaMode': 'BLEND', 'doubleSided': True, 'pbrMetallicRoughness': {'baseColorFactor': [.1, .7, .9, 0], 'roughnessFactor': 1, 'metallicFactor': 0}}],
    'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'indices': 3, 'material': 0}]}],
}
metadata = json.dumps(gltf, separators=(',', ':')).encode()
metadata += b' ' * (-len(metadata) % 4)
data += b'\0' * (-len(data) % 4)
chunks = struct.pack('<I4s', len(metadata), b'JSON') + metadata + struct.pack('<I4s', len(data), b'BIN\0') + data
Path(__file__).resolve().parents[1].joinpath('assets/meshes/glass.glb').write_bytes(struct.pack('<4sII', b'glTF', 2, 12 + len(chunks)) + chunks)
