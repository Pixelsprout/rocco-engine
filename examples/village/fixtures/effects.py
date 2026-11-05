#!/usr/bin/env python3
"""Capture effects with fixed Bridge inputs, seeds, and simulation steps."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / 'examples/village'
sys.path.insert(0, str(ROOT / 'scripts'))
from bridge import Bridge, png_rgba


def capture(out, name, switches, seed, view, steps, selected, retina):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, ROCCO_BRIDGE=str(port), ROCCO_SEED=str(seed), ROCCO_EXIT_AFTER_FRAMES='30000')
    suffix = '.exe' if os.name == 'nt' else '_linux.bin' if sys.platform.startswith('linux') else '.bin'
    command = [str(GAME / ('village' + suffix))]
    if retina:
        command.append('--retina-1080')
    with (out / (name + '.log')).open('w') as log:
        process = subprocess.Popen(command, cwd=GAME, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            with Bridge.connect(port, wait=60) as bridge:
                bridge.hello()
                initial = bridge.scene()['scene']
                assert not initial['nodes'] and initial['ui']
                for ready_step in range(1, 1025):
                    bridge.step(1)
                    scene = bridge.scene()['scene']
                    if scene['nodes']:
                        break
                    assert scene['ui']
                else:
                    raise AssertionError('The village did not finish loading')
                for switch in switches:
                    bridge.tell('effects', switch)
                if 'ui' in name:
                    bridge.tell('effects', 'controls')
                if selected:
                    bridge.tell('view', 'walk')
                    bridge.step(2)
                    bridge.step(424, held=['W', 'LeftShift'])
                    bridge.step(600, held=['D', 'LeftShift'])
                    bridge.step(1, mouse=[392.6991, 0])
                    bridge.step(1, tap=['Enter'])
                    selection = bridge.scene()['scene']
                    group = next(n['Group'] for n in selection['nodes'] if 'Group' in n and n['Group']['id'] == 20)
                    assert group['selected'], group
                    assert len(group['children']) > 1
                    assert all(n['Draw']['tint'] == {'r': 1, 'g': 1, 'b': 1} for n in group['children'])
                if view == 'occluded':
                    bridge.tell('view', 'walk')
                    bridge.step(2)
                    bridge.tell('view', 'free')
                    bridge.step(2)
                    bridge.step(340, held=['D'])
                    bridge.step(560, held=['W'])
                    bridge.step(26, held=['Space'])
                    bridge.step(1, mouse=[-641.3, 0])
                else:
                    bridge.tell('view', view)
                bridge.step(steps)
                scene = bridge.scene()['scene']
                (out / (name + '-scene.json')).write_text(json.dumps(scene, indent=2) + '\n')
                image = out / (name + '.png')
                result = bridge.screenshot(str(image))
                assert result['physical'] == [1920, 1080], result
                bridge.quit()
            assert process.wait(timeout=30) == 0
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=30)
    return dict(name=name, seed=seed, switches=switches, view=view, selected=20 if selected else 0, ready_step=ready_step, steps_after_view=steps, physical=result['physical'], camera=scene['camera'], emitters=scene['emitters'],  png_sha256=hashlib.sha256(image.read_bytes()).hexdigest())


def pixels(path):
    return png_rgba(path.read_bytes())[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out', type=Path)
    parser.add_argument('--retina-1080', action='store_true')
    parser.add_argument('--steps', type=int, default=1800)
    parser.add_argument('--cases', nargs='+')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    cases = [
        ('hero-all', [], 0, 'hero', False),
        ('hero-repeat', [], 0, 'hero', False),
        ('hero-seed7', [], 7, 'hero', False),
        ('hero-none', ['none'], 0, 'hero', False),
        ('hero-ui', [], 0, 'hero', False),
        ('hero-ui-no-colour', ['colour'], 0, 'hero', False),
        ('hero-no-smoke', ['smoke'], 0, 'hero', False),
        ('hero-no-dust', ['dust'], 0, 'hero', False),
        ('hero-no-colour', ['colour'], 0, 'hero', False),
        ('square-all', [], 0, 'square', False),
        ('outline-visible', ['pulse', 'visible'], 0, 'square', True),
        ('outline-through', ['pulse', 'through'], 0, 'square', True),
        ('outline-off', ['pulse', 'outline'], 0, 'square', True),
        ('occluded-visible', ['pulse', 'visible'], 0, 'occluded', True),
        ('occluded-through', ['pulse', 'through'], 0, 'occluded', True),
    ]
    if args.cases:
        cases = [case for case in cases if case[0] in args.cases]
    report = dict(seed=0, retina_1080=args.retina_1080, binary_sha256=hashlib.sha256((GAME / ('village.exe' if os.name == 'nt' else 'village_linux.bin' if sys.platform.startswith('linux') else 'village.bin')).read_bytes()).hexdigest(), captures=[])
    for name, switches, seed, view, selected in cases:
        row = capture(out, name, switches, seed, view, args.steps, selected, args.retina_1080)
        report['captures'].append(row)
        print(name, row['png_sha256'], flush=True)
    names = {row['name'] for row in report['captures']}
    if {'hero-all', 'hero-repeat'} <= names:
        assert pixels(out / 'hero-all.png') == pixels(out / 'hero-repeat.png'), 'Equal seeds and steps changed pixels'
        report['deterministic_pixels'] = True
    comparisons = [('hero-all', 'hero-seed7'), ('hero-all', 'hero-no-smoke'), ('hero-all', 'hero-no-dust'), ('hero-all', 'hero-no-colour'), ('outline-visible', 'outline-through'), ('outline-visible', 'outline-off'), ('occluded-visible', 'occluded-through')]
    for a, b in comparisons:
        if {a, b} <= names:
            left, right = pixels(out / (a + '.png')), pixels(out / (b + '.png'))
            count = sum(left[i:i+4] != right[i:i+4] for i in range(0, len(left), 4))
            assert count > 0, f'{a}/{b} did not change pixels'
            report.setdefault('changed_pixels', {})[a + '/' + b] = count
    if {'hero-ui', 'hero-ui-no-colour'} <= names:
        left, right = pixels(out / 'hero-ui.png'), pixels(out / 'hero-ui-no-colour.png')
        assert all(left[(y*1920+x)*4:(y*1920+x)*4+4] == right[(y*1920+x)*4:(y*1920+x)*4+4] for y in range(34, 230) for x in range(34, 670)), 'Colour changed UI pixels'
        report['ui_pixel_parity'] = True
    (out / 'effects.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
