# Run from the repository root: python3 -m unittest scripts/test_ci_wait.py

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ci_wait

# Trimmed from a failed macOS job of PR 47.
LOG = """\
2026-11-06T21:14:59.5800020Z ##[group]Run sh scripts/macos/build-miniaudio.sh
2026-11-06T21:14:59.5844440Z ##[endgroup]
2026-11-06T21:15:05.6000000Z == miniaudio archive
2026-11-06T21:15:05.6108760Z ##[group]Run roc scripts/build.roc all --release
2026-11-06T21:15:05.6109130Z \x1b[36;1mroc scripts/build.roc all --release\x1b[0m
2026-11-06T21:15:05.6151780Z shell: /bin/bash -e {0}
2026-11-06T21:15:05.6154610Z ##[endgroup]
2026-11-06T21:15:28.4193460Z == roc build --target=arm64mac --output=./cards.bin main.roc
2026-11-06T21:15:29.1726160Z ld64.lld: error: undefined symbol: _snprintf
2026-11-06T21:15:29.1730330Z >>> did you mean: _vsnprintf
2026-11-06T21:15:29.1752370Z
2026-11-06T21:15:29.1781060Z build: roc exited with 1
2026-11-06T21:15:29.1991920Z ##[error]Process completed with exit code 1.
2026-11-06T21:15:29.2272910Z ##[group]Run actions/upload-artifact@v4
2026-11-06T21:15:29.2275910Z ##[endgroup]
"""


class FailureExcerptTest(unittest.TestCase):
    def test_names_the_failed_step_and_keeps_its_output(self):
        self.assertEqual(
            ci_wait.failure_excerpt(LOG),
            "\n".join([
                "Failed step: roc scripts/build.roc all --release",
                "  == roc build --target=arm64mac --output=./cards.bin main.roc",
                "  ld64.lld: error: undefined symbol: _snprintf",
                "  >>> did you mean: _vsnprintf",
                "  build: roc exited with 1",
                "  Process completed with exit code 1.",
            ]),
        )

    def test_keeps_only_the_tail_of_a_long_step(self):
        excerpt = ci_wait.failure_excerpt(LOG, tail=1)
        self.assertEqual(excerpt.splitlines()[1:], ["  build: roc exited with 1", "  Process completed with exit code 1."])

    def test_returns_none_when_no_step_failed(self):
        self.assertIsNone(ci_wait.failure_excerpt(LOG.replace("##[error]", "")))


class JobStateTest(unittest.TestCase):
    def test_running_job_names_its_active_step(self):
        job = {"status": "in_progress", "conclusion": "", "steps": [
            {"name": "Build", "status": "completed"},
            {"name": "Run the games", "status": "in_progress"},
        ]}
        self.assertEqual(ci_wait.job_state(job), "in_progress (Run the games)")

    def test_finished_job_shows_its_conclusion(self):
        self.assertEqual(ci_wait.job_state({"status": "completed", "conclusion": "failure"}), "failure")


if __name__ == "__main__":
    unittest.main()
