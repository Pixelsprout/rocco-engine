#!/usr/bin/env python3
"""Summarise valid D3D11 timestamp intervals and retain all exclusion counts."""
import argparse
from collections import Counter, defaultdict
import csv
import json
import math
from pathlib import Path


def distribution(values):
    ordered = sorted(values)
    if not ordered:
        return None
    return {**{name: ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]
               for name, fraction in [('p50', .50), ('p95', .95), ('p99', .99)]},
            'samples': len(ordered), 'max': ordered[-1]}


def summarise(rows, first, last):
    frames = {}
    passes = defaultdict(list)
    for row in rows:
        frame = int(row['frame'])
        if not first <= frame <= last:
            continue
        if row['scope'] == 'frame':
            if frame in frames:
                raise ValueError(f'duplicate frame row: {frame}')
            frames[frame] = row
        elif row['scope'] == 'pass':
            passes[frame].append(row)
        else:
            raise ValueError('unknown row scope')
    counts = Counter(row['status'] for row in frames.values())
    counts['Absent'] = last - first + 1 - len(frames)
    values, groups = [], defaultdict(list)
    for frame, row in frames.items():
        if row['status'] != 'Valid':
            continue
        duration = float(row['gpu_ms'])
        if not math.isfinite(duration) or duration < 0:
            raise ValueError(f'invalid frame duration: {frame}')
        values.append(duration)
        totals = defaultdict(float)
        indices = set()
        for sample in passes[frame]:
            index = int(sample['pass_index'])
            if sample['status'] != 'Valid' or index in indices:
                raise ValueError(f'invalid pass status or index: {frame}')
            indices.add(index)
            duration = float(sample['gpu_ms'])
            if not math.isfinite(duration) or duration < 0:
                raise ValueError(f'invalid pass duration: {frame}')
            totals[sample['pass']] += duration
        for name, total in totals.items():
            groups[name].append(total)
    return {
        'first_frame': first, 'last_frame': last, 'expected_frames': last - first + 1,
        'status_counts': dict(sorted(counts.items())), 'excluded_frames': last - first + 1 - len(values),
        'gpu_frame_elapsed_ms': distribution(values),
        'gpu_pass_totals_per_frame_ms': {name: distribution(samples) for name, samples in sorted(groups.items())},
        'percentile_method': 'nearest rank; valid frames only; absent pass kinds excluded from that pass distribution',
        'acceptance': 'Review all exclusions before acceptance. Missing slow frames can bias percentiles. Pacing requires a separate capture.',
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('csv', type=Path)
    parser.add_argument('--first-frame', type=int, required=True)
    parser.add_argument('--last-frame', type=int, required=True)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    if args.first_frame < 1 or args.last_frame < args.first_frame:
        parser.error('require 1 <= first-frame <= last-frame')
    with args.csv.open(newline='') as file:
        result = summarise(list(csv.DictReader(file)), args.first_frame, args.last_frame)
    text = json.dumps(result, indent=2) + '\n'
    if args.out:
        args.out.write_text(text)
    print(text, end='')


if __name__ == '__main__':
    main()
