#!/usr/bin/env python3
"""Run the production timestamp hook on native D3D11. CI makes no timing claim."""
import argparse
import csv
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, default=Path('build/gpu-timing-check'))
    args = parser.parse_args()
    if sys.platform != 'win32':
        parser.error('this fixture requires native Windows D3D11')
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    binary = out / 'gpu-timing-check.exe'
    command = [os.environ.get('ODIN', 'odin'), 'build', 'scripts/gpu-timing-check',
               '-define:ROCCO_D3D_GPU_TIMING=true', '-vet', '-strict-style', '-out:' + str(binary)]
    subprocess.run(command, check=True)
    csv_path = out / 'gpu.csv'
    try:
        result = subprocess.run([str(binary), str(csv_path)], capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired as error:
        (out / 'native.log').write_bytes((error.stdout or b'') + (error.stderr or b''))
        raise
    (out / 'native.log').write_text(result.stdout + result.stderr)
    print(result.stdout, end='')
    result.check_returncode()
    if 'PASS: D3D11 timestamp queries;' not in result.stdout:
        raise RuntimeError('native timestamp fixture did not finish')
    with csv_path.open(newline='') as file:
        rows = list(csv.DictReader(file))
    frames = [row for row in rows if row['scope'] == 'frame']
    if [int(row['frame']) for row in frames] != list(range(1, 121)):
        raise RuntimeError('native fixture did not preserve every frame')
    if frames[0]['status'] != 'Overflow':
        raise RuntimeError('native pass overflow was not recorded')
    counts = {}
    for row in frames:
        counts[row['status']] = counts.get(row['status'], 0) + 1
    if not counts.get('Valid'):
        raise RuntimeError('native fixture returned no ready valid timestamp pairs')
    if counts.get('Invalid') or counts.get('Query_Error') or counts.get('Pending'):
        raise RuntimeError('native fixture returned invalid queries')
    for row in rows:
        if row['status'] == 'Valid':
            if int(row['frequency_hz']) <= 0 or int(row['end_tick']) < int(row['start_tick']) or float(row['gpu_ms']) < 0:
                raise RuntimeError('invalid native timestamp conversion')
        elif any(row[key] for key in ('frequency_hz', 'start_tick', 'end_tick', 'gpu_ms')):
            raise RuntimeError('unusable query must not have a numeric duration')
    if not any(row['scope'] == 'pass' and row['status'] == 'Valid' for row in rows):
        raise RuntimeError('native pass timestamps never became ready')
    (out / 'evidence.json').write_text(json.dumps({
        'host': sys.platform, 'result': 'passed', 'frames': len(frames), 'status_counts': counts,
        'ownership': 'eight retained slots; no current-frame reads; DONOTFLUSH polling',
        'cleanup': 'all 1048 query objects released; repeat close verified',
        'performance_claim': False,
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
