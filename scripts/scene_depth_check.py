#!/usr/bin/env python3
"""Compare production scene-depth batches against individual native submissions."""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import sys
import zlib

from bridge import png_rgba
from bridge_check import binary_suffix, check

ROOT = Path(__file__).resolve().parents[1]


def fixtures(out):
    source = ROOT / 'examples/post'
    declaration = json.loads((source / 'shaders.json').read_text())['shaders'][0]
    shaders = [dict(declaration, instancing=True), dict(declaration, name='RigidFoliage', instancing=False),
               dict(name='Inspect', kind='post', post='inspect.glsl',
                    inputs=['scene_colour', 'scene_depth', 'selection_coverage', 'selection_depth'],
                    locations=['after_tone_map'], parameters=[dict(name='mode', type='F32', scope='Draw', stage='fragment', default=[0])])]
    fixture = out / 'fixture'
    fixture.mkdir(exist_ok=True)
    for name in ('wind.glsl', 'leaves.glsl'):
        shutil.copy2(source / name, fixture / name)
    shutil.copy2(ROOT / 'scripts/scene-depth-check/inspect.glsl', fixture / 'inspect.glsl')
    (fixture / 'shaders.json').write_text(json.dumps(dict(contract=1, shaders=shaders)))
    meshes = fixture / 'assets/meshes'
    meshes.mkdir(parents=True, exist_ok=True)
    for name in ('tree.glb', 'pip.glb'):
        shutil.copy2(source / 'assets/meshes' / name, meshes / name)
    subprocess.run([sys.executable, str(ROOT / 'platform/shader-tools/build.py'), str(fixture / 'shaders.json'),
                    '--out', str(fixture / 'assets/shaders'), '--helpers', str(fixture / 'helpers'),
                    '--shdc', os.environ.get('ROCCO_SHDC', str(ROOT / 'build/shader-tools' / ('sokol-shdc.exe' if os.name == 'nt' else 'sokol-shdc')))], check=True)
    return fixture / 'assets'


def pixels(path):
    return png_rgba(path.read_bytes())[2]


def compare(out, samples):
    results = {}
    for sample in samples:
        for pose in range(2):
            modes = {}
            for mode, name in enumerate(('depth_bits', 'coverage', 'final', 'zero_bias_diagnostic')):
                a, b = [pixels(out / f'{sample}-{pose}-{mode}-{kind}.png') for kind in ('individual', 'batched')]
                result = dict(changed_channels=sum(x != y for x, y in zip(a, b)), exact=a == b,
                              individual_sha256=hashlib.sha256(a).hexdigest(), batched_sha256=hashlib.sha256(b).hexdigest())
                if mode == 0:
                    left, right = [struct.unpack('<' + 'f' * (len(value) // 4), value) for value in (a, b)]
                    check(all(math.isfinite(value) and value >= 0 for values in (left, right) for value in values), 'finite nonnegative device depth')
                    result.update(changed_depths=sum(x != y for x, y in zip(left, right)),
                                  max_absolute=max(abs(x-y) for x, y in zip(left, right)),
                                  max_relative=max((abs(x-y)/max(abs(x), abs(y)) if x or y else 0) for x, y in zip(left, right)),
                                  max_ulp=max(abs(x-y) for x, y in zip(struct.unpack('<' + 'I' * len(left), a), struct.unpack('<' + 'I' * len(right), b))))
                modes[name] = result
                if a != b:
                    save_diff(out / f'{sample}-{pose}-{mode}-diff.png', a, b)
            results[f'{sample}-{pose}'] = modes
    return results


def save_diff(path, left, right):
    width, height = 480, 360
    pixels = bytearray(len(left))
    for i in range(0, len(left), 4):
        changed = left[i:i+4] != right[i:i+4]
        pixels[i:i+4] = bytes((255 if changed else 0,) * 3 + (255,))
    rows = b''.join(b'\0' + pixels[y*width*4:(y+1)*width*4] for y in range(height))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / 'build/scene-depth-check').resolve()
    out.mkdir(parents=True, exist_ok=True)
    assets = fixtures(out)
    binary = out / ('scene-depth-check' + binary_suffix())
    command = [os.environ.get('ODIN', 'odin'), 'build', 'scripts/scene-depth-check', '-o:speed', '-strict-style', '-vet', '-out:' + str(binary)]
    subprocess.run(command, cwd=ROOT, check=True)
    result = subprocess.run(shlex.split(os.environ.get('RUN_PREFIX', '')) + [str(binary), str(assets), str(out)], cwd=ROOT, text=True, capture_output=True)
    log = result.stdout + result.stderr
    (out / 'native.log').write_text(log)
    print(log, end='')
    check(result.returncode == 0, 'scene-depth native fixture exits successfully')
    check('[sg][error]' not in log and '[sg][panic]' not in log and 'VALIDATION_FAILED' not in log, 'native graphics validation')
    samples = [int(n) for n in re.findall(r'SCENE_DEPTH_SAMPLES (\d+)', log)]
    check(1 in samples, 'single-sample native comparison executes')
    comparisons = compare(out, samples)
    evidence = dict(build_command=command, supported_samples=samples, depth_limits=dict(absolute=2**-28, relative=2**-22, ulp=3), comparisons=comparisons, binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
    (out / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    for name, modes in comparisons.items():
        check(modes['coverage']['exact'], name + ' exact camera and Selection coverage')
        check(modes['final']['exact'], name + ' exact final colour with depth and Selection effect')
        depth = modes['depth_bits']
        check(depth['max_absolute'] <= 2**-28 and depth['max_relative'] <= 2**-22 and depth['max_ulp'] <= 3, name + ' measured device-depth rounding bounds')
    for sample in samples:
        check(pixels(out / f'{sample}-0-0-batched.png') != pixels(out / f'{sample}-1-0-batched.png'), str(sample) + ' authored deformation changes scene depth')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
