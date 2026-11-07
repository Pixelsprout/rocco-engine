#!/usr/bin/env python3
"""Check view-opposed Surface normals under uniform environment lighting."""
import hashlib
import json
from pathlib import Path
import sys

from bridge_check import check
from surface_check import green, pixels, run, single


def compare(left, right):
    a, b = pixels(left), pixels(right)
    differences = [abs(x - y) for i, (x, y) in enumerate(zip(a, b)) if i % 4 != 3]
    return {'mean_difference': sum(differences) / len(differences), 'changed_channels': sum(d > 2 for d in differences)}


def indirect(driver, shot):
    driver.step(1)
    check(driver.scene()['scene']['environment']['sky'] != 0, 'uniform white environment loaded')
    frame = shot('frame')
    check(green(frame) > 1000, 'the assigned leaf Surface remains visible')
    return frame


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/indirect-surface-check').resolve()
    out.mkdir(parents=True, exist_ok=True)
    result = {}
    for label, layout in [('rigid', []), ('instanced', ['--instances'])]:
        front = run(label + '-front', ['--indirect', '--no-wind', *layout], out, indirect)
        opposed = run(label + '-opposed', ['--indirect', '--opposed', '--no-wind', *layout], out, indirect)
        result[label] = compare(front, opposed)
        check(result[label]['mean_difference'] < .2, label + ' view-opposed normals retain equal white-sky response')
    builtin = run('indirect-builtin', ['--indirect', '--builtin', '--no-wind'], out, single)
    default = run('indirect-default', ['--indirect', '--default-shader', '--no-wind'], out, single)
    result['default_surface'] = compare(builtin, default)
    check(result['default_surface']['mean_difference'] < .2, 'empty Surface preserves built-in environment response')
    result['images'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.glob('*.png'))}
    (out / 'evidence.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
