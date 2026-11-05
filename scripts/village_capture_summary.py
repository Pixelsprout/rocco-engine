#!/usr/bin/env python3
"""Join observed village route boundaries without replacing missing measurements."""
import argparse
from collections import Counter, defaultdict
import csv
import json
import math
from pathlib import Path

REQUIRED_PASSES = {'Shadow', 'Main', 'Scene_Depth', 'Selection', 'Game_Post_HDR',
                   'Game_Post_LDR', 'Bloom_Prefilter', 'Bloom_Down', 'Bloom_Up', 'Post', 'Blit'}
ENABLED_SETTINGS = {'wind', 'canopy', 'grass', 'field', 'source_casts_shadow', 'outline', 'visible_only',
                    'pulse', 'glow', 'colour', 'smoke', 'dust', 'sun', 'sky', 'exposure', 'bloom', 'haze', 'lamps', 'ground'}
GPU_STATUSES = {'Valid', 'Disjoint', 'Invalid', 'Overflow', 'Missing_Busy', 'Missing_Shutdown', 'Query_Error'}


def distribution(values):
    values = sorted(values)
    if not values:
        return None
    return {'samples': len(values), **{name: values[max(0, math.ceil(len(values)*p)-1)]
            for name, p in [('p50', .5), ('p95', .95), ('p99', .99)]}, 'max': values[-1]}


def read_csv(path):
    with Path(path).open(newline='', encoding='utf-8-sig') as stream:
        return list(csv.DictReader(stream))


def unique_frames(rows):
    result = {}
    for row in rows:
        frame = int(row['frame'])
        if frame in result:
            raise ValueError(f'duplicate frame {frame}')
        result[frame] = row
    return result


def markers(path):
    result = []
    for line in Path(str(path)+'.commands.jsonl').read_text().splitlines():
        row = json.loads(line)
        for command in row['commands']:
            if not isinstance(command, dict) or 'Tell' not in command:
                continue
            tell = command['Tell']
            if tell['port'] != 'village.capture.v1':
                continue
            event, cycle, count, waypoint, mode = tell['msg'].split('|')
            result.append(dict(event=event, cycle=int(cycle), count=int(count), waypoint=int(waypoint),
                               kind=mode, step=int(row['step']), frame=int(row['frame'])))
    if len(result) > 64:
        raise ValueError('more than 64 village markers')
    return result


def settings(path, ready):
    snapshots = []
    for line in Path(str(path)+'.commands.jsonl').read_text().splitlines():
        row = json.loads(line)
        for command in row['commands']:
            if isinstance(command, dict) and command.get('Tell', {}).get('port') == 'village.capture.settings.v1':
                snapshots.append((row, json.loads(command['Tell']['msg'])))
    if len(snapshots) != 1 or snapshots[0][0]['step'] != ready['step']:
        raise ValueError('missing or misplaced effective settings snapshot')
    value = snapshots[0][1]
    if (value['density'] != 22000 or value['distance'] != 65 or value['width'] != 2
            or value['field_casts_shadow'] is not False or value['controls'] is not False
            or any(value[name] is not True for name in ENABLED_SETTINGS)):
        raise ValueError('effective scene settings differ from the complete village')
    return value


