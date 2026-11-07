#!/usr/bin/env python3
"""Check ordered runtime Post packages and production scene depth through the Bridge."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import re
import subprocess
import sys

import bridge
from bridge_check import binary_suffix, check


def frame(path):
    return bridge.png_rgba(Path(path).read_bytes())


def shot(driver, path):
    reply = driver.screenshot(str(path))
    return dict(path=str(path), physical=reply['physical'], logical=reply['logical'])


def run(label, args, out, drive=None, allow_unloaded=False):
    binary = Path('examples/post/post' + binary_suffix()).resolve()
    port = bridge.free_port()
    log_path = out / (label + '.log')
    with log_path.open('w') as log:
        process = subprocess.Popen(shlex.split(os.environ.get('RUN_PREFIX', '')) + [str(binary), *args], cwd=binary.parent,
                                   env=dict(os.environ, ROCCO_BRIDGE=str(port)), stdout=log, stderr=subprocess.STDOUT)
        try:
            with bridge.Bridge.connect(port, wait=60) as driver:
                driver.hello()
                driver.step(1)
                result = shot(driver, out / (label + '.png'))
                if drive:
                    result['drive'] = drive(driver, label)
                driver.quit()
            check(process.wait(timeout=20) == 0, label + ' exits after quit')
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=20)
    text = log_path.read_text(errors='replace')
    check('[sg][error]' not in text and '[sg][panic]' not in text and 'VALIDATION_FAILED' not in text,
          label + ' native graphics validation')
    check('failed GPU' not in text and 'pipeline creation' not in text, label + ' programs and pipelines load')
    check('which did not load' not in text and (allow_unloaded or 'drawing the fallback' not in text), label + ' fixture meshes load')
    result['log'] = str(log_path)
    return result


def rgb(image, x, y):
    w, h, data = frame(image['path'])
    i = (int(y * h) * w + int(x * w)) * 4
    return tuple(data[i:i+3])


def equal(a, b):
    return frame(a['path']) == frame(b['path'])


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/post-check').resolve()
    out.mkdir(parents=True, exist_ok=True)
    probe = Path('build/post-target-check' + binary_suffix()).resolve()
    subprocess.run([os.environ.get('ODIN', 'odin'), 'build', 'scripts/post-target-check', '-strict-style', '-vet', '-out:' + str(probe)], check=True)
    native = subprocess.run(shlex.split(os.environ.get('RUN_PREFIX', '')) + [str(probe)], capture_output=True, text=True, check=True)
    (out / 'targets.log').write_text(native.stdout + native.stderr)
    match = re.search(r'POST_SAMPLES (\[[0-9,]+\])', native.stdout)
    check(match is not None and 'PASS: Post resize' in native.stdout, 'native resize, DPI, allocation, and target checks')
    supported = json.loads(match[1])
    evidence = {'supported_samples': supported, 'unsupported_samples': [n for n in (1, 2, 4, 8) if n not in supported]}
    for count in supported:
        sample = 'off' if count == 1 else 'x' + str(count)
        args = [] if sample == 'off' else ['--' + sample]
        empty = run(sample + '-empty', args + ['--empty'], out)
        disabled = run(sample + '-disabled', args + ['--disabled'], out)
        failed_only = run(sample + '-failed-only', args + ['--failed-only'], out)
        check(equal(empty, disabled) and equal(empty, failed_only), sample + ' empty, disabled, and invalid-only parity')
        chain = run(sample + '-chain', args, out)
        failed = run(sample + '-failed', args + ['--failed'], out)
        reverse = run(sample + '-reverse', args + ['--reverse'], out)
        check(equal(chain, failed), sample + ' one failed effect preserves the surrounding chain')
        a, b = rgb(chain, .9, .1), rgb(reverse, .9, .1)
        check(all(17 <= x-y <= 21 for x, y in zip(a, b)), sample + ' duplicate effects preserve order and instance values')
        check(rgb(empty, .05, .04) == rgb(chain, .05, .04) == (255, 0, 0), sample + ' UI remains outside world effects')
        depth = run(sample + '-depth', args + ['--depth'], out)
        depth_without_blend = run(sample + '-depth-no-blend', args + ['--depth', '--no-blend'], out)
        w, h, pixels = frame(depth['path'])
        _, _, without_blend = frame(depth_without_blend['path'])
        check(pixels[0::4] == without_blend[0::4] and pixels[1::4] == without_blend[1::4], sample + ' Blend geometry never writes scene depth')
        check(rgb(depth, .9, .1)[:2] == (0, 0), sample + ' scene depth clears to zero behind the scene')
        depths = {r for r, g in zip(pixels[0::4], pixels[1::4]) if 126 <= g <= 129 and 0 < r < 255}
        check(len(depths) > 40, sample + ' real geometry produces varying reversed depth')
        selection = run(sample + '-selection', args + ['--selection'], out)
        check(any(r == 255 and g > 0 for r, g in zip(frame(selection['path'])[2][0::4], frame(selection['path'])[2][1::4])), sample + ' selected Groups populate independent coverage and depth')
        hdr = run(sample + '-hdr', args + ['--hdr'], out)
        check(rgb(hdr, .9, .1) != rgb(chain, .9, .1), sample + ' HDR effects run before bloom and tone mapping')
        evidence[sample] = dict(physical=depth['physical'], logical=depth['logical'], depth_values=len(depths),
                                chain_sha256=hashlib.sha256(frame(chain['path'])[2]).hexdigest())
    solid = run('depth-solid', ['--depth', '--solid'], out)
    _, _, masked = frame(out / 'off-depth.png')
    _, _, filled = frame(solid['path'])
    check(sum(a != b for a, b in zip(masked[0::4], filled[0::4])) > 100, 'Surface Mask holes preserve the depth behind foliage')

    def wind(driver, label):
        first = shot(driver, out / (label + '-1.png'))
        driver.step(59)
        second = shot(driver, out / (label + '-60.png'))
        hashes = [hashlib.sha256(frame(image['path'])[2][0::4]).hexdigest() for image in (first, second)]
        check(hashes[0] != hashes[1], 'authored Surface deformation changes production scene depth')
        return hashes

    a = run('depth-wind-a', ['--depth', '--wind'], out, wind)
    b = run('depth-wind-b', ['--depth', '--wind'], out, wind)
    check(a['drive'] == b['drive'], 'fixed Bridge steps reproduce deformed production depth')
    evidence['depth_wind_hashes'] = a['drive']
    small = run('small-low-dpi', ['--small', '--low-dpi', '--depth'], out)
    check(small['physical'] == [480, 360], 'physical inputs follow launch dimensions and DPI')

    selection_checks(out, supported, evidence)
    subprocess.run([sys.executable, str(Path(__file__).with_name('scene_depth_check.py')), str(out / 'scene-depth'), '--diagnostics'], check=True)
    evidence['result'] = 'passed'
    evidence['binary_sha256'] = hashlib.sha256(Path('examples/post/post' + binary_suffix()).read_bytes()).hexdigest()
    (out / 'post-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')


def selection_checks(out, supported, evidence):
    for count in supported:
        sample = 'off' if count == 1 else 'x' + str(count)
        args = [] if count == 1 else ['--' + sample]
        selected = run(sample + '-selected', args + ['--selection', '--wind'], out)
        unoccluded = run(sample + '-selected-unoccluded', args + ['--selection', '--wind', '--no-occluder'], out)
        w, h, pixels = frame(selected['path'])
        _, _, clear = frame(unoccluded['path'])
        check(pixels[0::4] == clear[0::4] and pixels[1::4] == clear[1::4], sample + ' front wall never removes selected coverage or nearest depth')
        hidden = sum(r == 255 and 0 < g < b - 1 for r, g, b in zip(pixels[0::4], pixels[1::4], pixels[2::4]))
        check(hidden > 1000, sample + ' selected geometry remains behind the front wall and floor')
        no_glass = run(sample + '-selected-no-glass', args + ['--selection', '--wind', '--no-blend'], out)
        _, _, absent = frame(no_glass['path'])
        glass = sum(a == 255 and b == 0 for a, b in zip(pixels[0::4], absent[0::4]))
        check(glass > 1000 and pixels[2::4] == absent[2::4], sample + ' alpha-zero double-sided glass covers its full shape and contributes no scene depth')
        deselected = run(sample + '-deselected', args + ['--selection', '--no-selection'], out)
        _, _, none = frame(deselected['path'])
        check(not any(none[y*w*4+4*x+1] for y in range(60, h) for x in range(w)), sample + ' no selected Group clears selected depth')
        boxes = run(sample + '-union', args + ['--selection', '--boxes'], out)
        left = run(sample + '-union-left', args + ['--selection', '--left-only'], out)
        right = run(sample + '-union-right', args + ['--selection', '--right-only'], out)
        both, a, b = (frame(image['path'])[2] for image in (boxes, left, right))
        for channel in (0, 1):
            check(all(u == max(x, y) for u, x, y in zip(both[channel::4], a[channel::4], b[channel::4])), sample + ' multi-Draw union retains combined coverage and nearest selected depth channel ' + str(channel))
        baseline = run(sample + '-outline-baseline', args + ['--empty', '--fixture', '--boxes', '--no-bloom'], out)
        through = run(sample + '-outline-through', args + ['--outline', '--boxes', '--through-wall', '--no-bloom'], out)
        visible = run(sample + '-outline-visible', args + ['--outline', '--boxes', '--no-bloom'], out)
        base, wall, front = (frame(image['path'])[2] for image in (baseline, through, visible))
        check(sum(x != y for x, y in zip(wall, front)) > 100, sample + ' game-authored visible-only and through-wall policies differ')
        check(all(wall[i:i+3] == base[i:i+3] for i in range(60*w*4, len(both), 4) if both[i] == 255), sample + ' one union outline has no internal multi-Draw edge')
        hdr = run(sample + '-outline-bloom', args + ['--outline', '--boxes', '--through-wall'], out)
        check(not equal(hdr, through), sample + ' HDR outline contributes to bloom')
        evidence[sample]['selection'] = dict(hidden_pixels=hidden, glass_pixels=glass, coverage_sha256=hashlib.sha256(pixels[0::4]).hexdigest())

    invisible = run('selection-glass-override-colour', ['--empty', '--fixture', '--override-glass'], out)
    absent = run('selection-glass-absent-colour', ['--empty', '--fixture', '--no-blend'], out)
    check(equal(invisible, absent), 'unlit Blend alpha-zero override preserves colour transparency')
    skin_zero = run('selection-skin-mask-zero', ['--selection', '--mask-zero'], out)
    no_skin = run('selection-skin-absent', ['--selection', '--no-skin'], out)
    check(equal(skin_zero, no_skin), 'skinned Mask alpha-zero override agrees across selection and scene depth')
    skin_colour = run('selection-skin-mask-zero-colour', ['--empty', '--fixture', '--mask-zero'], out)
    no_skin_colour = run('selection-skin-absent-colour', ['--empty', '--fixture', '--no-skin'], out)
    check(equal(skin_colour, no_skin_colour), 'skinned Mask alpha-zero override agrees with colour')

    solid = run('selection-solid', ['--selection', '--solid', '--wind'], out)
    masked = frame(out / 'off-selected.png')[2]
    filled = frame(solid['path'])[2]
    check(sum(a != b for a, b in zip(masked[0::4], filled[0::4])) > 100, 'selected Surface Mask holes preserve coverage holes')

    def animate(driver, label):
        group = next(node['Group'] for node in driver.scene()['scene']['nodes'] if 'Group' in node)
        pip = next(node['Draw'] for node in group['children'] if 'Draw' in node and node['Draw']['id'] == 24)
        check(group['selected'] and pip['pose']['clip'] != 0, 'selected skinned fixture has a loaded animation clip')
        a = shot(driver, out / (label + '-1.png'))
        driver.step(59)
        b = shot(driver, out / (label + '-60.png'))
        first, second = frame(a['path'])[2], frame(b['path'])[2]
        w, h, _ = frame(a['path'])
        for lo, hi, name in ((.55, .72, 'foliage'), (.72, .85, 'skinned')):
            changed = sum(first[(y*w+x)*4] != second[(y*w+x)*4] for y in range(h) for x in range(int(w*lo), int(w*hi)))
            check(changed > 20, 'selected ' + name + ' shares deterministic deformation')
        driver.step(1, tap=['S'])
        empty = shot(driver, out / (label + '-deselected.png'))
        _, _, pixels = frame(empty['path'])
        check(not any(pixels[1::4]), 'live deselection clears the previous selected depth')
        driver.step(1, tap=['U'])
        unloaded = shot(driver, out / (label + '-unloaded.png'))
        return [hashlib.sha256(frame(image['path'])[2][0::4]).hexdigest() for image in (a, b)]

    a = run('selection-animation-a', ['--selection', '--wind'], out, animate, allow_unloaded=True)
    b = run('selection-animation-b', ['--selection', '--wind'], out, animate, allow_unloaded=True)
    check(a['drive'] == b['drive'], 'fixed Bridge steps reproduce selected foliage and skin poses')
    evidence['selection_animation_hashes'] = a['drive']


if __name__ == '__main__':
    main()
