import unittest

from scripts.gpu_timing_summary import summarise


class SummaryTests(unittest.TestCase):
    def test_missing_disjoint_and_absent_frames_remain_visible(self):
        rows = [dict(frame='1', scope='frame', status='Valid', gpu_ms='10'),
                dict(frame='1', scope='pass', pass_index='0', **{'pass': 'Shadow'}, status='Valid', gpu_ms='2'),
                dict(frame='1', scope='pass', pass_index='1', **{'pass': 'Shadow'}, status='Valid', gpu_ms='3'),
                dict(frame='2', scope='frame', status='Disjoint', gpu_ms=''),
                dict(frame='3', scope='frame', status='Missing_Busy', gpu_ms=''),
                dict(frame='4', scope='frame', status='Valid', gpu_ms='20')]
        result = summarise(rows, 1, 5)
        self.assertEqual(result['excluded_frames'], 3)
        self.assertEqual(result['status_counts'], {'Absent': 1, 'Disjoint': 1, 'Missing_Busy': 1, 'Valid': 2})
        self.assertEqual(result['gpu_frame_elapsed_ms']['p95'], 20)
        shadows = result['gpu_pass_totals_per_frame_ms']['Shadow']
        self.assertEqual((shadows['samples'], shadows['p95']), (1, 5))

    def test_invalid_or_duplicate_frames_do_not_produce_a_summary(self):
        row = dict(frame='1', scope='frame', status='Valid', gpu_ms='nan')
        with self.assertRaises(ValueError):
            summarise([row], 1, 1)
        row['gpu_ms'] = '1'
        with self.assertRaises(ValueError):
            summarise([row, row], 1, 1)


if __name__ == '__main__':
    unittest.main()
