import csv
import json
from pathlib import Path
import sys
import tempfile
from unittest import mock
import zipfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import village_capture as runner
import village_capture_summary as capture
import village_metal_summary as metal
from village_bench_capture import SIZES, sweep_order
import package_village_capture as package


def boundary(frame, before, after):
    return dict(frame=str(frame), steps=str(after-before), step_before=str(before), step_after=str(after),
                prev_step=str(max(0, after-1)), alpha='0.5', width='960', height='540', dpi='1',
                start_tick=str(frame*1000), commit_start_tick=str(frame*1000+50),
                commit_end_tick=str(frame*1000+100), delta_seconds='0.016', applied_seconds='0.016',
                clamped_seconds='0', fov_y='1.3089969', pass_count='1')


def gpu_row(frame, status='Valid', scope='frame', kind='', index=-1, value='2'):
    valid = status == 'Valid'
    return dict(frame=str(frame), scope=scope, pass_index=str(index), **{'pass': kind}, status=status,
                frequency_hz='1000' if valid else '', start_tick='1' if valid else '',
                end_tick='3' if valid else '', gpu_ms=value if valid else '')


def fixture(path, supplement=0):
    rows = [boundary(i+1, i*16, (i+1)*16) for i in range(31)]
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    meta = dict(version=1, frames=31, frequency_hz=1000000, error='', seed=0, mode='Real_Clock',
                msaa=4, shadow_map=2048, shadow_cascades=2, step_hz=120, spans=False,
                d3d_timestamps=False, source_draws=1436, field_draws=21000, supplement_draws=supplement, other_draws=1, post_count=2,
                emitter_count=41, selected_groups=[20], clock='QueryPerformanceCounter', pass_labels=True)
    Path(str(path)+'.meta.json').write_text(json.dumps(meta))
    events = [('ready', 0, 1, 0, 1), ('warmup_start', 0, 1, 0, 1),
              ('warmup_end', 0, 120, 0, 121), ('route_start', 1, 1, 0, 121),
              ('route_end', 1, 120, 0, 241), ('route_start', 2, 1, 0, 241),
              ('route_end', 2, 120, 0, 361), ('complete', 2, 120, 0, 481)]
    records = [dict(frame=(step-1)//16+1, step=step,
                    commands=[dict(Tell=dict(port='village.capture.v1',
                                             msg=f'{event}|{cycle}|{count}|{waypoint}|operation'))])
               for event, cycle, count, waypoint, step in events]
    effective = dict(density=22000, distance=65, width=2, field_casts_shadow=False, controls=False,
                     **{name: True for name in capture.ENABLED_SETTINGS})
    records[0]['commands'].append(dict(Tell=dict(port='village.capture.settings.v1', msg=json.dumps(effective))))
    Path(str(path)+'.commands.jsonl').write_text('\n'.join(json.dumps(row) for row in records)+'\n')
    return meta


