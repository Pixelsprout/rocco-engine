#!/usr/bin/env python3
"""Check complete loading, source-scale vegetation, and fixed-step wind replay."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

from capture import GAME, launch
sys.path.insert(0, str(GAME.parents[1] / 'scripts'))
from bridge import Bridge


def draws(nodes):
    result = []
    for node in nodes:
        if 'Draw' in node:
            result.append(node['Draw'])
        elif 'Group' in node:
            result.extend(draws(node['Group']['children']))
    return result


def run(out, steps):
    out.mkdir(parents=True, exist_ok=True)
    proc, port, log = launch(out)
    observations = {'seed': 0, 'hero_steps': steps, 'field_seed': 777, 'generated_field_draw_count': 22000}
    try:
        with Bridge.connect(port, wait=60) as bridge:
            bridge.hello()
            start = bridge.scene()['scene']
            assert not start['nodes'] and start['ui']
            bridge.screenshot(str(out / 'loading.png'))
            ready_step = 0
            for _ in range(128):
                bridge.step(1)
                ready_step += 1
                scene = bridge.scene()['scene']
                if scene['nodes']:
                    break
                assert scene['ui'], 'Loading must keep deliberate feedback'
            assert scene['nodes'], 'Complete scene readiness timed out'
            print('Loaded complete village', flush=True)
            placed = draws(scene['nodes'])
            field = [draw for draw in placed if draw['id'] >= 100000]
            source = [draw for draw in placed if 100 <= draw['id'] < 100000]
            assert len(source) == 1436
            assert all(draw['mesh'] for draw in placed)
            assert field and all(not draw['casts_shadow'] for draw in field)
            assert all(draw['casts_shadow'] for draw in source)
            groups = [node['Group']['id'] for node in scene['nodes'] if 'Group' in node]
            assert groups == [10, 20, 30, 40]
            assert len([node for node in scene['nodes'] if 'Collider' in node]) == 6
            observations.update(ready_step=ready_step, draw_count=len(placed), source_draw_count=len(source), visible_field_draw_count=len(field), groups=groups)
            bridge.tell('view', 'hero')
            bridge.step(steps)
            observations['hero_camera'] = bridge.scene()['scene']['camera']
            reply = bridge.screenshot(str(out / 'hero.png'))
            assert reply['physical'] == [1920, 1080], reply
            observations['physical'] = reply['physical']
            print('Captured hero', flush=True)
            observations['hero_sha256'] = hashlib.sha256((out / 'hero.png').read_bytes()).hexdigest()
            for name in ['square', 'foliage', 'canopy']:
                bridge.tell('view', name)
                bridge.step(1)
                observations[name + '_camera'] = bridge.scene()['scene']['camera']
                bridge.screenshot(str(out / (name + '.png')))
            bridge.step(60)
            bridge.screenshot(str(out / 'canopy-moving.png'))
            assert (out / 'canopy.png').read_bytes() != (out / 'canopy-moving.png').read_bytes()
            bridge.tell('vegetation', 'wind')
            bridge.step(1)
            bridge.screenshot(str(out / 'canopy-still.png'))
            bridge.quit()
        assert proc.wait(timeout=30) == 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=30)
        log.close()
    suffix = '.exe' if sys.platform == 'win32' else '_linux.bin' if sys.platform.startswith('linux') else '.bin'
    observations['binary_sha256'] = hashlib.sha256((GAME / ('village' + suffix)).read_bytes()).hexdigest()
    (out / 'observations.json').write_text(json.dumps(observations, indent=2) + '\n')
    print(json.dumps(observations), flush=True)
    return observations


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('out', type=Path)
    parser.add_argument('--hero-steps', type=int, default=1680)
    parser.add_argument('--replay', action='store_true')
    args = parser.parse_args()
    first = run(args.out.resolve(), args.hero_steps)
    if args.replay:
        second = run(args.out.resolve().with_name(args.out.name + '-replay'), args.hero_steps)
        assert first['hero_sha256'] == second['hero_sha256'], 'Equal seeds and steps must reproduce the wind pose'
