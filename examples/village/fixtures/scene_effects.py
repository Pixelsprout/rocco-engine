#!/usr/bin/env python3
"""Verify full-density village effects with bounded native rendering."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from capture import GAME, launch
from foliage import draws
sys.path.insert(0, str(GAME.parents[1] / 'scripts'))
from bridge import Bridge, png_rgba


def capture(bridge, out, name):
    path = out / (name + '.png')
    reply = bridge.screenshot(str(path))
    assert reply['physical'] == [1920, 1080], reply
    return hashlib.sha256(path.read_bytes()).hexdigest()


def changed(out, first, second):
    a = png_rgba((out / (first + '.png')).read_bytes())[2]
    b = png_rgba((out / (second + '.png')).read_bytes())[2]
    return sum(a[i:i+4] != b[i:i+4] for i in range(0, len(a), 4))


def run(out, retina, seed=0, seed_only=False, movie=False):
    out.mkdir(parents=True, exist_ok=True)
    process, port, log = launch(out, ['--retina-1080'] if retina else [], seed)
    report = dict(seed=seed, full_density=22000, source_placements=1436, warmup_steps=432, physical=[1920, 1080], cameras={}, images={})
    try:
        with Bridge.connect(port, wait=60, process=process) as bridge:
            bridge.hello()
            initial = bridge.scene()['scene']
            assert not initial['nodes'] and initial['ui']
            for ready_step in range(1, 129):
                bridge.step(1)
                scene = bridge.scene()['scene']
                if scene['nodes']:
                    break
                assert scene['ui'], 'Incomplete assets must retain loading feedback'
            else:
                raise AssertionError('Full village readiness timed out')
            placed = draws(scene['nodes'])
            assert len([d for d in placed if 100 <= d['id'] < 100000]) == 1436
            assert len([d for d in placed if d['id'] >= 100000]) > 20000
            assert all(d['mesh'] for d in placed)
            assert [n['Group']['id'] for n in scene['nodes'] if 'Group' in n] == [10, 20, 30, 40]
            assert len([n for n in scene['nodes'] if 'Collider' in n]) == 6
            assert len(scene['emitters']) == 41
            assert all(e['image'] > 0 for e in scene['emitters'])
            assert {e['blend'] for e in scene['emitters']} == {'Alpha', 'Add'}
            report.update(ready_step=ready_step, emitters=scene['emitters'], environment=scene['environment'], shadow=scene['shadow'])
            if seed_only:
                bridge.step(2)
                report['images']['seed'] = capture(bridge, out, 'seed')
            else:
                bridge.tell('view', 'canopy')
                bridge.step(1)
                report['images']['wind-start'] = capture(bridge, out, 'wind-start')
                bridge.step(2)
                report['images']['wind-moving'] = capture(bridge, out, 'wind-moving')
                assert report['images']['wind-start'] != report['images']['wind-moving']
                bridge.tell('vegetation', 'wind')
                bridge.step(1)
                report['images']['wind-off'] = capture(bridge, out, 'wind-off')
                bridge.step(2)
                report['images']['wind-off-later'] = capture(bridge, out, 'wind-off-later')
                assert report['images']['wind-off'] == report['images']['wind-off-later']
                bridge.tell('vegetation', 'wind')
                bridge.tell('view', 'hero')
                bridge.step(432)
                report['cameras']['hero'] = bridge.scene()['scene']['camera']
                report['images']['hero'] = capture(bridge, out, 'hero')
                bridge.tell('vegetation', 'wind')
                bridge.tell('effects', 'pulse')
                bridge.tell('view', 'walk')
                bridge.step(2)
                bridge.step(1, mouse=[125.7, 0])
                bridge.step(1, tap=['Enter'])
                selected = bridge.scene()['scene']
                group = next(n['Group'] for n in selected['nodes'] if 'Group' in n and n['Group']['id'] == 20)
                assert group['selected'] and len(group['children']) > 1
                assert all(n['Draw']['tint'] == {'r': 1, 'g': 1, 'b': 1} for n in group['children'])
                bridge.tell('view', 'square')
                bridge.step(1)
                scene = bridge.scene()['scene']
                report['selected_group'] = 20
                report['selected_children'] = len(group['children'])
                report['cameras']['outline'] = scene['camera']
                report['images']['visible'] = capture(bridge, out, 'visible')
                bridge.tell('effects', 'through')
                bridge.step(1)
                assert bridge.scene()['scene']['camera'] == report['cameras']['outline']
                report['images']['through'] = capture(bridge, out, 'through')
                bridge.tell('effects', 'outline')
                bridge.step(1)
                report['images']['outline-off'] = capture(bridge, out, 'outline-off')
                report['policy_changed_pixels'] = changed(out, 'visible', 'through')
                report['outline_changed_pixels'] = changed(out, 'visible', 'outline-off')
                assert report['policy_changed_pixels'] > 1000
                assert report['outline_changed_pixels'] > 1000
                bridge.tell('effects', 'controls')
                bridge.step(1)
                report['images']['ui'] = capture(bridge, out, 'ui')
                bridge.tell('effects', 'colour')
                bridge.step(1)
                report['images']['ui-no-colour'] = capture(bridge, out, 'ui-no-colour')
                left = png_rgba((out / 'ui.png').read_bytes())[2]
                right = png_rgba((out / 'ui-no-colour.png').read_bytes())[2]
                assert all(left[(y*1920+x)*4:(y*1920+x)*4+4] == right[(y*1920+x)*4:(y*1920+x)*4+4] for y in range(40, 90) for x in range(40, 350)), 'Post changed opaque UI pixels'
                report['ui_unchanged_pixels'] = 15500
                assert changed(out, 'ui', 'ui-no-colour') > 1000
                bridge.tell('effects', 'smoke')
                bridge.step(1)
                assert len(bridge.scene()['scene']['emitters']) == 40
                bridge.tell('effects', 'dust')
                bridge.step(1)
                assert not bridge.scene()['scene']['emitters']
                bridge.tell('effects', 'none')
                bridge.step(1)
                bridge.tell('effects', 'all')
                bridge.step(1)
                assert len(bridge.scene()['scene']['emitters']) == 41
                bridge.tell('vegetation', 'field')
                bridge.tell('vegetation', 'casting')
                bridge.step(1)
                switched = draws(bridge.scene()['scene']['nodes'])
                assert len(switched) == 1437 and all(not d['casts_shadow'] for d in switched if d['id'] >= 100)
                bridge.tell('vegetation', 'field')
                bridge.tell('vegetation', 'casting')
                bridge.step(1)
                restored = draws(bridge.scene()['scene']['nodes'])
                assert len(restored) > 20000
                assert all(not d['casts_shadow'] for d in restored if d['id'] >= 100000)
                if movie:
                    bridge.step(1, tap=['R'])
                    bridge.tell('effects', 'controls')
                    bridge.tell('vegetation', 'wind')
                    bridge.tell('view', 'tour')
                    frames = out / 'route'
                    frames.mkdir(exist_ok=True)
                    route = []
                    for frame in range(8):
                        bridge.step(120)
                        camera = bridge.scene()['scene']['camera']
                        image = frames / f'{frame:04d}.png'
                        bridge.screenshot(str(image))
                        route.append(dict(step=(frame+1)*120, camera=camera, sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
                    subprocess.run(['ffmpeg', '-y', '-framerate', '1', '-i', str(frames / '%04d.png'), '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(out / 'route.mp4')], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    for image in frames.glob('*.png'):
                        image.unlink()
                    report['route_preview'] = route
            bridge.quit()
        assert process.wait(timeout=30) == 0
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        log.close()
    native_log = (out / 'host.log').read_text()
    assert not re.search(r'(?i)(panic|\[error\]|\[warn\]|not in|failed|absent|invalid|capacity|first [0-9]+)', native_log), native_log
    report.update(native_log_diagnostics=0, binary_sha256=hashlib.sha256((GAME / ('village.exe' if sys.platform == 'win32' else 'village_linux.bin' if sys.platform.startswith('linux') else 'village.bin')).read_bytes()).hexdigest())
    (out / 'effects.json').write_text(json.dumps(report, indent=2)+'\n')
    print(out, report['ready_step'], flush=True)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out', type=Path)
    parser.add_argument('--retina-1080', action='store_true')
    parser.add_argument('--movie', action='store_true')
    args = parser.parse_args()
    first = run(args.out.resolve(), args.retina_1080, movie=args.movie)
    second = run(args.out.resolve().with_name(args.out.name+'-replay'), args.retina_1080)
    assert first['images'] == second['images'], 'Fixed seeds and inputs must repeat all effect pixels'
    assert first['cameras'] == second['cameras'] and first['ready_step'] == second['ready_step']
    alternate = run(args.out.resolve().with_name(args.out.name+'-seed7'), args.retina_1080, seed=7, seed_only=True)
    assert first['emitters'] != alternate['emitters'], 'Game seed must change particle source streams'