class BoundaryTests(unittest.TestCase):
    def test_mixed_and_zero_step_frames_keep_measured_interpolation(self):
        rows = [boundary(1, 0, 2), boundary(2, 2, 5), boundary(3, 5, 5), boundary(4, 5, 6)]
        result = capture.membership(rows, [dict(cycle=1, first_step=3, end_step_exclusive=5)])
        self.assertEqual([r['included'] for r in result], [False, True, True, False])
        self.assertEqual([r['mixed'] for r in result], [False, True, True, False])
        self.assertEqual([r['measured_steps'] for r in result], [0, 2, 0, 0])

    def test_one_render_can_include_both_route_cycles(self):
        result = capture.membership([boundary(1, 2, 7)], [dict(cycle=1, first_step=3, end_step_exclusive=5),
                                                       dict(cycle=2, first_step=5, end_step_exclusive=7)])
        self.assertEqual(result[0]['cycles'], [1, 2])
        self.assertTrue(result[0]['mixed'])
        self.assertEqual(result[0]['measured_steps'], 4)

    def test_observed_warmup_and_complete_markers_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'boundaries.csv'
            fixture(path)
            report = capture.summarise(path, operation=True)
            self.assertEqual(report['routes'][0]['first_step'], 121)
            self.assertEqual(report['routes'][-1]['end_step_exclusive'], 361)
            self.assertTrue(report['mixed_frames'])
            self.assertEqual(report['measured_fixed_steps'], 240)
            self.assertEqual(report['evidence'], 'operation only')
            with self.assertRaises(ValueError):
                capture.summarise(path)
            records = Path(str(path)+'.commands.jsonl')
            records.write_text('\n'.join(records.read_text().splitlines()[:-1])+'\n')
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                capture.summarise(path, operation=True)

    def test_reduced_density_cannot_certify_the_full_route(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'boundaries.csv'
            fixture(path)
            records = Path(str(path)+'.commands.jsonl')
            lines = records.read_text().splitlines()
            first = json.loads(lines[0])
            value = json.loads(first['commands'][1]['Tell']['msg'])
            value['density'] = 1000
            first['commands'][1]['Tell']['msg'] = json.dumps(value)
            lines[0] = json.dumps(first)
            records.write_text('\n'.join(lines)+'\n')
            with self.assertRaisesRegex(ValueError, 'effective scene settings'):
                capture.summarise(path, operation=True)

    def test_supplement_count_stays_separate_and_matches_frozen_scene(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'boundaries.csv'
            meta = fixture(path, supplement=123)
            report = capture.summarise(path, operation=True, expected_supplement=123)
            self.assertEqual(report['metadata']['source_draws'], 1436)
            self.assertEqual(report['metadata']['field_draws'], 21000)
            self.assertEqual(report['metadata']['supplement_draws'], 123)
            self.assertEqual(report['expected_supplement_draws'], 123)
            with self.assertRaisesRegex(ValueError, 'frozen scene contract'):
                capture.summarise(path, operation=True, expected_supplement=0)
            meta['field_draws'] = 22123
            Path(str(path)+'.meta.json').write_text(json.dumps(meta))
            with self.assertRaisesRegex(ValueError, 'field'):
                capture.summarise(path, operation=True, expected_supplement=123)

    def test_markers_must_belong_to_the_actual_frame(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'boundaries.csv'
            fixture(path)
            records = Path(str(path)+'.commands.jsonl')
            lines = records.read_text().splitlines()
            first = json.loads(lines[0])
            first['frame'] = 2
            lines[0] = json.dumps(first)
            records.write_text('\n'.join(lines)+'\n')
            with self.assertRaisesRegex(ValueError, 'recorded frame'):
                capture.summarise(path, operation=True)

    def test_wrong_selected_group_fails_completeness(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'boundaries.csv'
            meta = fixture(path)
            meta['selected_groups'] = []
            Path(str(path)+'.meta.json').write_text(json.dumps(meta))
            with self.assertRaisesRegex(ValueError, 'Group 20'):
                capture.summarise(path, operation=True)


class MeasurementTests(unittest.TestCase):
    def test_gpu_exclusions_and_absent_samples_never_become_zero(self):
        statuses = sorted(capture.GPU_STATUSES-{'Valid'})
        rows = [gpu_row(1), *[gpu_row(i+2, status) for i, status in enumerate(statuses)]]
        report = capture.gpu_summary(rows, range(1, 9))
        self.assertEqual(report['gpu_frame_elapsed_ms']['samples'], 1)
        self.assertEqual(report['gpu_frame_elapsed_ms']['p95'], 2)
        self.assertEqual(report['status_counts']['Absent'], 1)
        for status in statuses:
            self.assertEqual(report['status_counts'][status], 1)
        self.assertEqual(report['excluded_frames'], 7)
        self.assertIn('1', report['missing_required_passes'])

    def test_invalid_pass_numeric_values_and_pending_status_fail(self):
        row = gpu_row(1, 'Disjoint', 'pass', 'Main', 0)
        row['gpu_ms'] = '0'
        with self.assertRaisesRegex(ValueError, 'numeric'):
            capture.gpu_summary([gpu_row(1, 'Disjoint'), row], [1])
        with self.assertRaisesRegex(ValueError, 'unfinished'):
            capture.gpu_summary([gpu_row(1, 'Pending')], [1])

    def test_repeated_pass_kinds_sum_per_frame_and_keep_sample_count(self):
        rows = [gpu_row(1), gpu_row(1, scope='pass', kind='Shadow', index=0, value='1'),
                gpu_row(1, scope='pass', kind='Shadow', index=1, value='2'), gpu_row(2)]
        report = capture.gpu_summary(rows, [1, 2])
        self.assertEqual(report['pass_totals_per_frame_ms']['Shadow']['p95'], 3)
        self.assertEqual(report['pass_totals_per_frame_ms']['Shadow']['samples'], 1)
        with self.assertRaisesRegex(ValueError, 'duplicate GPU pass'):
            capture.gpu_summary([*rows, rows[1]], [1, 2])

    def test_cpu_keeps_catchup_zero_steps_and_missing_frames(self):
        rows = [dict(frame='1', steps='0', step_us='0', commit_us='1000', span_cost_us='1'),
                dict(frame='2', steps='3', step_us='3000', commit_us='1000', span_cost_us='1')]
        report = capture.cpu_summary(rows, [1, 2, 3])
        self.assertEqual(report['absent_frames'], [3])
        self.assertEqual(report['steps_per_frame'], {0: 1, 3: 1})
        self.assertEqual(report['frame_cpu_work_ms']['p95'], 4)

    def test_presentmon_keeps_na_and_uses_qpc_window(self):
        rows = [dict(CPUStartQPC=str(tick), FrameTime='16.7', DisplayedTime='NA' if tick == 1100 else '16.7',
                     GPUBusy='3', GPUTime='5', GPUWait='2', SwapChainAddress='0x1')
                for tick in (900, 1100, 2100, 2200)]
        report = capture.presentmon_summary(rows, [boundary(1, 0, 1), boundary(2, 1, 2)], 1000)
        self.assertEqual(report['route_window_rows'], 2)
        self.assertEqual(report['outside_window_rows'], 2)
        self.assertEqual(report['not_displayed_rows'], 1)
        self.assertEqual(report['missing']['DisplayedTime'], 1)
        self.assertTrue(report['route_start_covered'])
        self.assertTrue(report['route_end_covered'])

    def test_metal_intervals_use_labels_instead_of_trace_frame_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'metal.xml'
            def row(start, duration):
                values = [str(start), str(duration), '', '9999', '', '', '', 'Active', '', '', '']
                tags = [f'<v fmt="rocco.frame=7.pass=0.kind=main">{v}</v>' if i == 4
                        else f'<v fmt="village.bin (12)">{v}</v>' if i == 10 else f'<v>{v}</v>'
                        for i, v in enumerate(values)]
                return '<row>'+''.join(tags)+'</row>'
            path.write_text('<root>'+row(0, 10)+row(5, 10)+'</root>')
            frames, kinds, missing = metal.intervals(path, 'village.bin')
            self.assertEqual(set(frames), {7})
            self.assertEqual(kinds[(7, 0)], 'main')
            self.assertEqual(missing, 0)
            self.assertEqual(metal.union_ms(frames[7][0]), 15/1e6)


class RunnerTests(unittest.TestCase):
    def test_capture_environment_is_explicit_and_instrumentation_is_separate(self):
        env = runner.environment('pacing', Path('/tmp/example'))
        self.assertEqual(env['ROCCO_LOCKSTEP'], '0')
        self.assertNotIn('ROCCO_BRIDGE', env)
        self.assertNotIn('ROCCO_SPANS_CSV', env)
        self.assertNotIn('ROCCO_D3D_GPU_CSV', env)
        self.assertNotIn('ROCCO_CAPTURE_LABELS', env)
        self.assertNotIn('ROCCO_CAPTURE_LABELS', runner.environment('cpu', Path('/tmp/example')))
        self.assertEqual(runner.environment('metal-gpu', Path('/tmp/example'))['ROCCO_CAPTURE_LABELS'], '1')
        gpu = runner.environment('gpu', Path('/tmp/example'))
        self.assertIn('ROCCO_SPANS_CSV', gpu)
        self.assertIn('ROCCO_D3D_GPU_CSV', gpu)

    def test_package_has_named_executables_and_one_shared_assets_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)/'source'
            for path in ['examples/village/assets/meshes/tree.glb', 'docs/VILLAGE-CAPTURE.md',
                         'examples/village/source/LICENSE_CC0_Quaternius.txt', 'examples/village/source/UPSTREAM-README.md',
                         *['scripts/'+name for name in ['village_capture.py', 'village_capture_summary.py',
                                                        'village_metal_summary.py', 'village_bench_capture.py']],
                         *['scripts/village-capture/'+name for name in ['Capture-Village.ps1', 'Capture-BenchSweeps.ps1',
                                                                        'Summarize-VillageCapture.ps1', 'machine.example.json']]]:
                target = root/path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('fixture')
            (root/'examples/village/source/rubble-manifest.json').write_text(json.dumps(dict(count=123, id_range=[200000, 200160])))
            presentmon = Path(directory)/'presentmon.exe'
            presentmon.write_bytes(b'presentmon fixture')
            archive = Path(directory)/'python.zip'
            with zipfile.ZipFile(archive, 'w') as stream:
                stream.writestr('python.exe', b'python fixture')
            builds = {}
            for name in ['village-ordinary.exe', 'village-cpu.exe', 'village-gpu.exe', 'bench-draws.exe', 'bench-mixed.exe']:
                binary = Path(directory)/name
                binary.write_bytes(name.encode())
                builds[name] = binary
            output = Path(directory)/'package'
            with mock.patch.object(package, 'ROOT', root), \
                 mock.patch.object(package, 'PRESENTMON_SHA256', package.digest(presentmon)), \
                 mock.patch.object(package.urllib.request, 'urlretrieve', side_effect=lambda url, path: Path(path).write_text('licence')):
                package.package_files(output, presentmon, archive, 'source-commit', builds, {}, [])
            manifest = runner.verify_manifest(output)
            self.assertEqual(manifest['source_commit'], 'source-commit')
            self.assertEqual(manifest['scene_contract']['source_assets'], 93)
            self.assertEqual(manifest['scene_contract']['source_records'], 1436)
            self.assertEqual(manifest['scene_contract']['field_records'], 22000)
            self.assertEqual(manifest['scene_contract']['supplement_records'], 123)
            self.assertEqual(manifest['scene_contract']['supplement_manifest_sha256'], runner.digest(root/'examples/village/source/rubble-manifest.json'))
            self.assertEqual([name for name in manifest['files'] if name.startswith('assets/')], ['assets/meshes/tree.glb'])
            self.assertTrue(all((output/name).is_file() for name in builds))
            self.assertEqual((output/'tools/python/python312._pth').read_text(), 'python312.zip\n.\n../../scripts\n')

    def test_full_sweep_keeps_all_sizes_processes_and_the_recorded_order(self):
        order = sweep_order(7)
        self.assertEqual(len(order), 90)
        self.assertEqual(set(order), {(game, n, p) for game in ('draws', 'mixed') for n in SIZES for p in range(1, 6)})
        self.assertEqual(order, sweep_order(7))
        self.assertNotEqual(order, sweep_order(8))
