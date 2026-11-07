"""Preserve bounded evidence for the hosted village rendering probe."""
from collections import Counter
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

from capture import GAME, ROOT
from foliage import draws


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def progress(out, event, **values):
    row = dict(event=event, monotonic_seconds=time.monotonic(), **values)
    with (out / 'progress.jsonl').open('a') as stream:
        stream.write(json.dumps(row, sort_keys=True) + '\n')
    print('[village-probe]', json.dumps(row, sort_keys=True), flush=True)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def command(args, timeout=15):
    try:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        return dict(command=args, returncode=result.returncode, output=result.stdout[:65536].decode(errors='replace'))
    except (OSError, subprocess.TimeoutExpired) as error:
        return dict(command=args, error=str(error))


def preserve(out):
    destination = out / 'provenance'
    destination.mkdir(exist_ok=True)
    suffix, target = ('.exe', 'x64win') if sys.platform == 'win32' else ('_linux.bin', 'x64glibc') if sys.platform.startswith('linux') else ('.bin', 'arm64mac')
    binary = GAME / ('village' + suffix)
    shutil.copy2(binary, destination / binary.name)
    shader_dir = GAME / 'assets/shaders'
    generated = {}
    for path in sorted(shader_dir.rglob('*')):
        if not path.is_file():
            continue
        name = path.relative_to(shader_dir).as_posix()
        generated[name] = dict(bytes=path.stat().st_size, sha256=digest(path))
        copy = destination / 'shaders' / name
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, copy)
    assets = {path.relative_to(GAME).as_posix(): dict(bytes=path.stat().st_size, sha256=digest(path))
              for path in sorted((GAME / 'assets').rglob('*')) if path.is_file() and shader_dir not in path.parents}
    libraries = {path.name: dict(bytes=path.stat().st_size, sha256=digest(path))
                 for path in sorted((ROOT / 'platform/targets' / target).iterdir()) if path.is_file()}
    sources = {path.relative_to(GAME).as_posix(): digest(path)
               for path in sorted(GAME.rglob('*')) if path.is_file() and path.suffix in ('.roc', '.glsl', '.json', '.py') and 'assets' not in path.relative_to(GAME).parts}
    runtime = dict(system=platform.platform(), machine=platform.machine(), python=sys.version,
                   run_prefix=os.environ.get('RUN_PREFIX', ''),
                   environment={key: os.environ[key] for key in ('ROCCO_SHDC', 'LIBGL_ALWAYS_SOFTWARE', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'RUNNER_OS', 'RUNNER_ARCH') if key in os.environ})
    commands = [['odin', 'version'], ['roc', 'version'], ['git', '-C', str(ROOT), 'rev-parse', 'HEAD']]
    if sys.platform == 'darwin':
        commands += [['sw_vers'], ['system_profiler', 'SPDisplaysDataType', '-json', '-detailLevel', 'mini'], ['xcrun', 'clang', '--version']]
    elif sys.platform.startswith('linux'):
        commands += [['uname', '-a'], ['sh', '-c', "dpkg-query -W 'libgl1-mesa-dri' 'libglx-mesa0' 'mesa-vulkan-drivers'"]]
    else:
        commands += [['powershell', '-NoProfile', '-Command', 'Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM | ConvertTo-Json']]
    runtime['commands'] = [command(args) for args in commands]
    write_json(destination / 'runtime.json', runtime)
    write_json(destination / 'inputs.json', dict(binary=dict(name=binary.name, bytes=binary.stat().st_size, sha256=digest(binary)), generated=generated, assets=assets, libraries=libraries, sources=sources))
    build = json.loads((shader_dir / 'build.json').read_text())
    assert len(build['assets']) == 5, build
    for asset in build['assets']:
        assert generated[asset['file']]['sha256'] == asset['sha256'], asset
    progress(out, 'provenance', binary_sha256=digest(binary), shader_packages=len(build['assets']), source_assets=len(assets))


def scene_checkpoint(out, name, reply):
    scene = reply['scene']
    placed = draws(scene['nodes'])
    with gzip.open(out / (name + '-scene.json.gz'), 'wt', encoding='utf-8') as stream:
        json.dump(reply, stream, separators=(',', ':'), sort_keys=True)
    summary = dict(steps=reply['steps'], camera=scene['camera'], environment=scene['environment'],
                   shadow=scene['shadow'], draws=len(placed), meshes=dict(Counter(str(d['mesh']) for d in placed)),
                   root_nodes=dict(Counter(next(iter(node)) for node in scene['nodes'])),
                   emitters=len(scene['emitters']), first_draws=placed[:3],
                   source_draws=sum(100 <= d['id'] < 100000 for d in placed),
                   field_draws=sum(d['id'] >= 100000 for d in placed))
    write_json(out / (name + '-scene.json'), summary)
    progress(out, 'scene', name=name, steps=reply['steps'], draws=len(placed), camera=scene['camera'])
    return summary


def compare_probe(out, probe, current):
    partial = probe / 'effects-partial.json'
    previous = json.loads(partial.read_text()) if partial.is_file() else {}
    final = probe / 'effects.json'
    successful = json.loads(final.read_text()) if final.is_file() else {}

    def wind_result(report):
        images = report.get('images', {})
        if not all(name in images for name in ('wind-start', 'wind-moving')):
            return 'unavailable'
        return 'passed' if images['wind-start'] != images['wind-moving'] else 'failed'

    early, later = wind_result(previous), wind_result(current)
    early_complete = (successful.get('result') == 'passed' and successful.get('native_log_diagnostics') == 0
                      and not previous.get('failure') and not successful.get('failure')
                      and successful.get('images') == previous.get('images') and wind_result(successful) == 'passed')
    failure = previous.get('failure')
    if not early_complete and failure is None:
        failure = dict(type='IncompleteProbe', message='The early probe has no matching successful final native report')
    result = dict(probe=str(probe), early_wind=early, later_wind=later, early_complete=early_complete, disagree=early != later,
                  early_ready_step=previous.get('ready_step'), later_ready_step=current.get('ready_step'),
                  early_images=previous.get('images', {}), later_images={key: value for key, value in current['images'].items() if key.startswith('wind-')},
                  early_failure=failure, later_failure=current.get('failure'))
    write_json(out / 'probe-comparison.json', result)
    progress(out, 'probe-comparison', early_wind=early, later_wind=later, disagree=early != later)
    return result
