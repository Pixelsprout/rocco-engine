#!/usr/bin/env python3
"""Check capture dimensions and bounded simulation advances without native rendering."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from capture import advance
from scene_effects import capture, changed, ui_region


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
