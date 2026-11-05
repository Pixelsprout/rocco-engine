#!/usr/bin/env python3
"""Build and verify the standalone shader authoring game from a candidate SDK."""
import argparse
import contextlib
import hashlib
import json
import math
import os
from pathlib import Path
import platform as host_platform
import shlex
import shutil
import subprocess
import sys
import time

from bridge import Bridge, free_port, png_rgba

GAME = Path(__file__).resolve().parent
COMMANDS = []
CHECKS = []


def sha(data):
    return hashlib.sha256(data).hexdigest()


def check(condition, label):
    if not condition:
        raise AssertionError(label)
    CHECKS.append(label)
    print("PASS: " + label, flush=True)


def execute(command, cwd, log=None, success=True):
    COMMANDS.append(dict(command=[str(part) for part in command], cwd=str(cwd)))
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if log:
        log.write_text(result.stdout)
    if success and result.returncode:
        raise RuntimeError(f"{command} exited {result.returncode}:\n{result.stdout}")
    return result


def wait_for(condition, label, timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(.1)
    raise AssertionError("timeout: " + label)


def pixels(path):
    return png_rgba(path.read_bytes())[2]


def changed(first, second):
    return sum(first[at:at+4] != second[at:at+4] for at in range(0, len(first), 4))


def green(data):
    return sum(g > r * 1.3 and g > b * 1.2 and g > 30 for r, g, b in zip(data[0::4], data[1::4], data[2::4]))


def patch(image, camera, point):
    def dot(a, b):
        return sum(x*y for x, y in zip(a, b))
    def cross(a, b):
        return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
    def unit(value):
        length = math.sqrt(dot(value, value))
        return [x / length for x in value]
    eye = [camera['eye'][key] for key in 'xyz']
    forward = unit([camera['target'][key]-eye[i] for i, key in enumerate('xyz')])
    side = unit(cross(forward, [camera['up'][key] for key in 'xyz']))
    up = cross(side, forward)
    relative = [value - origin for value, origin in zip(point, eye)]
    depth = dot(relative, forward)
    width, height, data = png_rgba(image.read_bytes())
    scale = depth * math.tan(camera['fov_y'] / 2)
    x = int((dot(relative, side) / (scale * width / height) + 1) * width / 2)
    y = int((1 - dot(relative, up) / scale) * height / 2)
    return bytes(data[(row*width+column)*4+channel] for row in range(y-2, y+3)
                 for column in range(x-2, x+3) for channel in range(3))


class Proof:
    def __init__(self, sdk, out):
        self.sdk = sdk
        self.out = out
        self.binary = GAME / ('authoring.exe' if sys.platform == 'win32' else 'authoring.bin')
        self.compiler = [sys.executable, str(sdk / 'shader-tools/build.py'), '--install']

    def build_shaders(self, label):
        return execute(self.compiler, GAME, self.out / (label + '.log'))

    def build_game(self, label):
        target = {'darwin': 'arm64mac', 'linux': 'x64glibc', 'win32': 'x64win'}[sys.platform]
        execute(['roc', 'build', '--target=' + target, '--output=' + self.binary.name, 'main.roc'],
                GAME, self.out / (label + '.log'))

    @contextlib.contextmanager
    def running(self, label, arguments=(), permit_failure=False):
        port = free_port()
        log_path = self.out / (label + '.log')
        command = shlex.split(os.environ.get('RUN_PREFIX', '')) + [str(self.binary), *arguments]
        COMMANDS.append(dict(command=command, cwd=str(GAME), env={'ROCCO_BRIDGE': str(port)}))
        with log_path.open('w') as log:
            process = subprocess.Popen(command, cwd=GAME, env=dict(os.environ, ROCCO_BRIDGE=str(port)),
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                with Bridge.connect(port, wait=60, process=process) as driver:
                    driver.hello()
                    driver.step(1)
                    yield driver, log_path
                    driver.quit()
                check(process.wait(timeout=20) == 0, label + ' exits after Bridge quit')
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=20)
        text = log_path.read_text(errors='replace')
        check(not any(word in text for word in ('[sg][error]', '[sg][panic]', 'VALIDATION_FAILED')),
              label + ' native graphics validation')
        if not permit_failure:
            check(not any(word in text for word in ('failed GPU', 'pipeline creation', 'which did not load', 'drawing the fallback')),
                  label + ' assets and programs load')

    def shot(self, driver, label):
        time.sleep(.35)
        path = self.out / (label + '.png')
        driver.screenshot(str(path))
        check(png_rgba(path.read_bytes())[:2] == (800, 600), label + ' physical dimensions')
        return path

    def completed(self, name, expected=None, different=None):
        try:
            assets = GAME / 'assets/shaders'
            record = json.loads((assets / 'build.json').read_text())
            for asset in record['assets']:
                content = (assets / asset['file']).read_bytes()
                if sha(content) != asset['sha256']:
                    return False
                if asset['asset'] == 'shader/' + name:
                    candidate = content
            return (expected is None or candidate == expected) and (different is None or candidate != different)
        except (OSError, ValueError, KeyError, UnboundLocalError):
            return False

    def await_frame(self, driver, label, predicate):
        path = self.out / (label + '.png')
        def matches():
            driver.screenshot(str(path))
            return predicate(pixels(path))
        wait_for(matches, label + ' rendered generation')
        check(png_rgba(path.read_bytes())[:2] == (800, 600), label + ' physical dimensions')
        return pixels(path)

    def frame(self, label, arguments):
        with self.running(label, arguments) as (driver, _):
            return self.shot(driver, label)

    def wind(self):
        sequences = []
        for replay in ('a', 'b'):
            with self.running('wind-' + replay, ['--empty', '--no-occluder']) as (driver, _):
                hashes = []
                for steps, frame in ((0, 1), (59, 60), (60, 120)):
                    if steps:
                        driver.step(steps)
                    hashes.append(sha(pixels(self.shot(driver, f'wind-{replay}-{frame}'))))
                check(len(set(hashes)) == 3, 'simulation steps change wind and shadow pose ' + replay)
                sequences.append(hashes)
        check(sequences[0] == sequences[1], 'equal Bridge steps reproduce wind and shadows')
        shadow_masks = []
        with self.running('wind-noncasting', ['--empty', '--no-occluder', '--no-shadow']) as (driver, _):
            for steps, frame in ((0, 1), (59, 60), (60, 120)):
                if steps:
                    driver.step(steps)
                no_shadow = pixels(self.shot(driver, f'wind-noncasting-{frame}'))
                casting = pixels(self.out / f'wind-a-{frame}.png')
                shadow_masks.append(bytes(casting[at:at+4] != no_shadow[at:at+4] for at in range(0, len(casting), 4)))
        check(all(sum(mask) > 100 for mask in shadow_masks), 'each wind pose casts a foliage shadow')
        check(len({sha(mask) for mask in shadow_masks}) == 3, 'shadow coverage follows simulation wind steps')
        selected_hashes = []
        for replay in ('a', 'b'):
            with self.running('wind-selection-' + replay, ['--selection', '--no-occluder']) as (driver, _):
                first = pixels(self.shot(driver, 'wind-selection-' + replay + '-1'))[0::4]
                driver.step(59)
                second = pixels(self.shot(driver, 'wind-selection-' + replay + '-60'))[0::4]
                check(sum(a != b for a, b in zip(first, second)) > 100, 'Selection coverage follows game wind ' + replay)
                selected_hashes.append([sha(first), sha(second)])
        check(selected_hashes[0] == selected_hashes[1], 'equal Bridge steps reproduce selected wind coverage')
        return dict(colour_and_shadow=sequences[0], shadow_masks=[sha(mask) for mask in shadow_masks], selection=selected_hashes[0])

    def materials(self):
        arguments = ['--empty', '--no-wind', '--no-occluder']
        with self.running('materials', arguments, permit_failure=True) as (driver, _):
            base = self.shot(driver, 'material-inherited')
            scene = driver.scene()['scene']
            group = next(node['Group'] for node in scene['nodes'] if 'Group' in node)
            check(group['selected'] and [node['Draw']['id'] for node in group['children']] == [10, 11],
                  'one selected Group contains the tree and marker Draws')
            check(group['children'][0]['Draw']['mesh'] != 0, 'two-slot tree Mesh loads')
            check(green(pixels(base)) > 1000, 'leaf helper preserves imported green material')
            driver.step(1, tap=['C'])
            red = self.shot(driver, 'material-red')
            check(green(pixels(red)) < green(pixels(base))/4, 'typed leaf parameter changes named Leaves slot')
            check(patch(base, scene['camera'], (0, .4, .13)) == patch(red, scene['camera'], (0, .4, .13)),
                  'Bark slot keeps its imported material')
            driver.step(1, tap=['C'])
            check(pixels(base) == pixels(self.shot(driver, 'material-restored')), 'equal material values restore the frame')
            driver.step(1, tap=['N'])
            noncasting = self.shot(driver, 'material-noncasting')
            check(green(pixels(noncasting)) == green(pixels(base)), 'non-casting foliage keeps colour coverage')
            check(changed(pixels(base), pixels(noncasting)) > 100, 'per-Draw casting removes the foliage shadow')
            driver.step(1, tap=['N'])
            driver.step(1, tap=['U'])
            unloaded = self.shot(driver, 'pack-unloaded')
            check(green(pixels(unloaded)) == 0, 'Shader Pack unload omits the leaf part')
            check(patch(base, scene['camera'], (0, .4, .13)) == patch(unloaded, scene['camera'], (0, .4, .13)),
                  'Shader Pack unload preserves the separate Mesh Pack and Bark slot')
            driver.step(1, tap=['U'])
            check(pixels(base) == pixels(self.shot(driver, 'pack-restored')), 'Shader Pack reload restores the frame')
        solid = self.frame('material-solid', arguments + ['--solid'])
        check(changed(pixels(base), pixels(solid)) > 100, 'imported alpha texture supplies colour and shadow holes')
        cast = self.frame('material-solid-noncasting', arguments + ['--solid', '--no-shadow'])
        masked_shadow = changed(pixels(base), pixels(noncasting))
        solid_shadow = changed(pixels(solid), pixels(cast))
        check(solid_shadow > masked_shadow + 100, 'solid foliage shadow covers imported cutout holes')
        return dict(cutout_shadow_pixels=masked_shadow, solid_shadow_pixels=solid_shadow)

    def selection(self):
        selected = self.frame('selection-inputs', ['--selection', '--no-wind'])
        clear = self.frame('selection-no-wall', ['--selection', '--no-wind', '--no-occluder'])
        first, second = pixels(selected), pixels(clear)
        check(first[0::4] == second[0::4] and first[1::4] == second[1::4],
              'occluder preserves identical selected coverage and nearest selected depth')
        hidden = sum(r == 255 and 0 < g < b - 1 for r, g, b in zip(first[0::4], first[1::4], first[2::4]))
        check(hidden > 500, 'selected Group supplies hidden coverage and depth behind the wall')
        solid = self.frame('selection-solid', ['--selection', '--no-wind', '--solid'])
        check(sum(a != b for a, b in zip(first[0::4], pixels(solid)[0::4])) > 100,
              'Selection preserves imported alpha texture holes')
        none = self.frame('selection-none', ['--selection', '--no-wind', '--no-selection'])
        check(not any(pixels(none)[0::4]) and not any(pixels(none)[1::4]), 'deselected Group clears Selection inputs')
        with self.running('outline-policies', ['--no-wind']) as (driver, _):
            visible = self.shot(driver, 'outline-visible')
            before = driver.scene()['scene']
            driver.step(1, tap=['V'])
            through = self.shot(driver, 'outline-through')
            after = driver.scene()['scene']
            check(before['nodes'] == after['nodes'], 'outline policies use the same selected Group and scene')
            check(changed(pixels(visible), pixels(through)) > 50, 'game Post shader chooses visible-only and through-wall outlines')
            driver.step(1, tap=['V'])
            check(pixels(visible) == pixels(self.shot(driver, 'outline-visible-restored')), 'outline policy toggle restores the frame')
        return dict(hidden_pixels=hidden, coverage_sha256=sha(first[0::4]), selected_depth_sha256=sha(first[1::4]))

    def first_load(self):
        assets = GAME / 'assets/shaders'
        paths = [assets / 'Foliage.shaderpack', assets / 'Outline.shaderpack']
        valid = {path: path.read_bytes() for path in paths}
        try:
            for path, content in valid.items():
                damaged = bytearray(content)
                damaged[10:12] = (2).to_bytes(2, 'little')
                path.write_bytes(damaged)
            with self.running('first-load-empty', ['--no-wind', '--empty'], permit_failure=True) as (empty_driver, _):
                no_effect = pixels(self.shot(empty_driver, 'first-load-empty'))
            with self.running('first-load-failure', ['--no-wind'], permit_failure=True) as (driver, log):
                failed = pixels(self.shot(driver, 'first-load-invalid'))
                check(green(failed) == 0, 'invalid first Surface omits affected foliage')
                check(no_effect == failed, 'invalid first Post skips the effect and preserves scene colour')
                check('incompatible shader contract' in log.read_text(), 'invalid first packages report contract failure')
                check(not any(r > 200 and b > 200 and g < 30 for r, g, b in zip(failed[0::4], failed[1::4], failed[2::4])),
                      'invalid first shaders never select a fallback material')
                self.build_shaders('first-load-recovery-build')
                restored = self.await_frame(driver, 'first-load-recovered', lambda frame: green(frame) > 1000)
                check(green(restored) > 1000 and restored != failed, 'retained Pack requests recover invalid first packages')
        finally:
            for path, content in valid.items():
                path.write_bytes(content)

    def reload(self):
        assets = GAME / 'assets/shaders'
        package = assets / 'Foliage.shaderpack'
        record = assets / 'build.json'
        wind = GAME / 'wind.glsl'
        outline = GAME / 'outline.glsl'
        declarations = GAME / 'shaders.json'
        originals = {path: path.read_bytes() for path in (wind, outline, declarations)}
        self.build_shaders('reload-initial-build')
        original_package = package.read_bytes()
        original_record = record.read_bytes()
        baseline = None
        try:
            with self.running('reload', ['--no-wind'], permit_failure=True) as (driver, log):
                baseline = pixels(self.shot(driver, 'reload-initial'))
                watch_log = self.out / 'watch.log'
                command = self.compiler + ['--watch']
                COMMANDS.append(dict(command=command, cwd=str(GAME)))
                with watch_log.open('w') as output:
                    watcher = subprocess.Popen(command, cwd=GAME, stdout=output, stderr=subprocess.STDOUT)
                    try:
                        wait_for(lambda: 'Built ' in watch_log.read_text(), 'watcher starts')
                        wind.write_text(originals[wind].decode().replace('vertex.position.x +=', 'vertex.position.x += 0.25 * weight +'))
                        wait_for(lambda: self.completed('Foliage', different=original_package), 'completed compatible Surface build')
                        modified = self.await_frame(driver, 'reload-surface', lambda frame: frame != baseline)
                        check(modified != baseline, 'compatible Surface edit reloads without restarting')
                        valid_outputs = {path: path.read_bytes() for path in assets.rglob('*') if path.is_file()}
                        wind.write_text(wind.read_text().replace('sin(', 'undefined_reload(', 1))
                        wait_for(lambda: 'undefined_reload' in watch_log.read_text(), 'compiler diagnostic')
                        invalid = execute(self.compiler, GAME, self.out / 'invalid-source-build.log', success=False)
                        check(invalid.returncode != 0, 'ordinary asset build rejects invalid shader source')
                        check(all(path.read_bytes() == content for path, content in valid_outputs.items()),
                              'invalid shader source preserves all published output files')
                        check(modified == pixels(self.shot(driver, 'reload-source-failed')), 'failed source reload keeps the valid frame')
                        wind.write_bytes(originals[wind])
                        wait_for(lambda: self.completed('Foliage', expected=original_package) and record.read_bytes() == original_record, 'completed corrected Surface build')
                        check(baseline == self.await_frame(driver, 'reload-source-recovered', lambda frame: frame == baseline), 'source correction restores the frame without restart')
                        outline_package = assets / 'Outline.shaderpack'
                        outline_bytes = outline_package.read_bytes()
                        outline.write_text(originals[outline].decode().replace('param_outline()', 'vec4(0.0, 2.0, 4.0, 1.0)'))
                        wait_for(lambda: self.completed('Outline', different=outline_bytes), 'completed compatible Post build')
                        check(baseline != self.await_frame(driver, 'reload-post', lambda frame: frame != baseline), 'compatible game Post edit reloads live')
                        outline.write_bytes(originals[outline])
                        wait_for(lambda: self.completed('Outline', expected=outline_bytes), 'completed corrected Post build')
                        check(baseline == self.await_frame(driver, 'reload-post-recovered', lambda frame: frame == baseline), 'Post source correction restores the frame')
                    finally:
                        watcher.terminate()
                        watcher.wait(timeout=20)
                good_record = record.read_bytes()
                damaged = bytearray(original_package)
                damaged[10:12] = (2).to_bytes(2, 'little')
                package.write_bytes(damaged)
                manifest = json.loads(good_record)
                next(asset for asset in manifest['assets'] if asset['asset'] == 'shader/Foliage')['sha256'] = sha(damaged)
                record.write_text(json.dumps(manifest))
                wait_for(lambda: 'incompatible shader contract' in log.read_text(), 'package rejection diagnostic')
                check(baseline == pixels(self.shot(driver, 'reload-package-failed')), 'invalid asset contract keeps the valid rendered generation')
                package.write_bytes(original_package)
                record.write_bytes(good_record)
                check(baseline == pixels(self.shot(driver, 'reload-package-recovered')), 'valid package correction recovers without restart')
                declaration = json.loads(originals[declarations])
                declaration['shaders'][0]['max_displacement'] = .5
                declarations.write_text(json.dumps(declaration, indent=2) + '\n')
                self.build_shaders('interface-changed-build')
                check(package.read_bytes() != original_package, 'interface edit produces a distinct package')
                wait_for(lambda: 'rebuild the game and restart' in log.read_text(), 'interface restart diagnostic')
                check(baseline == pixels(self.shot(driver, 'reload-interface-rejected')), 'interface change retains the old frame before restart')
            self.build_game('interface-rebuild-game')
            with self.running('interface-restarted', ['--no-wind']) as (driver, log):
                check(baseline == pixels(self.shot(driver, 'interface-restarted')), 'rebuilt game accepts the changed interface after restart')
                check('rebuild the game and restart' not in log.read_text(), 'restarted game defines a new interface baseline')
        finally:
            for path, content in originals.items():
                path.write_bytes(content)
            self.build_shaders('restore-build')


def published_provenance(candidate, provenance):
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        return False
    artifact_id = provenance['artifact_id'] or ''
    artifact_digest = provenance['artifact_sha256'] or ''
    expected_url = (f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{candidate['repository']}"
                    f"/actions/runs/{candidate['run_id']}/artifacts/{artifact_id}")
    check(artifact_id.isdigit() and provenance['artifact_url'] == expected_url,
          'published artifact URL and ID match this candidate run')
    check(len(artifact_digest) == 64 and all(char in '0123456789abcdef' for char in artifact_digest),
          'published artifact has its CI SHA-256 digest')
    check(candidate['run_id'] == os.environ.get('GITHUB_RUN_ID') and
          candidate['repository'] == os.environ.get('GITHUB_REPOSITORY') and
          candidate['commit'] == os.environ.get('CANDIDATE_COMMIT'),
          'candidate provenance matches the clean CI proof job')
    return True


def verify_sdk(directory, out):
    hashes = {}
    for line in (directory / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split('  ', 1)
        check(Path(name).name == name, 'SDK checksum filename stays within artifact')
        check(sha((directory / name).read_bytes()) == digest, 'candidate checksum ' + name)
        hashes[name] = digest
    candidate = json.loads((directory / 'candidate.json').read_text())
    expected = os.environ.get('CANDIDATE_COMMIT')
    check(not expected or candidate['commit'] == expected, 'candidate commit matches CI builder commit')
    check(shutil.which('odin') is None, 'Odin is absent from PATH before the external build')
    check(not any((parent / '.git').exists() for parent in (GAME, *GAME.parents)), 'external game has no engine checkout')
    check(not any(GAME.rglob('*.odin')), 'self-contained fixture has no Odin source')
    check(all(Path(filename).name == filename and filename in hashes for filename in candidate['bundles'].values()),
          'every SDK archive has a verified checksum')
    sdk_root = out / 'external-sdk'
    sdk_root.mkdir()
    bundles = {}
    for name, filename in candidate['bundles'].items():
        check(filename.startswith(name + '-') and filename.endswith('.tar.zst'), name + ' archive has the release filename form')
        bare_name = filename.removeprefix(name + '-')
        local_archive = sdk_root / bare_name
        shutil.copyfile(directory / filename, local_archive)
        COMMANDS.append(dict(operation='copy verified archive for roc unbundle', source=str(directory / filename),
                             destination=str(local_archive), sha256=hashes[filename]))
        execute(['roc', 'unbundle', str(local_archive)], sdk_root, out / ('unbundle-' + name + '.log'))
        bundles[name] = sdk_root / bare_name.removesuffix('.tar.zst')
        check((bundles[name] / 'main.roc').is_file(), name + ' unbundles in the explicit clean working directory')
    check(not any(sdk_root.rglob('*.odin')), 'extracted SDK has no Odin source')
    check(not any(sdk_root.rglob('.git')), 'extracted SDK has no engine checkout')
    header = (GAME / 'main.roc').read_text().replace('../../platform/main.roc', os.path.relpath(bundles['platform'] / 'main.roc', GAME).replace(os.sep, '/'))
    header = header.replace('../../packages/mesh/main.roc', os.path.relpath(bundles['mesh'] / 'main.roc', GAME).replace(os.sep, '/'))
    (GAME / 'main.roc').write_text(header)
    provenance = dict(candidate=candidate, archive_sha256=hashes, artifact_url=os.environ.get('CANDIDATE_ARTIFACT_URL'),
                      artifact_id=os.environ.get('CANDIDATE_ARTIFACT_ID'),
                      artifact_sha256=os.environ.get('CANDIDATE_ARTIFACT_SHA256'),
                      sha256sums_sha256=sha((directory / 'SHA256SUMS').read_bytes()))
    provenance['published_source_verified'] = published_provenance(candidate, provenance)
    return bundles['platform'], provenance


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--sdk', type=Path, help='downloaded checksummed candidate artifact')
    source.add_argument('--platform', type=Path, help='local preparation only; does not prove published artifacts')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    evidence = dict(result='failed', host=sys.platform, backend={'darwin': 'Metal', 'linux': 'GL 4.3', 'win32': 'D3D11'}[sys.platform],
                    system=host_platform.platform(), mode='local SDK replay' if args.sdk else 'local preparation',
                    published_artifact_gate='not exercised',
                    game=str(GAME), engine_checkout=False if args.sdk else 'local preparation', odin=shutil.which('odin'),
                    python=dict(version=sys.version, executable=sys.executable), LIB=os.environ.get('LIB'))
    try:
        sdk, provenance = verify_sdk(args.sdk.resolve(), out) if args.sdk else (args.platform.resolve(), {})
        evidence.update(provenance)
        if provenance.get('published_source_verified'):
            evidence['mode'] = 'published candidate in clean CI'
            evidence['published_artifact_gate'] = 'pending native proof'
        if args.sdk and sys.platform == 'win32':
            check(not os.environ.get('LIB'), 'Windows external link has no LIB environment path')
        roc = execute(['roc', 'version'], GAME)
        archive = os.environ.get('ROC_ARCHIVE_PATH')
        evidence['roc'] = dict(version=roc.stdout.strip(), executable=shutil.which('roc'),
                               executable_sha256=sha(Path(shutil.which('roc')).read_bytes()),
                               archive_url=os.environ.get('ROC_ARCHIVE_URL'),
                               archive_sha256=sha(Path(archive).read_bytes()) if archive else None)
        pins = json.loads((sdk / 'shader-tools/contract-v1/compiler.json').read_text())
        proof = Proof(sdk, out)
        proof.build_shaders('build-shaders')
        suffix = '.exe' if sys.platform == 'win32' else ''
        compiler = Path(os.environ.get('ROCCO_SHDC') or shutil.which('sokol-shdc') or
                        Path.home() / '.cache/rocco/shader-tools' / pins['commit'] / ('sokol-shdc' + suffix)).resolve()
        target = 'win32' if sys.platform == 'win32' else ('osx_arm64' if host_platform.machine().lower() in ('arm64', 'aarch64') else 'osx') if sys.platform == 'darwin' else 'linux'
        digest = sha(compiler.read_bytes())
        check(digest == pins['sha256'][target], 'installed shader compiler matches SDK checksum pin')
        evidence['shader_compiler'] = dict(commit=pins['commit'], executable=str(compiler), sha256=digest,
            url=f"https://raw.githubusercontent.com/floooh/sokol-tools-bin/{pins['commit']}/bin/{target}/sokol-shdc{suffix}")
        record = json.loads((GAME / 'assets/shaders/build.json').read_text())
        check(record['meshes'] == [{'module': 'Tree', 'asset': 'tree', 'materials': [
            {'identifier': 'bark', 'name': 'Bark', 'source_material': 0},
            {'identifier': 'leaves', 'name': 'Leaves', 'source_material': 1}]}],
              'SDK generates typed Bark and Leaves slot helpers')
        evidence['build'] = record
        proof.build_game('build-game')
        evidence['binary_sha256'] = sha(proof.binary.read_bytes())
        evidence['wind_hashes'] = proof.wind()
        evidence['materials'] = proof.materials()
        evidence['selection'] = proof.selection()
        proof.first_load()
        proof.reload()
        if args.sdk:
            check(shutil.which('odin') is None, 'Odin remains absent after compilation and native proof')
        evidence['result'] = 'passed'
        if provenance.get('published_source_verified'):
            evidence['published_artifact_gate'] = 'passed'
    except Exception as error:
        evidence['failure'] = dict(type=type(error).__name__, message=str(error))
        if evidence.get('published_source_verified'):
            evidence['published_artifact_gate'] = 'failed'
        raise
    finally:
        evidence['checks'] = CHECKS
        evidence['commands'] = COMMANDS
        (out / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