def route_ranges(events, operation):
    kind = 'operation' if operation else 'full'
    if any(e['kind'] != kind for e in events):
        raise ValueError('capture kind differs from the requested evidence mode')
    names = [e['event'] for e in events if e['event'] != 'waypoint']
    expected = ['ready', 'warmup_start', 'warmup_end', 'route_start', 'route_end',
                'route_start', 'route_end', 'complete']
    if names != expected:
        raise ValueError(f'incomplete or unordered capture markers: {names}')
    ready, warmup, warmup_end = (next(e for e in events if e['event'] == name)
                                 for name in ['ready', 'warmup_start', 'warmup_end'])
    warmup_steps, route_steps = (120, 120) if operation else (1800, 3600)
    if ready['step'] != warmup['step'] or warmup_end['step']-warmup['step'] != warmup_steps:
        raise ValueError('warmup does not start from observed readiness or has the wrong length')
    ranges = []
    for cycle in (1, 2):
        starts = [e for e in events if e['event'] == 'route_start' and e['cycle'] == cycle]
        ends = [e for e in events if e['event'] == 'route_end' and e['cycle'] == cycle]
        if len(starts) != 1 or len(ends) != 1:
            raise ValueError(f'missing cycle {cycle}')
        start, end = starts[0], ends[0]
        if end['step']-start['step'] != route_steps or end['count'] != route_steps:
            raise ValueError(f'wrong route length for cycle {cycle}')
        if not operation and end['waypoint'] != 6:
            raise ValueError(f'cycle {cycle} did not reach the final source waypoint')
        ranges.append(dict(cycle=cycle, first_step=start['step'], end_step_exclusive=end['step']))
    if ranges[0]['first_step'] != warmup_end['step'] or ranges[0]['end_step_exclusive'] != ranges[1]['first_step']:
        raise ValueError('route cycles do not follow warmup and each other directly')
    complete = events[-1]
    if complete['step']-ranges[-1]['end_step_exclusive'] != 120:
        raise ValueError('capture drain is incomplete')
    return ranges


def membership(rows, ranges):
    result = []
    for row in rows:
        before, after, previous = (int(row[k]) for k in ['step_before', 'step_after', 'prev_step'])
        count = int(row['steps'])
        if after-before != count or previous > after or count < 0:
            raise ValueError(f'inconsistent fixed steps in frame {row["frame"]}')
        cycles = []
        measured_steps = 0
        mixed = False
        for route in ranges:
            lo, hi = route['first_step'], route['end_step_exclusive']
            overlap = max(0, min(after, hi-1)-max(before+1, lo)+1) if count else 0
            measured_steps += overlap
            stepped = overlap > 0
            rendered = lo <= previous < hi or lo <= after < hi
            if stepped or rendered:
                cycles.append(route['cycle'])
                mixed |= previous < lo or after >= hi or (count > 0 and before+1 < lo)
        result.append(dict(frame=int(row['frame']), cycles=cycles, included=bool(cycles), mixed=mixed, measured_steps=measured_steps))
    return result


def gpu_summary(rows, selected):
    frame_rows = unique_frames([r for r in rows if r['scope'] == 'frame'])
    passes = defaultdict(list)
    for row in rows:
        if row['scope'] == 'pass':
            passes[int(row['frame'])].append(row)
        elif row['scope'] != 'frame':
            raise ValueError('unknown GPU row scope')
    counts = Counter()
    values, groups = [], defaultdict(list)
    missing_passes = {}
    counts.update({name: 0 for name in GPU_STATUSES | {'Absent'}})
    for frame in selected:
        row = frame_rows.get(frame)
        if row is None:
            counts['Absent'] += 1
            continue
        status = row['status']
        if status not in GPU_STATUSES:
            raise ValueError(f'unknown or unfinished GPU status: {status}')
        counts[status] += 1
        samples = passes[frame]
        indices = [int(s['pass_index']) for s in samples]
        if len(set(indices)) != len(indices):
            raise ValueError('duplicate GPU pass index')
        if any(s['status'] != status for s in samples):
            raise ValueError('GPU pass validity differs from its frame')
        if status != 'Valid':
            if any(sample[k] != '' for sample in [row, *samples]
                   for k in ['frequency_hz', 'start_tick', 'end_tick', 'gpu_ms']):
                raise ValueError('invalid GPU sample has numeric data')
            continue
        value = float(row['gpu_ms'])
        if not math.isfinite(value) or value < 0:
            raise ValueError('invalid valid GPU duration')
        values.append(value)
        totals = defaultdict(float)
        for sample in samples:
            value = float(sample['gpu_ms'])
            if not math.isfinite(value) or value < 0:
                raise ValueError('invalid valid pass duration')
            totals[sample['pass']] += value
        missing = REQUIRED_PASSES - totals.keys()
        if missing:
            missing_passes[str(frame)] = sorted(missing)
        for name, total in totals.items():
            groups[name].append(total)
    return dict(gpu_frame_elapsed_ms=distribution(values), status_counts=dict(sorted(counts.items())),
                expected_frames=len(selected), excluded_frames=len(selected)-len(values),
                missing_required_passes=missing_passes,
                pass_totals_per_frame_ms={k: distribution(v) for k, v in sorted(groups.items())},
                definition='D3D timestamp elapsed before commit; excludes presentation and display wait',
                acceptance='Review every exclusion and missing pass before hardware acceptance.')


