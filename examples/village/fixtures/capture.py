#!/usr/bin/env python3
"""Capture fixed views and a deterministic source tour through the Bridge."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / 'examples/village'
sys.path.insert(0, str(ROOT / 'scripts'))
from bridge import Bridge

def view(bridge, name):
    bridge.tell('view', name)
    bridge.step(2)

def launch(out):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, ROCCO_BRIDGE=str(port), ROCCO_SEED='0', ROCCO_EXIT_AFTER_FRAMES='20000', ROCCO_SPANS_CSV=str(out / 'capture-spans.csv'))
    suffix = '.exe' if os.name == 'nt' else '_linux.bin' if sys.platform.startswith('linux') else '.bin'
    log = (out / 'host.log').open('w')
    proc = subprocess.Popen([str(GAME / f'village{suffix}')], cwd=GAME, env=env, stdout=log, stderr=subprocess.STDOUT)
    return (proc, port, log)

def run(out, movie):
    out.mkdir(parents=True, exist_ok=True)
    proc, port, log = launch(out)
    observations = {}
    try:
        with Bridge.connect(port, wait=60) as bridge:
            bridge.hello()
            bridge.step(600)
            scene = bridge.scene()['scene']
            draws = []

            def collect(nodes):
                for n in nodes:
                    if 'Draw' in n:
                        draws.append(n['Draw'])
                    if 'Group' in n:
                        collect(n['Group']['children'])
            collect(scene['nodes'])
            assert len(draws) == 155 and all((d['mesh'] != 0 for d in draws)), 'All prepared assets must load'
            observations['draw_count'] = len(draws)
            for name in ('hero', 'square', 'walk'):
                view(bridge, name)
                observations[name] = bridge.scene()['scene']['camera']
                capture = bridge.screenshot(str(out / f'{name}.png'))
                assert capture['physical'] == [1920, 1080], capture
            view(bridge, 'walk')
            bridge.step(424, held=['W', 'LeftShift'])
            bridge.step(600, held=['D', 'LeftShift'])
            b = bridge.scene()['scene']['camera']['eye']
            assert 4.2 < b['x'] < 4.3 and abs(b['z'] - 5) < 0.1, b
            observations['collision_b'] = b
            bridge.step(1, mouse=[392.6991, 0])
            bridge.step(1, tap=['Enter'])
            selected = bridge.scene()['scene']
            group = next((n['Group'] for n in selected['nodes'] if 'Group' in n and n['Group']['id'] == 20))
            assert all((abs(n['Draw']['tint']['g'] - 0.85) < 1e-05 for n in group['children']))
            observations['selected_group'] = 20
            view(bridge, 'walk')
            bridge.step(565, held=['W', 'LeftShift'])
            bridge.step(600, held=['A', 'LeftShift'])
            a = bridge.scene()['scene']['camera']['eye']
            assert -4.1 < a['x'] < -4.0 and abs(a['z'] - 1) < 0.1, a
            observations['collision_a'] = a
            view(bridge, 'free')
            before = bridge.scene()['scene']['camera']['eye']
            bridge.step(120, held=['Space'])
            after = bridge.scene()['scene']['camera']['eye']
            assert after['y'] > before['y'] + 5.9
            observations['free_camera'] = after
            view(bridge, 'walk')
            bridge.step(1, mouse=[100, -50])
            look = bridge.scene()['scene']['camera']
            assert look['target']['x'] > look['eye']['x'] and look['target']['y'] > look['eye']['y']
            observations['mouse_look'] = look
            view(bridge, 'tour')
            route = []
            frames = out / 'route'
            frames.mkdir(exist_ok=True)
            for frame in range(150):
                route.append(bridge.scene()['scene']['camera'])
                if movie:
                    bridge.screenshot(str(frames / f'{frame:04d}.png'))
                bridge.step(24)
            observations['route'] = route
            observations['route_sha256'] = hashlib.sha256(json.dumps(route, sort_keys=True).encode()).hexdigest()
            bridge.quit()
        assert proc.wait(timeout=30) == 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=30)
        log.close()
    (out / 'observations.json').write_text(json.dumps(observations, indent=2) + '\n')
    if movie:
        subprocess.run(['ffmpeg', '-y', '-framerate', '5', '-i', str(out / 'route/%04d.png'), '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(out / 'route.mp4')], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps({'evidence': str(out), 'route_sha256': observations['route_sha256']}))
    return observations
if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('out', type=Path)
    parser.add_argument('--movie', action='store_true')
    args = parser.parse_args()
    run(args.out.resolve(), args.movie)
