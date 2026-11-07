#!/usr/bin/env python3
"""Build one self-contained native Windows capture package from a frozen source."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

from village_capture import PRESENTMON_SHA256, digest, scene_contract, write_json

ROOT = Path(__file__).resolve().parents[1]
PYTHON_VERSION = '3.12.10'
PRESENTMON_URL = 'https://github.com/GameTechDev/PresentMon/releases/download/v2.6.0/PresentMon-2.6.0-x64.exe'
PYTHON_URL = f'https://www.python.org/ftp/python/{PYTHON_VERSION}/python-{PYTHON_VERSION}-embed-amd64.zip'


def run(command, cwd=ROOT):
    subprocess.run(command, cwd=cwd, check=True)


def package_files(output, presentmon, python_archive, source, builds, toolchain, commands):
    output.mkdir(parents=True, exist_ok=False)
    if digest(presentmon) != PRESENTMON_SHA256:
        raise ValueError('PresentMon executable checksum mismatch')
    for name, path in builds.items():
        shutil.copy2(path, output/name)
    shutil.copytree(ROOT/'examples/village/assets', output/'assets')
    scripts = output/'scripts'
    scripts.mkdir()
    for name in ['village_capture.py', 'village_capture_summary.py', 'village_metal_summary.py', 'village_bench_capture.py']:
        shutil.copy2(ROOT/'scripts'/name, scripts/name)
    for name in ['Capture-Village.ps1', 'Capture-BenchSweeps.ps1', 'Summarize-VillageCapture.ps1', 'machine.example.json']:
        shutil.copy2(ROOT/'scripts/village-capture'/name, output/name)
    shutil.copy2(ROOT/'docs/VILLAGE-CAPTURE.md', output/'README.md')
    credits = output/'credits'
    credits.mkdir()
    for name in ['LICENSE_CC0_Quaternius.txt', 'UPSTREAM-README.md']:
        shutil.copy2(ROOT/'examples/village/source'/name, credits/name)
    tools = output/'tools'
    tools.mkdir()
    shutil.copy2(presentmon, tools/'PresentMon-2.6.0-x64.exe')
    python = tools/'python'
    python.mkdir()
    with zipfile.ZipFile(python_archive) as archive:
        for name in archive.namelist():
            if not (python/name).resolve().is_relative_to(python.resolve()):
                raise ValueError('Python archive contains an outside path')
        archive.extractall(python)
    (python/'python312._pth').write_text('python312.zip\n.\n../../scripts\n')
    licence = tools/'PresentMon-LICENSE.txt'
    urllib.request.urlretrieve('https://raw.githubusercontent.com/GameTechDev/PresentMon/v2.6.0/LICENSE.txt', licence)
    files = {path.relative_to(output).as_posix(): dict(bytes=path.stat().st_size, sha256=digest(path))
             for path in sorted(output.rglob('*')) if path.is_file()}
    manifest = dict(version=1, source_commit=source, scene_contract=scene_contract(ROOT), files=files, toolchain=toolchain, build_commands=commands, builds={
        'village-ordinary.exe': ['release', 'no Spans', 'no D3D timestamps'],
        'village-cpu.exe': ['release', 'ROCCO_SPANS=true'],
        'village-gpu.exe': ['release', 'ROCCO_SPANS=true', 'ROCCO_D3D_GPU_TIMING=true'],
        'bench-draws.exe': ['release', 'ROCCO_SPANS=true'],
        'bench-mixed.exe': ['release', 'ROCCO_SPANS=true']},
        tools=dict(presentmon_url=PRESENTMON_URL, presentmon_sha256=PRESENTMON_SHA256,
                   python_url=PYTHON_URL, python_version=PYTHON_VERSION, python_archive_sha256=digest(python_archive)),
        assets='One adjacent assets directory shared by every executable.',
        acceptance='Native operation checks must pass before sharing the package. Hardware and human acceptance remain open.')
    write_json(output/'manifest.json', manifest)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--odin', default='odin')
    parser.add_argument('--roc', default='roc')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Build the package natively on Windows with the pinned tools and prepared release inputs.')
    if args.output.exists():
        parser.error('output already exists')
    toolchain = {name: subprocess.check_output([program, 'version'], cwd=ROOT, text=True).strip()
                 for name, program in [('odin', args.odin), ('roc', args.roc)]}
    if '902106f' not in toolchain['odin'] or '7d256b9' not in toolchain['roc']:
        raise ValueError('capture package requires the pinned Odin 902106f and Roc 7d256b9')
    commands = []
    def build(command, cwd=ROOT):
        commands.append(dict(command=command, cwd=str(cwd)))
        run(command, cwd)
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    build(['git', 'diff', '--exit-code'])
    build([args.roc, 'scripts/build.roc', '--', 'inputs', '--release'])
    builds = {}
    with tempfile.TemporaryDirectory(prefix='village-capture-package-') as temporary:
        temporary = Path(temporary)
        for name, flags in [('ordinary', []), ('cpu', ['-define:ROCCO_SPANS=true']),
                            ('gpu', ['-define:ROCCO_SPANS=true', '-define:ROCCO_D3D_GPU_TIMING=true'])]:
            build([args.odin, 'build', 'engine', '-build-mode:static', '-out:platform/targets/x64win/host.lib',
                 '-no-crt', '-no-thread-local', '-o:speed', *flags, '-vet', '-strict-style'])
            build([args.roc, 'build', '--no-cache', '--opt=speed', '--target=x64win', '--output=./village.exe', 'main.roc'], ROOT/'examples/village')
            destination = temporary/f'village-{name}.exe'
            shutil.copy2(ROOT/'examples/village/village.exe', destination)
            builds[destination.name] = destination
            if name == 'cpu':
                for game in ['draws', 'mixed']:
                    destination = temporary/f'bench-{game}.exe'
                    build([args.roc, 'build', '--no-cache', '--opt=speed', '--target=x64win',
                         '--output='+str(destination), 'main.roc'], ROOT/'bench'/game)
                    builds[destination.name] = destination
        presentmon = temporary/'PresentMon.exe'
        python_archive = temporary/'python.zip'
        urllib.request.urlretrieve(PRESENTMON_URL, presentmon)
        urllib.request.urlretrieve(PYTHON_URL, python_archive)
        package_files(args.output.resolve(), presentmon, python_archive, source, builds, toolchain, commands)


if __name__ == '__main__':
    main()
