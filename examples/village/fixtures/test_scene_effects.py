#!/usr/bin/env python3
"""Check capture dimensions and bounded simulation advances without native rendering."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch

from capture import advance
from diagnostics import compare_probe
from scene_effects import capture, changed, run, ui_region


class SceneEffectsTests(unittest.TestCase):
    def test_bounded_advances_preserve_steps_and_held_inputs(self):
        for total in (0, 24, 120, 424, 432, 565, 600):
            with self.subTest(total=total):
                bridge = Mock()
                advance(bridge, total, held=['W', 'LeftShift'])
                requests = bridge.step.call_args_list
                self.assertEqual(sum(call.args[0] for call in requests), total)
                self.assertTrue(all(0 < call.args[0] <= 24 for call in requests))
                self.assertTrue(all(call.kwargs == {'held': ['W', 'LeftShift']} for call in requests))
                bridge.screenshot.assert_not_called()

    def test_capture_records_verified_actual_dimensions(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / 'frame.png').write_bytes(b'frame')
            bridge = Mock()
            bridge.screenshot.return_value = dict(physical=[960, 540], logical=[960, 540])
            report = dict(expected_physical=[960, 540], expected_logical=[960, 540], captures={})
            with patch('scene_effects.png_rgba', return_value=(960, 540, b'')):
                self.assertEqual(len(capture(bridge, out, 'frame', report)), 64)
            self.assertEqual(report['captures']['frame'], bridge.screenshot.return_value)
            self.assertEqual(report['physical'], [960, 540])
            self.assertEqual(report['logical'], [960, 540])
            for physical, logical, png in (([1028, 749], [960, 540], (960, 540, b'')),
                                           ([960, 540], [480, 270], (960, 540, b'')),
                                           ([960, 540], [960, 540], (1920, 1080, b''))):
                with self.subTest(physical=physical, logical=logical, png=png):
                    bridge.screenshot.return_value = dict(physical=physical, logical=logical)
                    with patch('scene_effects.png_rgba', return_value=png), self.assertRaises(AssertionError):
                        capture(bridge, out, 'frame', report)

    def test_identical_canopy_pixels_fail_after_preserving_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            bridge = MagicMock()
            bridge.hello.return_value = dict(protocol=10, steps=0)
            nodes = [{'Group': {'id': n}} for n in (10, 20, 30, 40, 1, 2)] + [{'Collider': {}} for _ in range(6)]
            scene = dict(nodes=nodes, emitters=[dict(image=1, blend='Alpha')] * 40 + [dict(image=1, blend='Add')],
                         environment={}, shadow={}, camera={})
            bridge.scene.side_effect = [dict(scene=dict(nodes=[], ui=[{}])), dict(scene=scene), dict(steps=1, scene=scene)]
            connection = MagicMock()
            connection.__enter__.return_value = bridge
            process = Mock()
            process.poll.return_value = 0
            placed = [dict(id=n, mesh=1) for n in range(100, 1536)]
            placed += [dict(id=n, mesh=2) for n in range(100000, 120001)]
            with patch('scene_effects.preserve') as preserve, patch('scene_effects.scene_checkpoint') as checkpoint, \
                 patch('scene_effects.launch', return_value=(process, 1234, Mock())), \
                 patch('scene_effects.Bridge.connect', return_value=connection), \
                 patch('scene_effects.draws', return_value=placed), \
                 patch('scene_effects.capture', return_value='same-sky-only-image'):
                with self.assertRaisesRegex(AssertionError, 'canopy wind must change pixels'):
                    run(out, hosted=True, canopy_only=True)
            preserve.assert_called_once_with(out)
            checkpoint.assert_called_once_with(out, 'ready', dict(steps=1, scene=scene))
            partial = json.loads((out / 'effects-partial.json').read_text())
            self.assertEqual(partial['failure']['type'], 'AssertionError')
            self.assertEqual(partial['images']['wind-start'], partial['images']['wind-moving'])
            self.assertEqual(partial['warmup_steps'], 0)
            bridge.quit.assert_not_called()

    def test_canopy_capture_records_camera_before_screenshot(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / 'wind-start.png').write_bytes(b'frame')
            bridge = Mock()
            camera = dict(eye=dict(x=1, y=2, z=3))
            bridge.scene.return_value = dict(steps=97, scene=dict(camera=camera))
            bridge.screenshot.return_value = dict(physical=[960, 540], logical=[960, 540])
            for diagnostics in (False, True):
                report = dict(expected_physical=[960, 540], expected_logical=[960, 540],
                              captures={}, cameras={}, diagnostics=diagnostics)
                with patch('scene_effects.scene_checkpoint') as checkpoint, \
                     patch('scene_effects.png_rgba', return_value=(960, 540, b'')):
                    capture(bridge, out, 'wind-start', report)
                self.assertEqual(report['cameras']['wind-start'], camera)
                self.assertEqual(checkpoint.call_count, int(diagnostics))

    def test_early_and_later_wind_disagreement_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            probe = out / 'early'
            probe.mkdir()
            (probe / 'effects-partial.json').write_text(json.dumps(dict(images={'wind-start': 'sky', 'wind-moving': 'sky'})))
            current = dict(images={'wind-start': 'canopy1', 'wind-moving': 'canopy2'})
            comparison = compare_probe(out, probe, current)
            self.assertEqual(comparison['early_wind'], 'failed')
            self.assertEqual(comparison['later_wind'], 'passed')
            self.assertTrue(comparison['disagree'])
            self.assertEqual(json.loads((out / 'probe-comparison.json').read_text()), comparison)

    def test_changed_early_images_do_not_hide_a_native_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            probe = out / 'early'
            probe.mkdir()
            images = {'wind-start': 'canopy1', 'wind-moving': 'canopy2'}
            failure = dict(type='AssertionError', message='native graphics validation failed')
            (probe / 'effects-partial.json').write_text(json.dumps(dict(images=images, failure=failure)))
            (probe / 'effects.json').write_text(json.dumps(dict(result='passed', native_log_diagnostics=0, images=images)))
            comparison = compare_probe(out, probe, dict(images=images))
            self.assertEqual(comparison['early_wind'], 'passed')
            self.assertFalse(comparison['early_complete'])
            self.assertEqual(comparison['early_failure'], failure)

    def test_early_probe_requires_its_matching_successful_final_report(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            probe = out / 'early'
            probe.mkdir()
            images = {'wind-start': 'canopy1', 'wind-moving': 'canopy2'}
            (probe / 'effects-partial.json').write_text(json.dumps(dict(images=images)))
            self.assertFalse(compare_probe(out, probe, dict(images=images))['early_complete'])
            (probe / 'effects.json').write_text(json.dumps(dict(result='passed', native_log_diagnostics=0, images=images)))
            self.assertTrue(compare_probe(out, probe, dict(images=images))['early_complete'])
            (probe / 'effects.json').write_text(json.dumps(dict(result='passed', native_log_diagnostics=0, images={'wind-start': 'other1', 'wind-moving': 'other2'})))
            self.assertFalse(compare_probe(out, probe, dict(images=images))['early_complete'])

    def test_comparison_rejects_a_different_png_size(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / 'a.png').write_bytes(b'a')
            (out / 'b.png').write_bytes(b'b')
            with patch('scene_effects.png_rgba', side_effect=[(960, 540, b''), (1920, 1080, b'')]):
                with self.assertRaises(AssertionError):
                    changed(out, 'a', 'b', [960, 540])

    def test_ui_region_uses_physical_scale_and_logical_panel_bounds(self):
        self.assertEqual(ui_region([960, 540], [960, 540]), (40, 40, 250, 75))
        self.assertEqual(ui_region([1920, 1080], [1920, 1080]), (40, 40, 250, 75))
        self.assertEqual(ui_region([1920, 1080], [960, 540]), (80, 80, 500, 150))


if __name__ == '__main__':
    unittest.main()