def cpu_summary(rows, selected):
    frames = unique_frames(rows)
    spans = defaultdict(list)
    steps = Counter()
    missing = []
    totals = []
    for frame in selected:
        row = frames.get(frame)
        if row is None:
            missing.append(frame)
            continue
        steps[int(row['steps'])] += 1
        if not any(k.endswith('_us') and k != 'span_cost_us' for k in row):
            raise ValueError('CPU capture has no Span columns')
        total = 0
        for key, raw in row.items():
            if key.endswith('_us') and key != 'span_cost_us':
                value = float(raw)/1000
                if not math.isfinite(value) or value < 0:
                    raise ValueError('invalid CPU span')
                spans[key].append(value)
                total += value
        totals.append(total)
    return dict(frame_cpu_work_ms=distribution(totals), spans_ms={k: distribution(v) for k, v in spans.items()},
                steps_per_frame=dict(sorted(steps.items())), absent_frames=missing,
                definition='Sum of engine CPU Spans; includes commit CPU duration, not GPU work')


def presentmon_summary(rows, boundaries, frequency):
    if not rows or 'CPUStartQPC' not in rows[0]:
        raise ValueError('PresentMon requires v2 metrics and --qpc_time')
    lo = int(boundaries[0]['start_tick'])
    hi = int(boundaries[-1]['commit_end_tick'])
    selected = [r for r in rows if lo <= int(r['CPUStartQPC']) <= hi]
    missing = Counter()
    dropped = 0
    metrics = defaultdict(list)
    swaps = Counter()
    for row in selected:
        dropped += row.get('DisplayedTime') in ('', 'NA')
        swaps[row.get('SwapChainAddress', '')] += 1
        for name in ['FrameTime', 'DisplayedTime', 'GPUBusy', 'GPUTime', 'GPUWait', 'CPUBusy', 'CPUWait']:
            raw = row.get(name)
            if raw in (None, '', 'NA'):
                missing[name] += 1
            else:
                value = float(raw)
                if not math.isfinite(value) or value < 0:
                    raise ValueError('invalid PresentMon metric')
                metrics[name].append(value)
    return dict(headers=list(rows[0]), raw_rows=len(rows), route_window_rows=len(selected),
                outside_window_rows=len(rows)-len(selected), missing=dict(missing), swapchains=dict(swaps),
                metrics_ms={k: distribution(v) for k, v in metrics.items()},
                not_displayed_rows=dropped,
                route_start_covered=bool(rows) and min(int(r['CPUStartQPC']) for r in rows) <= lo,
                route_end_covered=bool(rows) and max(int(r['CPUStartQPC']) for r in rows) >= hi,
                qpc_window=[lo, hi], frequency_hz=frequency,
                association='Native QPC route time window; no engine-frame join or row-position matching',
                acceptance='Preserve missing display results and dropped frames; review raw margins and event loss.')


