#!/usr/bin/env python3
"""Validate committed conversion products without Blender or the source archive."""
import hashlib
import json
from pathlib import Path
import struct
ROOT = Path(__file__).resolve().parents[1]

def validate():
    manifest = json.loads((ROOT / 'source/manifest.json').read_text())
    assert hashlib.sha256((ROOT / 'Layout.roc').read_bytes()).hexdigest() == manifest['layout_sha256'], 'Stale generated layout'
    names = set(manifest['assets'])
    assert names == {p.stem for p in (ROOT / 'assets/meshes').glob('*.glb')}, 'Unused or absent prepared assets'
    assert names == {p['asset'] for p in manifest['placements']}, 'Unused source assets'
    assert len({p['id'] for p in manifest['placements']}) == len(manifest['placements'])
    for name, record in manifest['assets'].items():
        data = (ROOT / 'assets/meshes' / f'{name}.glb').read_bytes()
        assert hashlib.sha256(data).hexdigest() == record['sha256'], name
        assert struct.unpack_from('<III', data) == (1179937895, 2, len(data)), name
        size, kind = struct.unpack_from('<II', data, 12)
        assert kind == 1313821514
        doc = json.loads(data[20:20 + size])
        start = 28 + size
        assert [m.get('name', '') for m in doc['materials']] == record['material_names']
        colours = 0
        for mesh in doc['meshes']:
            for primitive in mesh['primitives']:
                assert 'TANGENT' in primitive['attributes']
                colours += 'COLOR_0' in primitive['attributes']
                for index in primitive['attributes'].values():
                    accessor = doc['accessors'][index]
                    view = doc['bufferViews'][accessor['bufferView']]
                    assert view.get('byteOffset', 0) + view['byteLength'] <= doc['buffers'][0]['byteLength']
        assert colours == record['vertex_colour_primitives']
        for image in doc['images']:
            view = doc['bufferViews'][image['bufferView']]
            pos = start + view['byteOffset']
            assert data[pos:pos + 8] == b'\x89PNG\r\n\x1a\n'
            width, height = struct.unpack_from('>II', data, pos + 16)
            if manifest['texture_max_side']:
                assert max(width, height) <= manifest['texture_max_side']
    print(f"Validated {len(names)} GLBs and {len(manifest['placements'])} placements")
if __name__ == '__main__':
    validate()
