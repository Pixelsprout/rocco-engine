#!/usr/bin/env python3
"""Run bounded village captures with explicit instrumentation and provenance."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time

from village_capture_summary import read_csv, summarise

PRESENTMON_SHA256 = 'b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af'
CAPTURE_VARIABLES = ('ROCCO_BRIDGE', 'ROCCO_HEADLESS', 'ROCCO_LOCKSTEP', 'ROCCO_SEED',
                     'ROCCO_DEBUG_CAMERA', 'ROCCO_ASSETS', 'ROCCO_ALLOC_REPORT', 'ROCCO_SPANS_CSV',
                     'ROCCO_D3D_GPU_CSV', 'ROCCO_CAPTURE_CSV', 'ROCCO_CAPTURE_LABELS', 'ROCCO_EXIT_AFTER_FRAMES')


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()


def scene_contract(root):
    path = Path(root)/'examples/village/source/rubble-manifest.json'
    count = 0
    checksum = None
    if path.is_file():
        manifest = json.loads(path.read_text())
        count = manifest['count']
        if manifest['id_range'] != [200000, 200160] or not 0 <= count <= 160:
            raise ValueError('supplement manifest differs from the reserved scene range')
        checksum = digest(path)
    return dict(source_assets=93, source_records=1436, field_records=22000, supplement_records=count,
                supplement_id_range=[200000, 200160], supplement_manifest_sha256=checksum)


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True)+'\n')


def verify_manifest(package):
    path = package/'manifest.json'
    if not path.is_file():
        raise ValueError('package manifest is missing')
    manifest = json.loads(path.read_text())
    for name, entry in manifest['files'].items():
        candidate = package/name
        if not candidate.resolve().is_relative_to(package.resolve()):
            raise ValueError('package manifest contains an outside path')
        if candidate.stat().st_size != entry['bytes'] or digest(candidate) != entry['sha256']:
            raise ValueError(f'package file differs from manifest: {name}')
    return manifest


def command_output(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=30)
        return dict(command=args, returncode=result.returncode, stdout=result.stdout[:65536], stderr=result.stderr[:65536])
    except (OSError, subprocess.TimeoutExpired) as error:
        return dict(command=args, error=str(error))


def machine_observations():
    result = dict(platform=platform.platform(), machine=platform.machine(), python=sys.version)
    if sys.platform == 'win32':
        result['native'] = command_output(['powershell', '-NoProfile', '-Command',
            "@{cpu=Get-CimInstance Win32_Processor | Select-Object Name; computer=Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory; gpu=Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate; hags=Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue | Select-Object HwSchMode} | ConvertTo-Json -Depth 5"])
        result['power_scheme'] = command_output(['powercfg', '/getactivescheme'])
    elif sys.platform == 'darwin':
        result['native'] = command_output(['system_profiler', 'SPHardwareDataType', 'SPDisplaysDataType', '-json', '-detailLevel', 'mini'])
        result['power'] = command_output(['pmset', '-g', 'custom'])
    return result


def environment(mode, out):
    result = {key: value for key, value in os.environ.items() if key not in CAPTURE_VARIABLES}
    result.update(ROCCO_LOCKSTEP='0', ROCCO_SEED='0', ROCCO_NO_GAMEPADS='1',
                  ROCCO_EXIT_AFTER_FRAMES='30000', ROCCO_CAPTURE_CSV=str(out/'boundaries.csv'))
    if mode in ('cpu', 'gpu'):
        result['ROCCO_SPANS_CSV'] = str(out/'cpu.csv')
    if mode == 'gpu':
        result['ROCCO_D3D_GPU_CSV'] = str(out/'gpu.csv')
    if mode == 'metal-gpu':
        result['ROCCO_CAPTURE_LABELS'] = '1'
    return result


def native_tick():
    if sys.platform == 'win32':
        tick = ctypes.c_int64()
        if not ctypes.windll.kernel32.QueryPerformanceCounter(ctypes.byref(tick)):
            raise OSError('QueryPerformanceCounter failed')
        return tick.value
    return time.monotonic_ns()


def capture(args, mode, run, provenance, observations):
    out = args.output/f'{mode}-{run}'
    out.mkdir(parents=True, exist_ok=False)
    name = {'cpu': 'cpu', 'gpu': 'gpu', 'pacing': 'ordinary', 'metal-gpu': 'ordinary'}[mode]
    binary = args.binary or args.package/f'village-{name}.exe'
    binary = binary.resolve()
    options = ['--capture-route=operation-v1' if args.operation else '--capture-route=full-v1']
    if args.operation:
        options.append('--hosted-compat')
    elif args.retina_1080:
        options.append('--retina-1080')
    env = environment(mode, out)
    manifest = dict(mode=mode, run=run, operation=args.operation, binary=str(binary), binary_sha256=digest(binary),
                    command=[str(binary), *options], package=provenance, machine=observations,
                    environment={k: env[k] for k in (*CAPTURE_VARIABLES, 'ROCCO_NO_GAMEPADS') if k in env},
                    timeout_seconds=args.timeout, performance_acceptance='open', human_acceptance='open')
    write_json(out/'run.json', manifest)
    game = present = trace = None
    try:
        with (out/'host.log').open('wb') as host_log, (out/'presentmon.log').open('wb') as present_log:
            game = subprocess.Popen([str(binary), *options], cwd=binary.parent, env=env,
                                    stdout=host_log, stderr=subprocess.STDOUT)
            if mode == 'metal-gpu':
                if sys.platform != 'darwin':
                    raise ValueError('metal-gpu requires macOS')
                command = ['xcrun', 'xctrace', 'record', '--template', 'Metal System Trace',
                           '--time-limit', f'{args.timeout}s', '--output', str(out/'gpu.trace'),
                           '--attach', str(game.pid)]
                manifest['trace_command'] = command
                trace = subprocess.Popen(command, cwd=binary.parent, stdout=present_log, stderr=subprocess.STDOUT)
                manifest['trace_pid'] = trace.pid
            manifest['launcher_pid'] = game.pid
            if mode == 'pacing' and sys.platform == 'win32':
                tool = args.package/'tools/PresentMon-2.6.0-x64.exe'
                if digest(tool) != PRESENTMON_SHA256:
                    raise ValueError('PresentMon executable checksum mismatch')
                command = [str(tool), '--process_id', str(game.pid), '--v2_metrics', '--qpc_time',
                           '--terminate_on_proc_exit', '--timed', str(args.timeout), '--terminate_after_timed',
                           '--output_file', str(out/'presentmon.csv'), '--no_console_stats']
                manifest['presentmon_launch_tick'] = native_tick()
                manifest['presentmon_command'] = command
                present = subprocess.Popen(command, cwd=args.package, stdout=present_log, stderr=subprocess.STDOUT)
                manifest['presentmon_pid'] = present.pid
            write_json(out/'run.json', manifest)
            manifest['game_exit'] = game.wait(timeout=args.timeout+30 if mode == 'metal-gpu' else args.timeout)
            if manifest['game_exit']:
                raise ValueError(f'capture process exited {manifest["game_exit"]}')
            if trace:
                if trace.poll() is None:
                    trace.send_signal(signal.SIGINT)
                manifest['trace_exit'] = trace.wait(timeout=30)
                if manifest['trace_exit'] != 0:
                    raise ValueError(f'xctrace exited {manifest["trace_exit"]}')
            if present:
                manifest['presentmon_exit'] = present.wait(timeout=30)
                if manifest['presentmon_exit']:
                    raise ValueError(f'PresentMon exited {manifest["presentmon_exit"]}')
        summary = summarise(out/'boundaries.csv', out/'cpu.csv' if mode in ('cpu', 'gpu') else None,
                            out/'gpu.csv' if mode == 'gpu' else None,
                            out/'presentmon.csv' if present else None, args.operation,
                            expected_supplement=provenance['scene_contract']['supplement_records'])
        expected = dict(cpu=(True, False), gpu=(True, True), pacing=(False, False), metal_gpu=(False, False))
        flags = (summary['metadata']['spans'], summary['metadata']['d3d_timestamps'])
        if mode != 'metal-gpu' and summary['metadata']['pass_labels']:
            raise ValueError('CPU and ordinary pacing captures require native labels disabled')
        if flags != expected[mode.replace('-', '_')]:
            raise ValueError(f'wrong executable instrumentation: {flags}')
        write_json(out/'summary.json', summary)
        if summary.get('cpu', {}).get('absent_frames'):
            raise ValueError('CPU capture is missing route frames')
        if mode == 'gpu':
            gpu = summary['gpu']
            if not gpu['gpu_frame_elapsed_ms'] or gpu['status_counts'].get('Query_Error', 0):
                raise ValueError('GPU diagnostic has no valid route samples or reported a query error')
            if gpu['missing_required_passes']:
                raise ValueError('required GPU passes are absent')
        if present:
            pacing = summary['presentmon']
            if not pacing['route_window_rows'] or not pacing['route_start_covered'] or not pacing['route_end_covered']:
                raise ValueError('PresentMon did not cover the complete route time window')
            starts = [e['frame'] for e in summary['markers'] if e['event'] == 'route_start']
            rows = {int(r['frame']): r for r in read_csv(out/'boundaries.csv')}
            if manifest['presentmon_launch_tick'] >= int(rows[min(starts)]['start_tick']):
                raise ValueError('PresentMon launched after route measurement began')
        if mode == 'metal-gpu':
            export = ['xcrun', 'xctrace', 'export', '--input', str(out/'gpu.trace')]
            subprocess.run([*export, '--toc', '--output', str(out/'trace-toc.xml')], check=True, timeout=120)
            subprocess.run([*export, '--xpath', '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]',
                            '--output', str(out/'metal-intervals.xml')], check=True, timeout=120)
            from village_metal_summary import summarise_metal
            metal = summarise_metal(out/'metal-intervals.xml', out/'boundaries.csv', binary.name, args.operation,
                                    expected_supplement=provenance['scene_contract']['supplement_records'])
            write_json(out/'metal-summary.json', metal)
            if metal['missing_frames'] or metal['missing_passes'] or metal['unlabelled_process_active_rows']:
                raise ValueError('Metal trace labels or route intervals are incomplete')
        manifest['result'] = 'operation passed' if args.operation else 'capture complete; acceptance remains open'
    except BaseException as error:
        manifest['result'] = 'failed'
        manifest['failure'] = dict(type=type(error).__name__, message=str(error))
        raise
    finally:
        for process in (game, present, trace):
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=15)
        write_json(out/'run.json', manifest)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['cpu', 'gpu', 'pacing', 'metal-gpu'], required=True)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--machine', type=Path)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--timeout', type=int, default=300)
    parser.add_argument('--operation', action='store_true')
    parser.add_argument('--retina-1080', action='store_true')
    args = parser.parse_args()
    def terminate_capture(signum, frame):
        raise SystemExit(f'capture interrupted by signal {signum}')
    signal.signal(signal.SIGTERM, terminate_capture)
    args.package, args.output = args.package.resolve(), args.output.resolve()
    if args.runs < 1 or args.runs > 3 or args.timeout < 10 or args.timeout > 900:
        parser.error('require 1 through 3 runs and a timeout from 10 through 900 seconds')
    if args.mode == 'gpu' and sys.platform != 'win32':
        parser.error('D3D GPU capture requires Windows')
    if not args.operation and args.machine is None:
        parser.error('full captures require --machine with verified hardware, power, refresh, driver, and HAGS details')
    observations = machine_observations()
    if args.machine:
        observations['recorded'] = json.loads(args.machine.read_text())
    if args.binary is None:
        provenance = verify_manifest(args.package)
    else:
        source = str(Path(__file__).resolve().parents[1])
        provenance = dict(local_binary=True, scene_contract=scene_contract(Path(source)), source_commit=command_output(['git', '-C', source, 'rev-parse', 'HEAD']),
                          source_state=command_output(['git', '-C', source, 'status', '--porcelain']),
                          association='Record the matching build log beside this binary hash; repository identity alone does not prove binary provenance.',
                          acceptance='open')
    args.output.mkdir(parents=True, exist_ok=True)
    for run in range(1, args.runs+1):
        print(capture(args, args.mode, run, provenance, observations), flush=True)


if __name__ == '__main__':
    main()
