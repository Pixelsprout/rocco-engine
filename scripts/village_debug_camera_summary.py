#!/usr/bin/env python3
"""Summarize bounded real-clock debug-camera frames after village asset loading."""
import argparse
import json
import math
from pathlib import Path

from village_capture_summary import cpu_summary, distribution, read_csv, unique_frames


def last_load_step(path):
    last = 0
    for line in Path(str(path)+'.commands.jsonl').read_text().splitlines():
        record = json.loads(line)
        if any(isinstance(command, dict) and 'Load' in command for command in record['commands']):
            last = max(last, int(record['step']))
    return last


def camera_moved(before, after):
    def pose(row):
        eye = tuple(float(row[f'eye_{axis}']) for axis in 'xyz')
        target = tuple(float(row[f'target_{axis}']) for axis in 'xyz')
        return eye, tuple(b-a for a, b in zip(eye, target))
    old_eye, old_direction = pose(before)
    eye, direction = pose(after)
    return math.dist(old_eye, eye) > 1e-5 or math.dist(old_direction, direction) > 1e-5


def frame_samples(rows, frequency_hz, first_frame=1, last_frame=None, first_step=0):
    result = []
    for before, frame, after in zip(rows, rows[1:], rows[2:]):
        number = int(frame['frame'])
        if number < first_frame or (last_frame is not None and number > last_frame):
            continue
        if int(frame['step_before']) < first_step:
            continue
        elapsed = (int(after['start_tick'])-int(frame['start_tick']))*1000/frequency_hz
        commit = (int(frame['commit_end_tick'])-int(frame['commit_start_tick']))*1000/frequency_hz
        if elapsed < 0 or commit < 0:
            raise ValueError('native capture clocks went backwards')
        result.append(dict(frame=number, interval_ms=elapsed, commit_cpu_ms=commit,
                           moving=camera_moved(before, frame), steps=int(frame['steps']),
                           clamped_ms=float(frame['clamped_seconds'])*1000,
                           eye=[float(frame[f'eye_{axis}']) for axis in 'xyz']))
    return result


def summarise(path, cpu=None, first_frame=1, last_frame=None, settle_steps=120):
    path = Path(path)
    meta = json.loads(Path(str(path)+'.meta.json').read_text())
    if meta['error'] or meta['mode'] != 'Real_Clock' or meta.get('debug_camera') is not True:
        raise ValueError('this summary requires a successful real-clock debug-camera capture')
    if meta['frequency_hz'] <= 0 or settle_steps < 0:
        raise ValueError('invalid native clock or settle step count')
    rows = read_csv(path)
    frames = unique_frames(rows)
    if list(frames) != list(range(1, meta['frames']+1)):
        raise ValueError('missing or unordered boundary frame')
    loaded_step = last_load_step(path)
    samples = frame_samples(rows, meta['frequency_hz'], first_frame, last_frame, loaded_step+settle_steps)
    if not samples:
        raise ValueError('no frames remain after loading and the selected settling period')
    moving = [sample for sample in samples if sample['moving']]
    stationary = [sample for sample in samples if not sample['moving']]
    result = dict(source=str(path), metadata=meta, last_load_step=loaded_step,
                  settle_steps=settle_steps, first_frame=first_frame, last_frame=last_frame,
                  samples=len(samples), moving_frames=len(moving), stationary_frames=len(stationary),
                  moving_interval_ms=distribution([sample['interval_ms'] for sample in moving]),
                  stationary_interval_ms=distribution([sample['interval_ms'] for sample in stationary]),
                  moving_commit_cpu_ms=distribution([sample['commit_cpu_ms'] for sample in moving]),
                  stationary_commit_cpu_ms=distribution([sample['commit_cpu_ms'] for sample in stationary]),
                  slowest_frames=sorted(samples, key=lambda sample: sample['interval_ms'], reverse=True)[:20],
                  limits='Callback intervals do not prove display cadence. CPU commit does not measure GPU work.')
    if cpu:
        if meta['spans'] is not True:
            raise ValueError('CPU Spans file does not match the ordinary executable')
        cpu_rows = read_csv(cpu)
        result['moving_cpu'] = cpu_summary(cpu_rows, [sample['frame'] for sample in moving])
        result['stationary_cpu'] = cpu_summary(cpu_rows, [sample['frame'] for sample in stationary])
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('boundaries', type=Path)
    parser.add_argument('--cpu', type=Path)
    parser.add_argument('--first-frame', type=int, default=1)
    parser.add_argument('--last-frame', type=int)
    parser.add_argument('--settle-steps', type=int, default=120)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    report = summarise(args.boundaries, args.cpu, args.first_frame, args.last_frame, args.settle_steps)
    args.out.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
