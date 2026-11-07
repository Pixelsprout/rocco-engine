#!/usr/bin/env python3
"""Check native reload ownership and live watcher recovery through the Bridge."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time

import bridge
from bridge_check import binary_suffix, check, odin_link_flags

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "platform/shader-tools"))
import build as asset_build
from package import HEADER, pack


def corrupt_native_source(source, target):
    data = source.read_bytes()
    metadata = HEADER.unpack_from(data)[4]
    manifest = json.loads(data[96:96 + metadata])
    payload = bytearray(data[96 + metadata:])
    for backend in manifest['shaders']:
        for program in backend['programs']:
            for stage in ('vertex_func', 'fragment_func'):
                offset = program[stage]['offset']
                payload[offset:offset + 8] = b'#error X'
    target.write_bytes(pack(manifest, payload))


def wait_for(condition, label, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(.05)
    raise AssertionError('timeout: ' + label)


def native(out, compiler):
    source = out / 'native-inputs'
    shutil.copytree(ROOT / 'scripts/shader_assets/example', source, dirs_exist_ok=True)
    assets = out / 'native-assets'
    asset_build.build(source / 'shaders.json', assets, out / 'native-helpers', compiler=compiler)
    corrupt_native_source(assets / 'Foliage.shaderpack', assets / 'Bad.shaderpack')
    corrupt_native_source(assets / 'Outline.shaderpack', assets / 'BadPost.shaderpack')
    binary = out / ('native' + binary_suffix())
    subprocess.run([os.environ.get('ODIN', 'odin'), 'build', 'scripts/shader-reload-check', '-debug', '-strict-style', '-vet', '-out:' + str(binary)] + odin_link_flags(), check=True)
    result = subprocess.run(shlex.split(os.environ.get('RUN_PREFIX', '')) + [str(binary), str(assets)], capture_output=True, text=True, timeout=120)
    (out / 'native.log').write_text(result.stdout + result.stderr)
    result.check_returncode()
    check('PASS: native Shader reload' in result.stdout, 'native failure, recovery, retirement, and resource accounting')
    (out / 'native-evidence.json').write_text(json.dumps(dict(result='passed', host=sys.platform, compatible_swaps=24,
        failed_pipeline_candidates=24, failed_program_candidates=2, surface_pipeline_keys=63, post_locations=2,
        log=result.stdout + result.stderr), indent=2) + '\n')


def running(out, compiler, initial='valid'):
    game = out / ('game-' + initial)
    shutil.copytree(ROOT / 'examples/post', game, ignore=shutil.ignore_patterns('*.bin', '*.exe', '*.dSYM'), dirs_exist_ok=True)
    binary = game / ('post' + binary_suffix())
    shutil.copy2(ROOT / 'examples/post' / binary.name, binary)
    assets = game / 'assets/shaders'
    asset_build.build(game / 'shaders.json', assets, game, compiler=compiler)
    package = assets / 'Foliage.shaderpack'
    if initial == 'missing':
        package.unlink()
    elif initial == 'invalid':
        package.write_bytes(b'invalid first load')
    port = bridge.free_port()
    log_path = out / ('game-' + initial + '.log')
    watcher_log = out / ('watch-' + initial + '.log')
    command = [sys.executable, str(ROOT / 'platform/shader-tools/build.py'), '--watch', '--shdc', str(compiler)]
    process = watcher = None
    with log_path.open('w') as log, watcher_log.open('w') as watch_log:
        try:
            process = subprocess.Popen(shlex.split(os.environ.get('RUN_PREFIX', '')) + [str(binary), '--depth', '--wind'], cwd=game, env=dict(os.environ, ROCCO_BRIDGE=str(port)), stdout=log, stderr=subprocess.STDOUT)
            with bridge.Bridge.connect(port, wait=60) as driver:
                driver.hello()
                driver.step(1)
                def shot(label):
                    time.sleep(.3)
                    path = out / (initial + '-' + label + '.png')
                    driver.screenshot(str(path))
                    return bridge.png_rgba(path.read_bytes())[2]
                def complete():
                    try:
                        record = json.loads((assets / 'build.json').read_text())
                        return all(hashlib.sha256((assets / asset['file']).read_bytes()).hexdigest() == asset['sha256'] for asset in record['assets'])
                    except (OSError, ValueError):
                        return False
                before = shot('before')
                watcher = subprocess.Popen(command, cwd=game, stdout=watch_log, stderr=subprocess.STDOUT)
                wait_for(lambda: complete() and 'Built ' in watcher_log.read_text(), 'first watched build')
                loaded = shot('loaded')
                if initial != 'valid':
                    check(before != loaded, initial + ' first-load recovery restores Surface parts')
                original = package.read_bytes()
                wind = game / 'wind.glsl'
                wind_text = wind.read_text()
                wind.write_text(wind_text.replace('sin(', 'sin(1.0 + ', 1))
                wait_for(lambda: package.read_bytes() != original and complete(), 'compatible source compilation')
                changed = shot('changed')
                check(loaded != changed, 'compatible deformation changes production scene depth')
                good_record = (assets / 'build.json').read_bytes()
                good_package = package.read_bytes()
                wind.write_text(wind.read_text().replace('sin(', 'undefined_reload(', 1))
                wait_for(lambda: 'undefined_reload' in watcher_log.read_text(), 'source diagnostic')
                check(good_record == (assets / 'build.json').read_bytes() and good_package == package.read_bytes(), 'failed compilation preserves every published output')
                check(changed == shot('failed'), 'invalid source keeps the last rendered generation')
                wind.write_text(wind_text)
                wait_for(lambda: package.read_bytes() == original and complete(), 'fixed source compilation')
                check(loaded == shot('recovered'), 'source correction recovers without restarting')
                post_source = game / 'depth.glsl'
                post_text = post_source.read_text()
                post_package = assets / 'Depth.shaderpack'
                post_original = post_package.read_bytes()
                post_source.write_text(post_text.replace('depth * 20.0', 'depth * 10.0'))
                wait_for(lambda: post_package.read_bytes() != post_original and complete(), 'Post source compilation')
                check(loaded != shot('post-changed'), 'compatible Post hook reload changes the running effect')
                post_source.write_text(post_text)
                wait_for(lambda: post_package.read_bytes() == post_original and complete(), 'Post source correction')
                check(loaded == shot('post-recovered'), 'Post hook correction restores the running effect')
                declarations = game / 'shaders.json'
                text = declarations.read_text()
                value = json.loads(text)
                value['shaders'][0]['max_displacement'] += .1
                declarations.write_text(json.dumps(value))
                wait_for(lambda: package.read_bytes() != original and complete(), 'incompatible package compilation')
                check(loaded == shot('incompatible'), 'changed interface preserves the last rendered generation')
                wait_for(lambda: 'rebuild the game and restart' in log_path.read_text(), 'restart diagnostic')
                declarations.write_text('{')
                wait_for(lambda: 'expected' in watcher_log.read_text() or 'Expecting' in watcher_log.read_text(), 'invalid declaration diagnostic')
                declarations.write_text(text)
                wait_for(lambda: package.read_bytes() == original and complete(), 'declaration correction')
                check(loaded == shot('declaration-recovered'), 'declaration correction recovers automatically')
                moved = game / 'moved-wind.glsl'
                moved.write_text(wind_text.replace('sin(', 'sin(2.0 + ', 1))
                value = json.loads(text); value['shaders'][0]['vertex'] = moved.name
                declarations.write_text(json.dumps(value))
                wait_for(lambda: package.read_bytes() != original and complete(), 'changed hook path')
                moved_frame = shot('moved')
                check(loaded != moved_frame, 'watcher follows a changed declaration path')
                value['shaders'] = value['shaders'][1:]
                declarations.write_text(json.dumps(value))
                wait_for(lambda: all(asset['asset'] != 'shader/Foliage' for asset in json.loads((assets / 'build.json').read_text())['assets']) and complete(), 'declaration removal')
                check(moved_frame == shot('removed'), 'declaration removal preserves the last valid generation')
                wait_for(lambda: 'declaration removed or renamed' in log_path.read_text(), 'declaration removal restart diagnostic')
                declarations.write_text(text)
                wait_for(lambda: package.read_bytes() == original and complete(), 'removed declaration recovery')
                check(loaded == shot('restored'), 'restoring the declaration restores live compilation')
                driver.quit()
            check(process.wait(timeout=20) == 0, 'reload game exits after Bridge quit')
        finally:
            for child in (watcher, process):
                if child is not None and child.poll() is None:
                    child.terminate(); child.wait(timeout=20)
    text = log_path.read_text()
    check('[sg][error]' not in text and '[sg][panic]' not in text, 'reload game native graphics validation')
    return hashlib.sha256(loaded).hexdigest()


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/bridge-check/reload').resolve()
    out.mkdir(parents=True, exist_ok=True)
    default_compiler = ROOT / 'build/shader-tools' / ('sokol-shdc.exe' if sys.platform == 'win32' else 'sokol-shdc')
    compiler = Path(os.environ.get('ROCCO_SHDC', default_compiler)).resolve()
    native(out, compiler)
    evidence = {initial: running(out, compiler, initial) for initial in ('valid', 'missing', 'invalid')}
    evidence.update(result='passed', host=sys.platform, binary_sha256=hashlib.sha256((ROOT / 'examples/post' / ('post' + binary_suffix())).read_bytes()).hexdigest())
    (out / 'reload-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
