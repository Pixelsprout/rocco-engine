import re
import unittest
from pathlib import Path

from scripts.build_shader import compact_source, compact_odin


class CompactShaderTests(unittest.TestCase):
    def test_compact_source_preserves_sampled_texture_bindings(self):
        source = '\n'.join(f'layout(binding = {slot}, std430) readonly buffer {name} {{}};' for name, slot in [('engine_points', 12), ('engine_clusters', 13), ('engine_indices', 14)])
        source += '\nlayout(binding = 12) uniform sampler2D image;'
        compact = compact_source(source)
        for slot, name in enumerate(('engine_points', 'engine_clusters', 'engine_indices')):
            self.assertIn(f'layout(binding = {slot}, std430) readonly buffer {name}', compact)
        self.assertIn('layout(binding = 12) uniform sampler2D image;', compact)

    def test_compact_source_rejects_missing_or_ambiguous_blocks(self):
        for source in ('', 'layout(binding = 12, std430) readonly buffer engine_points {};' * 2):
            with self.assertRaises(ValueError):
                compact_source(source)

    def test_generated_sources_and_reflection_use_the_same_compact_slots(self):
        text = Path('engine/shader_basic.odin').read_text()
        for slot in range(12, 15):
            self.assertEqual(text.count(f'desc.views[{slot}].storage_buffer.glsl_binding_n = {slot - 12}\n'), 6)
        sources = re.findall(r'\w+_source_glsl430 := \[\d+\]u8 \{\n(.*?)\n\}', text, re.S)
        clustered = []
        for values in sources:
            source = bytes(int(value, 16) for value in re.findall(r'0x([0-9a-f]{2})', values)).decode()
            if 'readonly buffer engine_points' in source:
                clustered.append(source)
                for slot, name in enumerate(('engine_points', 'engine_clusters', 'engine_indices')):
                    self.assertIn(f'layout(binding = {slot}, std430) readonly buffer {name}', source)
        self.assertEqual(len(clustered), 3)
        with self.assertRaises(ValueError):
            compact_odin(text)


if __name__ == '__main__':
    unittest.main()
