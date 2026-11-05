#!/usr/bin/env python3
"""Check native particle replay, bursts, image unload, and draining sources."""

import json
import sys
import tempfile
from pathlib import Path

import bridge
from bridge_check import binary_suffix, check, run_game


def drive(b, out):
    b.hello()
    initial = Path(out).with_name(Path(out).stem + '-initial.png')
    b.screenshot(str(initial))
    _, _, pixels = bridge.png_rgba(initial.read_bytes())
    check(sum(pixels[i] > 180 and pixels[i] > pixels[i+2] * 2 for i in range(0, len(pixels), 4)) > 10, 'init Burst resolves the initial Scene source')
    b.step(240)
    scene = b.scene()['scene']
    check(len(scene['emitters']) == 3, 'smoke, dust, and sparks are declared')
    check(scene['emitters'][1]['image'] != 0, 'the dust Pack image loaded')
    reply = b.step(1, tap=['B'])
    check({'Burst': {'emitter': 3, 'count': 180}} in reply['commands'], 'the burst reaches the host and Bridge')
    b.step(24)
    image = Path(out)
    b.screenshot(str(image))
    again = image.with_name(image.stem + '-paused.png')
    b.screenshot(str(again))
    check(image.read_bytes() == again.read_bytes(), 'paused frames do not advance particles')
    b.step(1, tap=['U'])
    b.screenshot(str(image.with_name(image.stem + '-unloaded.png')))
    b.step(1, tap=['L'])
    check(b.scene()['scene']['emitters'][1]['image'] != scene['emitters'][1]['image'], 'reload uses a new image generation')
    b.step(1, tap=['R'])
    check(b.scene()['scene']['emitters'] == [], 'removal stops all sources')
    b.step(600)
    drained = image.with_name(image.stem + '-drained.png')
    b.screenshot(str(drained))
    check(image.read_bytes() != drained.read_bytes(), 'live particles change the frame')
    b.step(120)
    empty = image.with_name(image.stem + '-empty.png')
    b.screenshot(str(empty))
    check(drained.read_bytes() == empty.read_bytes(), 'removed sources drain completely')
    b.quit()


def main(argv):
    out = Path(argv[0] if argv else 'build/bridge-check/particles').resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for run in range(2):
            run_game('particles', drive, str(out / f'run-{run}.png'), tmp, binary_suffix())
            log = Path(tmp, 'particles.log').read_text(errors='replace')
            (out / f'run-{run}.log').write_text(log)
            check('[sg][error]' not in log and '[sg][panic]' not in log, 'the native graphics log has no errors')
            check('LEAK ' not in log and 'BAD Free' not in log, 'the native allocator reports no leaks or invalid frees')
            check(log.count('Particle Image id') == 1, 'the unloaded image logs once while particles drain')
    check((out / 'run-0.png').read_bytes() == (out / 'run-1.png').read_bytes(), 'two Bridge runs reproduce the same particle pixels')
    (out / 'evidence.json').write_text(json.dumps({'replay_identical': True, 'runs': 2, 'steps_before_capture': 265, 'checks': ['smoke', 'dust image', 'additive burst', 'paused frame', 'asset unload', 'asset reload', 'removal', 'drain']}, indent=2) + '\n')
    print('PASS: native particle replay check')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
