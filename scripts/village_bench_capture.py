#!/usr/bin/env python3
"""Run the complete prebuilt Draw and mixed sweeps without a toolchain."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import time

from village_capture import CAPTURE_VARIABLES, digest, machine_observations, verify_manifest, write_json
from village_capture_summary import cpu_summary, read_csv

SIZES = [64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384]


def sweep_order(seed):
    left = [(game, size, process) for game in ('draws', 'mixed') for size in SIZES for process in range(1, 6)]
    result = []
    rng = (seed*6364136223846793005+1442695040888963407) % (1 << 64)
    while left:
        result.append(left.pop((rng >> 33) % len(left)))
        rng = (rng*6364136223846793005+1442695040888963407) % (1 << 64)
    return result


def run(args):
    package, output = args.package.resolve(), args.output.resolve()
    package_manifest = verify_manifest(package)
    output.mkdir(parents=True, exist_ok=False)
    seed = secrets.randbits(64) if args.shuffle_seed is None else args.shuffle_seed
    order = [('draws', 64, 1)] if args.operation else sweep_order(seed)
    observations = machine_observations()
    if args.machine:
        observations['recorded'] = json.loads(args.machine.read_text())
    frames, warmup = (8, 0) if args.operation else (2120, 120)
    manifest = dict(operation=args.operation, seed=0, shuffle_seed=seed, order=order, sizes=SIZES,
                    processes=5, warmup_frames=warmup, measured_frames=frames-warmup, cooldown_ms=1000,
                    package=package_manifest, machine=observations, mode='windowed Lockstep',
                    acceptance='Raw reference-PC sweeps only. Hardware acceptance and the reference headline remain open.', runs=[])
    write_json(output/'sweep.json', manifest)
    for game, size, process in order:
        name = f'{game}-{size}-p{process}'
        binary = package/f'bench-{game}.exe'
        csv = output/(name+'.csv')
        env = {k: v for k, v in os.environ.items() if k not in CAPTURE_VARIABLES}
        env.update(ROCCO_LOCKSTEP='1', ROCCO_SEED='0', ROCCO_EXIT_AFTER_FRAMES=str(frames),
                   ROCCO_SPANS_CSV=str(csv), ROCCO_NO_GAMEPADS='1')
        record = dict(game=game, n=size, process=process, binary_sha256=digest(binary), command=[str(binary), str(size)])
        manifest['runs'].append(record)
        try:
            with (output/(name+'.log')).open('wb') as log:
                child = subprocess.Popen(record['command'], cwd=package, env=env, stdout=log, stderr=subprocess.STDOUT)
                try:
                    record['exit'] = child.wait(timeout=args.timeout)
                finally:
                    if child.poll() is None:
                        child.terminate()
                        try:
                            child.wait(timeout=15)
                        except subprocess.TimeoutExpired:
                            child.kill()
                            child.wait(timeout=15)
            if record['exit']:
                raise ValueError(f'{name} exited {record["exit"]}')
            rows = read_csv(csv)
            if len(rows) != frames or [int(r['frame']) for r in rows] != list(range(1, frames+1)):
                raise ValueError(f'{name} is missing frames')
            if any(int(r['steps']) != 1 for r in rows):
                raise ValueError(f'{name} did not use Lockstep')
            record['result'] = 'complete'
            summary = cpu_summary(rows, range(warmup+1, frames+1))
            summary['reference_policy'] = 'Nearest-rank supplemental summary; retain raw samples for the existing reference analysis and budget scaling.'
            write_json(output/(name+'.json'), summary)
        except BaseException as error:
            record['result'] = 'failed'
            record['failure'] = str(error)
            raise
        finally:
            write_json(output/'sweep.json', manifest)
        time.sleep(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--machine', type=Path)
    parser.add_argument('--shuffle-seed', type=int)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--operation', action='store_true')
    args = parser.parse_args()
    if not args.operation and args.machine is None:
        parser.error('full sweeps require --machine with verified reference-PC details')
    if args.shuffle_seed is not None and not 0 <= args.shuffle_seed < 1 << 64:
        parser.error('shuffle seed must be U64')
    run(args)


if __name__ == '__main__':
    main()
