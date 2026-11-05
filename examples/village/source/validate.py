#!/usr/bin/env python3
"""Validate committed conversion products without Blender or the source archive."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import tempfile
import zipfile

from prepare import CHECKSUM, IDENTITY, decompose, field, mul
ROOT = Path(__file__).resolve().parents[1]

def validate():
    manifest = json.loads((ROOT / 'source/manifest.json').read_text())
    assert hashlib.sha256((ROOT / 'Layout.roc').read_bytes()).hexdigest() == manifest['layout_sha256'], 'Stale generated layout'
    assert hashlib.sha256((ROOT / 'Field.roc').read_bytes()).hexdigest() == manifest['field_sha256'], 'Stale generated field'
    assert len(manifest['placements']) == 1436
    assert len(manifest['field']['placements']) == 22000
    assert manifest['field']['seed'] == 777
    assert manifest['capacities']['total_parts'] < 32768
    assert len(manifest['assets']) < 128
    assert len(manifest['colliders']) == 6
    names = set(manifest['assets'])
    assert names == {p.stem for p in (ROOT / 'assets/meshes').glob('*.glb')}, 'Unused or absent prepared assets'
    assert names == {p['asset'] for p in manifest['placements'] + manifest['field']['placements']}, 'Unused source assets'
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
            payload = data[pos:pos + view['byteLength']]
            if manifest['texture_max_side'] == 0:
                assert hashlib.sha256(payload).hexdigest() in list(manifest['original_texture_sha256'].values()) + list(manifest.get('decoded_texture_sha256', {}).values()), name
            width, height = struct.unpack_from('>II', data, pos + 16)
            if manifest['texture_max_side']:
                assert max(width, height) <= manifest['texture_max_side']
    print(f"Validated {len(names)} GLBs and {len(manifest['placements'])} placements")
def validate_source(archive_path):
    assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == CHECKSUM
    manifest = json.loads((ROOT / 'source/manifest.json').read_text())
    with tempfile.TemporaryDirectory() as directory:
        with zipfile.ZipFile(archive_path) as archive:
            archive.extractall(directory)
        source = Path(directory) / 'cq-godot-3d-village-look'
        text = (source / 'scenes/world.tscn').read_text()
        transforms = {}
        placements = {p['name']: p for p in manifest['placements']}
        seen = set()
        for header, body in re.findall(r'^\[node ([^\n]+)\]\n(.*?)(?=^\[|\Z)', text, re.M | re.S):
            name = re.search(r'name="([^"]+)"', header)[1]
            parent = re.search(r'parent="([^"]+)"', header)
            if not parent:
                continue
            parent = parent[1]
            path = name if parent == '.' else parent + '/' + name
            transform = re.search(r'transform = Transform3D\(([^)]+)\)', body)
            local = [float(x) for x in transform[1].split(',')] if transform else IDENTITY
            world = mul(transforms.get(parent, IDENTITY), local)
            transforms[path] = world
            if 'instance=ExtResource' not in header:
                continue
            expected_position, expected_rotation, expected_scale = decompose(world)
            actual = placements[path]
            assert list(actual['pos'].values()) == expected_position, path
            assert list(actual['rot'].values()) == expected_rotation, path
            assert list(actual['scale'].values()) == expected_scale, path
            seen.add(path)
        assert seen == set(placements)
        generated_field, tries = field(source)
        assert generated_field == manifest['field']['placements']
        assert tries == manifest['field']['tries']
        for path, digest in manifest['original_texture_sha256'].items():
            assert hashlib.sha256((source / path).read_bytes()).hexdigest() == digest, path
    shapes = {shape['asset']: shape for shape in manifest['mesh_info']}
    minimum_canopy = min(min(p['scale'].values()) for p in manifest['placements'] if shapes[p['asset']]['kind'] == 'Canopy')
    minimum_plant = min(min(p['scale'].values()) for p in manifest['placements'] + manifest['field']['placements'] if shapes[p['asset']]['kind'] == 'Plant')
    assert (.12 * .85 * 1.2 ** 2 + .035 * 1.2) / minimum_canopy < .3
    assert math.sqrt(1 + .15 ** 2) * 1.7 * .22 / minimum_plant < 2
    print(f'Compared {len(seen)} cumulative source transforms and 22000 seeded field placements')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    validate()
    if args.archive:
        validate_source(args.archive)
