import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tour_content


class MarkerTest(unittest.TestCase):
    def test_balanced_skip_and_tour_only_blocks_pass(self):
        page = '\n'.join([
            '# 1. A window',
            '<!-- tour:skip -->',
            '## Run the game',
            '```sh',
            'roc main.roc',
            '```',
            '<!-- /tour:skip -->',
            '<!-- tour-only',
            'Press Run.',
            '-->',
            '',
        ])
        self.assertEqual(tour_content.marker_problems(page, 'p.md'), [])

    def test_a_skip_block_that_never_closes_fails(self):
        page = 'a\n<!-- tour:skip -->\nb\n'
        self.assertEqual(tour_content.marker_problems(page, 'p.md'),
                         ['p.md:2 opens a tour:skip block that never closes'])

    def test_a_close_with_no_open_block_fails(self):
        self.assertEqual(tour_content.marker_problems('<!-- /tour:skip -->\n', 'p.md'),
                         ['p.md:1 closes a tour:skip block that is not open'])

    def test_a_block_inside_a_block_fails(self):
        page = '<!-- tour:skip -->\n<!-- tour-only\nx\n-->\n<!-- /tour:skip -->\n'
        self.assertIn('p.md:2 opens a tour-only block inside the tour:skip block from line 1',
                      tour_content.marker_problems(page, 'p.md'))

    def test_a_one_line_tour_only_marker_fails(self):
        self.assertEqual(tour_content.marker_problems('<!-- tour-only -->\n', 'p.md'),
                         ['p.md:1 has the unknown tour marker <!-- tour-only -->'])

    def test_markers_inside_a_fence_are_text(self):
        page = '```md\n<!-- tour:skip -->\n```\n'
        self.assertEqual(tour_content.marker_problems(page, 'p.md'), [])


class DesktopOnlyTest(unittest.TestCase):
    def test_a_shell_block_outside_a_skip_block_fails(self):
        page = 'Run:\n\n```sh\nroc main.roc\n```\n'
        self.assertEqual(tour_content.desktop_problems(page, 'p.md'),
                         ['p.md:3 has a sh block outside a tour:skip block'])

    def test_a_desktop_only_section_outside_a_skip_block_fails(self):
        for heading in ['## Before you start', '## Run the game', '## Play the game',
                        '## Test the calls', '## Get the mesh file']:
            self.assertEqual(tour_content.desktop_problems(heading + '\n', 'p.md'),
                             [f'p.md:1 has the desktop-only section "{heading[3:]}" outside a tour:skip block'])

    def test_desktop_only_parts_inside_a_skip_block_pass(self):
        page = '<!-- tour:skip -->\n## Run the game\n\n```sh\nroc main.roc\n```\n<!-- /tour:skip -->\n## The Model\n'
        self.assertEqual(tour_content.desktop_problems(page, 'p.md'), [])


HEADER = ('app [init, launch, loaded, step, view] { mesh: "../../../packages/mesh/main.roc", '
          'pf: platform "../../../platform/main.roc", roc: "nightly" }\n')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


class StepTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        for step in ['00-start', '01-window', '02-character']:
            self.source(step, HEADER)
        for page in ['01-window', '02-character']:
            write(os.path.join(self.root, 'guide', 'tutorial', page + '.md'), '# Page\n')

    def tearDown(self):
        self.tmp.cleanup()

    def source(self, step, text):
        write(os.path.join(self.root, 'examples', 'tutorial', step, 'main.roc'), text)

    def test_complete_steps_pass(self):
        self.assertEqual(tour_content.step_problems(self.root), [])

    def test_the_step_1_stub_is_required(self):
        os.remove(os.path.join(self.root, 'examples', 'tutorial', '00-start', 'main.roc'))
        self.assertEqual(tour_content.step_problems(self.root),
                         ['examples/tutorial/00-start/main.roc is missing: it is the starting source of step 1'])

    def test_each_page_needs_its_answer(self):
        write(os.path.join(self.root, 'guide', 'tutorial', '03-moving.md'), '# Page\n')
        self.assertEqual(tour_content.step_problems(self.root),
                         ['examples/tutorial/03-moving/main.roc is missing: it is the answer of guide/tutorial/03-moving.md'])

    def test_a_shaders_json_in_a_step_fails(self):
        write(os.path.join(self.root, 'examples', 'tutorial', '00-start', 'shaders.json'), '{}')
        write(os.path.join(self.root, 'examples', 'tutorial', '02-character', 'assets', 'shaders.json'), '{}')
        self.assertEqual(tour_content.step_problems(self.root), [
            'examples/tutorial/00-start/shaders.json: a Tour step cannot use shader packs',
            'examples/tutorial/02-character/assets/shaders.json: a Tour step cannot use shader packs',
        ])

    def test_a_header_path_with_no_release_url_fails(self):
        self.source('01-window', HEADER.replace('packages/mesh', 'packages/extra'))
        self.assertEqual(tour_content.step_problems(self.root), [
            'examples/tutorial/01-window/main.roc: the header names "../../../packages/extra/main.roc", '
            'which has no release URL marker',
        ])

    def test_page_problems_name_the_page(self):
        write(os.path.join(self.root, 'guide', 'tutorial', '01-window.md'), '<!-- tour:skip -->\n## Run the game\n')
        self.assertEqual(tour_content.step_problems(self.root),
                         ['guide/tutorial/01-window.md:1 opens a tour:skip block that never closes'])


class RepoTest(unittest.TestCase):
    def test_the_tour_content_of_this_checkout_passes(self):
        self.assertEqual(tour_content.step_problems(tour_content.ROOT), [])


if __name__ == '__main__':
    unittest.main()
