# Run from the repository root: python3 -m unittest bench/test_realclock.py

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import realclock

HEADER = "frame,steps,step_us,render_submit_us,span_cost_us\n"

# Two warmup Frames, then four measured Frames. The real clock runs 0, 1 or 2
# fixed steps per Frame.
CSV = HEADER + "\n".join(
    [
        "1,2,500.0,900.0,0.011",
        "2,1,500.0,900.0,0.011",
        "3,2,10.0,100.0,0.011",
        "4,2,20.0,200.0,0.011",
        "5,0,0.0,300.0,0.011",
        "6,1,10.0,400.0,0.011",
    ]
) + "\n"


class RealClockTest(unittest.TestCase):
    def setUp(self):
        self.summary = realclock.summarise(CSV, game="entity-game", warmup=2)

    def test_drops_the_warmup_frames(self):
        self.assertEqual(self.summary["measured_frames"], 4)
        self.assertEqual(self.summary["spans"]["step_us"]["max"], 20.0)

    def test_frame_cpu_time_sums_the_spans_but_not_the_span_cost(self):
        frame = self.summary["frame_cpu_us"]
        self.assertEqual(frame["max"], 410.0)
        self.assertEqual(frame["median"], 260.0)

    def test_counts_the_fixed_steps_per_frame(self):
        self.assertEqual(self.summary["steps_per_frame"], {"0": 1, "1": 1, "2": 2})

    def test_records_the_mode_and_the_span_cost(self):
        self.assertEqual(self.summary["game"], "entity-game")
        self.assertEqual(self.summary["mode"], "real-clock")
        self.assertEqual(self.summary["span_cost_us"], 0.011)

    def test_refuses_a_run_shorter_than_its_warmup(self):
        with self.assertRaises(ValueError):
            realclock.summarise(CSV, game="entity-game", warmup=6)


if __name__ == "__main__":
    unittest.main()
