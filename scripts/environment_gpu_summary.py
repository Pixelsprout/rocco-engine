#!/usr/bin/env python3
"""Summarize active Metal intervals for the environment reference game."""
import argparse
import csv
import json
import math
import statistics
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('xml', type=Path)
parser.add_argument('--discard', type=int, required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
root = ET.parse(args.xml).getroot()
refs = {e.attrib['id']: e for e in root.iter() if 'id' in e.attrib}
def resolve(e):
    return refs[e.attrib['ref']] if 'ref' in e.attrib else e
frames = defaultdict(list)
processes = set()
for row in root.iter('row'):
    values = [resolve(e) for e in row]
    if len(values) < 11:
        continue
    process = values[10].attrib.get('fmt', '')
    if not process.startswith('environment-lighting.bin (') or values[7].text != 'Active':
        continue
    processes.add(process)
    start, duration, frame = int(values[0].text), int(values[1].text), int(values[3].text)
    frames[frame].append((start, start + duration))
if len(processes) != 1:
    raise ValueError(f'Expected one environment process: {processes}')
def union(intervals):
    merged = []
    for lo, hi in sorted(intervals):
        if merged and lo <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    return sum(hi - lo for lo,hi in merged) / 1e6
rows = [(frame, union(intervals), min(t[0] for t in intervals), max(t[1] for t in intervals), len(intervals)) for frame,intervals in sorted(frames.items())]
measured = rows[args.discard:]
values = sorted(row[1] for row in measured)
if not values:
    raise ValueError('No measured GPU frames')
def percentile(p):
    return values[math.ceil(len(values) * p) - 1]
args.out.parent.mkdir(parents=True, exist_ok=True)
with args.out.with_suffix('.csv').open('w') as f:
    writer = csv.writer(f)
    writer.writerow(['gpu_frame','active_ms','start_ns','end_ns','interval_count'])
    writer.writerows(rows)
result = {
    'process': next(iter(processes)),
    'total_gpu_frames': len(rows),
    'first_gpu_frame': rows[0][0],
    'last_gpu_frame': rows[-1][0],
    'discarded_gpu_frames': args.discard,
    'measured_gpu_frames': len(values),
    'first_measured_gpu_frame': measured[0][0],
    'gpu_frame_ms': {'median': statistics.median(values), 'p95': percentile(.95), 'p99': percentile(.99), 'max': max(values)},
    'percentile_method': 'nearest rank',
    'interval_method': 'Union of Active Metal intervals for the environment-lighting.bin process within each GPU frame',
    'intervals': str(args.xml),
}
args.out.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
