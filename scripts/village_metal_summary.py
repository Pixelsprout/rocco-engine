#!/usr/bin/env python3
"""Summarize labelled native Metal intervals without assuming trace frame IDs."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from village_capture_summary import distribution, read_csv, summarise

LABEL = re.compile(r'rocco\.frame=(\d+)\.pass=(\d+)\.kind=([A-Za-z0-9_-]+)')


def union_ms(intervals):
    merged = []
    for lo, hi in sorted(intervals):
        if merged and lo <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    return sum(hi-lo for lo, hi in merged)/1e6


def intervals(xml, process):
    references = {}
    frames = defaultdict(lambda: defaultdict(list))
    kinds = {}
    unlabelled = 0
    with Path(xml).open('rb') as stream:
        for _, element in ET.iterparse(stream, events=['end']):
            if 'id' in element.attrib:
                references[element.attrib['id']] = (element.text or '', element.attrib.get('fmt', ''))
            if element.tag != 'row':
                continue
            values = [references.get(child.attrib.get('ref'), (child.text or '', child.attrib.get('fmt', '')))
                      for child in element]
            if len(values) >= 11 and values[7][0] == 'Active' and values[10][1].startswith(process+' ('):
                labels = {match.groups() for value in values for raw in value
                          for match in LABEL.finditer(raw)}
                if len(labels) != 1:
                    unlabelled += 1
                else:
                    frame, index, kind = next(iter(labels))
                    key = (int(frame), int(index))
                    if key in kinds and kinds[key] != kind:
                        raise ValueError('Metal pass index has conflicting labels')
                    kinds[key] = kind
                    start, duration = int(values[0][0]), int(values[1][0])
                    if duration < 0:
                        raise ValueError('negative Metal interval')
                    frames[key[0]][key[1]].append((start, start+duration))
            element.clear()
    return frames, kinds, unlabelled


def summarise_metal(xml, boundaries, process, operation=False, expected_supplement=0):
    capture = summarise(boundaries, operation=operation, expected_supplement=expected_supplement)
    if not capture['metadata']['pass_labels']:
        raise ValueError('Metal capture requires ROCCO_CAPTURE_LABELS=1')
    members = {m['frame'] for m in capture['membership'] if m['included']}
    expected = {int(r['frame']): int(r['pass_count']) for r in read_csv(boundaries)}
    frames, kinds, unlabelled = intervals(xml, process)
    missing_frames, missing_passes = [], {}
    active, elapsed = [], []
    groups = defaultdict(list)
    raw = []
    for frame in sorted(members):
        passes = frames.get(frame)
        if not passes:
            missing_frames.append(frame)
            continue
        absent = sorted(set(range(expected[frame]))-passes.keys())
        if absent:
            missing_passes[str(frame)] = absent
            continue
        if set(passes)-set(range(expected[frame])):
            raise ValueError('Metal label refers to an unknown native pass')
        all_intervals = [interval for values in passes.values() for interval in values]
        lo = min(a for a, _ in all_intervals)
        hi = max(b for _, b in all_intervals)
        active.append(union_ms(all_intervals))
        elapsed.append((hi-lo)/1e6)
        totals = defaultdict(float)
        for index, values in sorted(passes.items()):
            value = union_ms(values)
            kind = kinds[(frame, index)]
            totals[kind] += value
            raw.append(dict(frame=frame, pass_index=index, kind=kind, intervals_ns=values, active_ms=value))
        for kind, value in totals.items():
            groups[kind].append(value)
    return dict(capture=capture, process=process, xml=str(xml), native_passes=raw,
                gpu_active_union_ms=distribution(active), gpu_frame_elapsed_ms=distribution(elapsed),
                pass_active_totals_ms={kind: distribution(values) for kind, values in sorted(groups.items())},
                expected_frames=len(members), missing_frames=missing_frames, missing_passes=missing_passes,
                unlabelled_process_active_rows=unlabelled,
                association='Native encoder labels contain engine frame and actual pass IDs; trace frame IDs are unused.',
                acceptance='Missing or unlabelled intervals require review. This is not display pacing evidence.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('xml', type=Path)
    parser.add_argument('boundaries', type=Path)
    parser.add_argument('--process', required=True)
    parser.add_argument('--operation', action='store_true')
    parser.add_argument('--supplement-count', type=int, default=0)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = summarise_metal(args.xml, args.boundaries, args.process, args.operation, args.supplement_count)
    args.out.write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