def summarise(path, cpu=None, gpu=None, presentmon=None, operation=False, expected_supplement=0):
    path = Path(path)
    meta = json.loads(Path(str(path)+'.meta.json').read_text())
    if meta['error'] or meta['mode'] != 'Real_Clock':
        raise ValueError(f'failed capture: {meta}')
    if meta['frequency_hz'] <= 0 or meta['seed'] != 0:
        raise ValueError('invalid native clock or unexpected game seed')
    if (meta['source_draws'] != 1436 or not 0 < meta['field_draws'] <= 22000 or meta['post_count'] != 2
            or meta['emitter_count'] != 41 or meta['selected_groups'] != [20]):
        raise ValueError('capture lacks full source content, field, selected Group 20, or required effects')
    if not 0 <= expected_supplement <= 160:
        raise ValueError('expected supplement count is outside its reserved range')
    if 'supplement_draws' not in meta or 'other_draws' not in meta:
        raise ValueError('capture metadata lacks separate supplement and other counts')
    if meta['supplement_draws'] != expected_supplement or meta['other_draws'] < 0:
        raise ValueError('capture supplement count differs from the frozen scene contract')
    rows = read_csv(path)
    frames = unique_frames(rows)
    if list(frames) != list(range(1, meta['frames']+1)):
        raise ValueError('missing or unordered boundary frame')
    if meta['step_hz'] != 120 or meta['msaa'] != 4 or meta['shadow_map'] != 2048 or meta['shadow_cascades'] != 2:
        raise ValueError('capture startup quality differs from the required settings')
    before = 0
    for row in rows:
        if int(row['step_before']) != before:
            raise ValueError('boundary fixed-step ranges are not continuous')
        before = int(row['step_after'])
    events = markers(path)
    last_step = -1
    for event in events:
        frame = frames.get(event['frame'])
        if (frame is None or not int(frame['step_before']) < event['step'] <= int(frame['step_after'])
                or event['step'] < last_step):
            raise ValueError('marker does not belong to its recorded frame or execution order')
        last_step = event['step']
    routes = route_ranges(events, operation)
    effective = settings(path, events[0])
    members = membership(rows, routes)
    fixed_steps = sum(m['measured_steps'] for m in members)
    if fixed_steps != sum(r['end_step_exclusive']-r['first_step'] for r in routes):
        raise ValueError('route fixed-step count differs from observed boundaries')
    selected = [m['frame'] for m in members if m['included']]
    if not selected:
        raise ValueError('no route frames')
    expected = (960, 540) if operation else (1920, 1080)
    measured = [frames[i] for i in selected]
    if any(not math.isclose(float(r['fov_y']), 1.3089969, abs_tol=1e-6) for r in measured):
        raise ValueError('capture lens differs from the source tour')
    if any(tuple(int(float(r[k])) for k in ['width', 'height']) != expected for r in measured):
        raise ValueError('wrong physical dimensions during the route')
    result = dict(version=1, evidence='operation only' if operation else 'capture prerequisite; hardware acceptance remains open',
                  metadata=meta, expected_supplement_draws=expected_supplement, effective_settings=effective, markers=events, routes=routes, membership=members,
                  measured_frames=len(selected), measured_fixed_steps=fixed_steps, mixed_frames=[m['frame'] for m in members if m['mixed']],
                  original_delta_ms=distribution([float(r['delta_seconds'])*1000 for r in measured]),
                  clamped_frames=[int(r['frame']) for r in measured if float(r['clamped_seconds']) > 0],
                  callback_interval_ms=distribution([(int(b['start_tick'])-int(a['start_tick']))*1000/meta['frequency_hz']
                                                     for a, b in zip(measured, measured[1:])]),
                  pacing_limit='Callback cadence alone does not prove display cadence.',
                  percentile_method='nearest rank; whole mixed frames retained')
    if cpu:
        cpu_rows = read_csv(cpu)
        cpu_frames = unique_frames(cpu_rows)
        if any(i in cpu_frames and int(cpu_frames[i]['steps']) != int(frames[i]['steps']) for i in selected):
            raise ValueError('CPU and boundary fixed-step counts differ')
        result['cpu'] = cpu_summary(cpu_rows, selected)
    if gpu:
        result['gpu'] = gpu_summary(read_csv(gpu), selected)
    if presentmon:
        if meta['clock'] != 'QueryPerformanceCounter':
            raise ValueError('PresentMon requires native QPC boundaries')
        result['presentmon'] = presentmon_summary(read_csv(presentmon), measured, meta['frequency_hz'])
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('boundaries', type=Path)
    parser.add_argument('--cpu', type=Path)
    parser.add_argument('--gpu', type=Path)
    parser.add_argument('--presentmon', type=Path)
    parser.add_argument('--operation', action='store_true')
    parser.add_argument('--supplement-count', type=int, default=0)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = summarise(args.boundaries, args.cpu, args.gpu, args.presentmon, args.operation, args.supplement_count)
    args.out.write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
