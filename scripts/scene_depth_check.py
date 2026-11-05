#!/usr/bin/env python3
"""Compare production scene-depth batches against individual native submissions."""
import argparse
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


def fixtures(out, probe=None):
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
    compiler = os.environ.get('ROCCO_SHDC', str(ROOT / 'build/shader-tools' / ('sokol-shdc.exe' if os.name == 'nt' else 'sokol-shdc')))
    if probe is None or probe == 'isolated':
        subprocess.run([sys.executable, str(ROOT / 'platform/shader-tools/build.py'), str(fixture / 'shaders.json'),
                        '--out', str(fixture / 'assets/shaders'), '--helpers', str(fixture / 'helpers'), '--shdc', compiler], check=True)
    else:
        build_probe_shaders(fixture, compiler, probe)
    (fixture / 'asset-hashes.json').write_text(json.dumps({str(path.relative_to(fixture)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((fixture / 'assets').rglob('*')) if path.is_file() and path.suffix in ('.glb', '.shaderpack')}, indent=2) + '\n')
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
                    direct = {}
                    for kind, encoded in (('individual', a), ('batched', b)):
                        path = out / f'{sample}-{pose}-depth-{kind}.f32'
                        if path.exists():
                            raw = path.read_bytes()
                            direct[kind] = dict(matches_export=raw == encoded, sha256=hashlib.sha256(raw).hexdigest(), byte_order=sys.byteorder)
                    if direct:
                        result['direct_readback'] = direct
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


def build_probe_shaders(fixture, compiler, probe):
    tools = ROOT / 'platform/shader-tools'
    sys.path.insert(0, str(tools))
    import build as shader_build
    original = shader_build.Composer
    applied = dict(clip=0, depth=0, fixup=0)

    class ProbeComposer(original):
        def template(self, name, replacements, hooks):
            replacements = dict(replacements)
            if name == 'vertex.glsl':
                if probe == 'gpu_product':
                    applied['clip'] += 1
                    replacements['@@CLIP@@'] = 'gl_Position = mvp * world_model * vec4(vertex.position, 1.0);'
                elif probe == 'pre_depth':
                    applied['clip'] += 1
                    self.append('noperspective out float probe_depth;')
                    replacements['@@CLIP@@'] += '\nprobe_depth = gl_Position.z / gl_Position.w;'
                elif probe == 'depth_fault':
                    applied['clip'] += 1
                    self.append('flat out float probe_instanced;')
                    replacements['@@CLIP@@'] += '\nprobe_instanced = ' + ('1.0;' if replacements['@@INSTANCE_INPUTS@@'] else '0.0;')
            return super().template(name, replacements, hooks)

        def append(self, source, path=None):
            if probe == 'zero_to_one':
                applied['fixup'] += source.count('@glsl_options fixup_clipspace')
                source = source.replace('@glsl_options fixup_clipspace', '')
            target = 'selected_depth = gl_FragCoord.z;'
            if target in source and probe == 'pre_depth':
                applied['depth'] += 1
                source = 'noperspective in float probe_depth;\n' + source.replace(target, 'selected_depth = probe_depth;')
            if target in source and probe == 'depth_fault':
                applied['depth'] += 1
                source = 'flat in float probe_instanced;\n' + source.replace(target, 'selected_depth = gl_FragCoord.z + probe_instanced * 0.00000011920928955078125;')
            return super().append(source, path)

    try:
        shader_build.Composer = ProbeComposer
        shader_build.build(fixture / 'shaders.json', fixture / 'assets/shaders', fixture / 'helpers', tools / 'contract-v1', compiler, False)
        required = ('fixup',) if probe == 'zero_to_one' else ('clip',) if probe == 'gpu_product' else ('clip', 'depth')
        if any(applied[name] == 0 for name in required):
            raise RuntimeError('fixture probe did not replace its expected shader sites')
        (fixture / 'composer-probe.json').write_text(json.dumps(dict(probe=probe, applied=applied), indent=2) + '\n')
    finally:
        shader_build.Composer = original
        sys.path.pop(0)


def run_fixture(binary, assets, out, probe=None):
    out.mkdir(parents=True, exist_ok=True)
    command = shlex.split(os.environ.get('RUN_PREFIX', '')) + [str(binary), str(assets), str(out)]
    if probe is not None:
        command.append(probe)
    process = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    log = process.stdout + process.stderr
    (out / 'native.log').write_text(log)
    metadata_path = out / 'metadata.json'
    metadata = json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
    samples = [int(n) for n in re.findall(r'SCENE_DEPTH_SAMPLES (\d+)', log)]
    result = dict(command=command, returncode=process.returncode, metadata=metadata, supported_samples=samples,
                  graphics_valid=not any(value in log for value in ('[sg][error]', '[sg][panic]', 'VALIDATION_FAILED')))
    if process.returncode == 0 and not metadata.get('skipped'):
        try:
            result['comparisons'] = compare(out, samples)
        except Exception as error:
            result['analysis_error'] = str(error)
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result, log


def raw_depth_passes(depth):
    return depth['max_absolute'] <= 2**-28 and depth['max_relative'] <= 2**-22 and depth['max_ulp'] <= 3


def collect_diagnostics(binary, out, metadata):
    results = {}
    for probe in ('isolated', 'gpu_product', 'pre_depth', 'zero_to_one', 'depth_fault'):
        directory = out / 'diagnostics' / probe
        directory.mkdir(parents=True, exist_ok=True)
        result = {}
        if metadata.get('driver', {}).get('backend') != 'GLCORE':
            result = dict(skipped='GL-only diagnostic control')
        elif probe == 'zero_to_one' and not metadata.get('driver', {}).get('clip_control'):
            result = dict(skipped='GL clip control is unsupported')
        else:
            try:
                assets = fixtures(directory, probe)
                result, _ = run_fixture(binary, assets, directory, probe)
                if result.get('supported_samples') != [1] or set(result.get('comparisons', {})) != {'1-0', '1-1'}:
                    raise RuntimeError('diagnostic did not capture both isolated poses at sample count 1')
                if 'comparisons' in result:
                    result['within_original_guard'] = {case: raw_depth_passes(values['depth_bits']) for case, values in result['comparisons'].items()}
                if probe == 'depth_fault' and 'comparisons' in result:
                    result['fault_rejected_by_original_guard'] = all(not raw_depth_passes(case['depth_bits']) for case in result['comparisons'].values())
                    result['fault_keeps_coverage'] = all(case['coverage']['exact'] for case in result['comparisons'].values())
            except Exception as error:
                result['error'] = str(error)
        results[probe] = result
        (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        (out / 'diagnostics.json').write_text(json.dumps(results, indent=2) + '\n')
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out', nargs='?', type=Path, default=ROOT / 'build/scene-depth-check')
    parser.add_argument('--diagnostics', action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    assets = fixtures(out)
    binary = out / ('scene-depth-check' + binary_suffix())
    command = [os.environ.get('ODIN', 'odin'), 'build', 'scripts/scene-depth-check', '-o:speed', '-strict-style', '-vet', '-out:' + str(binary)]
    subprocess.run(command, cwd=ROOT, check=True)
    result, log = run_fixture(binary, assets, out)
    print(log, end='')
    evidence = dict(build_command=command, supported_samples=result['supported_samples'], depth_limits=dict(absolute=2**-28, relative=2**-22, ulp=3),
                    comparisons=result.get('comparisons', {}), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), metadata=result['metadata'])
    (out / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    diagnostics = collect_diagnostics(binary, out, result['metadata']) if args.diagnostics else {}
    check(result['returncode'] == 0, 'scene-depth native fixture exits successfully')
    check(result['graphics_valid'], 'native graphics validation')
    check('analysis_error' not in result, 'scene-depth bit analysis completes')
    samples, comparisons = result['supported_samples'], result.get('comparisons', {})
    check(1 in samples, 'single-sample native comparison executes')
    for name, modes in comparisons.items():
        check(modes['coverage']['exact'], name + ' exact camera and Selection coverage')
        check(modes['final']['exact'], name + ' exact final colour with depth and Selection effect')
        check(raw_depth_passes(modes['depth_bits']), name + ' measured device-depth rounding bounds')
    for sample in samples:
        check(pixels(out / f'{sample}-0-0-batched.png') != pixels(out / f'{sample}-1-0-batched.png'), str(sample) + ' authored deformation changes scene depth')
    for probe, diagnostic in diagnostics.items():
        if diagnostic.get('skipped'):
            continue
        check('error' not in diagnostic and diagnostic.get('returncode') == 0 and diagnostic.get('graphics_valid') and 'analysis_error' not in diagnostic, probe + ' diagnostic completes')
        if probe == 'depth_fault':
            check(diagnostic.get('fault_rejected_by_original_guard') and diagnostic.get('fault_keeps_coverage'), 'injected depth fault remains red-capable')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
