#!/usr/bin/env python3
"""Check complete loading, source-scale vegetation, and fixed-step wind replay."""
import argparse
import hashlib
import json
import re
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


def run(out, steps, retina=False, motion_steps=60):
    out.mkdir(parents=True, exist_ok=True)
    proc, port, log = launch(out, ['--retina-1080'] if retina else [])
    observations = {'retina_1080': retina, 'motion_steps': motion_steps, 'seed': 0, 'hero_steps': steps, 'field_seed': 777, 'generated_field_draw_count': 22000}
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
            observations.update(environment=scene['environment'], shadow=scene['shadow'])
            observations['settings'] = {'density': 22000, 'visibility_distance': 65, 'fade_margin': 10, 'startup_shadow_map': 2048, 'startup_cascades': 2, 'startup_msaa': 4}
            bridge.tell('effects', 'none')
            bridge.tell('view', 'hero')
            bridge.step(steps)
            observations['hero_camera'] = bridge.scene()['scene']['camera']
            reply = bridge.screenshot(str(out / 'hero.png'))
            assert reply['physical'] == [1920, 1080], reply
            observations['physical'] = reply['physical']
            print('Captured hero', flush=True)
            observations['hero_sha256'] = hashlib.sha256((out / 'hero.png').read_bytes()).hexdigest()
            observations['pose_steps'] = {'hero': steps}
            for name in ['square', 'foliage', 'canopy']:
                bridge.tell('view', name)
                bridge.step(1)
                observations[name + '_camera'] = bridge.scene()['scene']['camera']
                assert bridge.screenshot(str(out / (name + '.png')))['physical'] == [1920, 1080]
                observations['pose_steps'][name] = steps + ['square', 'foliage', 'canopy'].index(name) + 1
            bridge.step(motion_steps)
            bridge.screenshot(str(out / 'canopy-moving.png'))
            assert (out / 'canopy.png').read_bytes() != (out / 'canopy-moving.png').read_bytes()
            bridge.tell('vegetation', 'wind')
            bridge.step(1)
            bridge.screenshot(str(out / 'canopy-still.png'))
            bridge.step(motion_steps)
            bridge.screenshot(str(out / 'canopy-still-later.png'))
            assert (out / 'canopy-still.png').read_bytes() == (out / 'canopy-still-later.png').read_bytes(), 'Disabled wind must retain the same pixels'
            bridge.tell('vegetation', 'casting')
            bridge.step(1)
            switched = draws(bridge.scene()['scene']['nodes'])
            assert all(not draw['casts_shadow'] for draw in switched if draw['id'] >= 100)
            bridge.tell('vegetation', 'casting')
            bridge.tell('vegetation', 'field')
            bridge.step(1)
            switched = draws(bridge.scene()['scene']['nodes'])
            assert len(switched) == 1437 and all(draw['id'] < 100000 for draw in switched)
            bridge.tell('vegetation', 'field')
            bridge.tell('lighting', 'sky')
            bridge.tell('quality', 'shadow-distance=60')
            bridge.step(1)
            controlled = bridge.scene()['scene']
            assert controlled['environment']['sky'] == 0
            assert controlled['shadow']['distance'] == 60
            assert len(draws(controlled['nodes'])) > 1437
            observations['controls'] = ['wind', 'casting', 'field', 'lighting sky', 'quality shadow-distance']
            bridge.quit()
        assert proc.wait(timeout=30) == 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=30)
        log.close()
    suffix = '.exe' if sys.platform == 'win32' else '_linux.bin' if sys.platform.startswith('linux') else '.bin'
    native_log = (out / 'host.log').read_text()
    assert not re.search(r'(?i)(panic|\[error\]|\[warn\]|not in|failed|absent|invalid|capacity|first [0-9]+)', native_log), native_log
    observations['native_log_diagnostics'] = 0
    observations['image_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.glob('*.png'))}
    observations['binary_sha256'] = hashlib.sha256((GAME / ('village' + suffix)).read_bytes()).hexdigest()
    (out / 'observations.json').write_text(json.dumps(observations, indent=2) + '\n')
    print(json.dumps(observations), flush=True)
    return observations


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('out', type=Path)
    parser.add_argument('--hero-steps', type=int, default=1680)
    parser.add_argument('--replay', action='store_true')
    parser.add_argument('--retina-1080', action='store_true')
    parser.add_argument('--compat', action='store_true', help='Bound rendering steps for software GPU compatibility checks')
    args = parser.parse_args()
    steps = 2 if args.compat else args.hero_steps
    motion_steps = 2 if args.compat else 60
    first = run(args.out.resolve(), steps, args.retina_1080, motion_steps)
    if args.replay:
        second = run(args.out.resolve().with_name(args.out.name + '-replay'), steps, args.retina_1080, motion_steps)
        assert first['image_sha256'] == second['image_sha256'], 'Equal seeds and steps must reproduce every captured pose and control'
        assert first['pose_steps'] == second['pose_steps']
        assert first['ready_step'] == second['ready_step']
        assert all(first[name + '_camera'] == second[name + '_camera'] for name in ['hero', 'square', 'foliage', 'canopy'])
