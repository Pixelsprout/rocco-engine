"""Waits for the CI runs of a commit and prints why a job failed.

Run from the repository root:
  python3 scripts/ci_wait.py              waits for the runs of HEAD.
  python3 scripts/ci_wait.py <run id>     waits for one run.

It prints one line each time a job changes state. When a job fails, it prints
the failed step and the end of its output, as soon as that job ends. The
other jobs can still be running. Exit status: 0 when every job passed,
1 when a job failed or was cancelled, 2 when gh failed.

It needs gh, logged in. The job logs come from a host other than
api.github.com, so a sandbox must allow that host too.
"""

import argparse
import json
import re
import subprocess
import sys
import time

TIMESTAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ?")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
STEP = "##[group]Run "
END_GROUP = "##[endgroup]"
ERROR = "##[error]"
FAILED = ("failure", "timed_out", "startup_failure")


class GhError(Exception):
    pass


def gh(*args):
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise GhError(f"gh {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def clean(line):
    return ANSI.sub("", TIMESTAMP.sub("", line.rstrip("\r")))


def failure_excerpt(log, tail=40):
    """Returns the first failed step of a job log: its name and the end of its output."""
    lines = [clean(line) for line in log.splitlines()]
    step, start = None, 0
    for i, line in enumerate(lines):
        if line.startswith(STEP):
            step, start = line[len(STEP):], i + 1
        elif line.startswith(END_GROUP):
            start = i + 1
        elif line.startswith(ERROR):
            output = [l for l in lines[start:i] if l.strip()]
            body = output[-tail:] + [line[len(ERROR):]]
            return "\n".join([f"Failed step: {step or 'unknown'}"] + ["  " + l for l in body])
    return None


def job_state(job):
    if job["status"] != "completed":
        active = [s["name"] for s in job.get("steps", []) if s.get("status") == "in_progress"]
        return job["status"] + (f" ({active[0]})" if active else "")
    return job["conclusion"] or "completed"


def runs_for_head(wait):
    sha = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    deadline = time.monotonic() + wait
    while True:
        runs = json.loads(gh("run", "list", "--commit", sha, "--json", "databaseId,workflowName"))
        if runs:
            return [(r["databaseId"], r["workflowName"]) for r in runs]
        if time.monotonic() > deadline:
            raise GhError(f"no CI run started for {sha[:7]} within {wait}s. Was it pushed?")
        time.sleep(10)


def print_failure(job):
    print(f"--- {job['name']} failed: {job['url']}", flush=True)
    try:
        log = gh("api", "--allow-escape-sequences", f"repos/{{owner}}/{{repo}}/actions/jobs/{job['databaseId']}/logs")
    except GhError as error:
        print(f"Could not read the job log. {error}", flush=True)
        return
    print(failure_excerpt(log) or "The log has no ##[error] line.", flush=True)


def wait(run_ids, interval):
    seen = {}
    reported = set()
    failed = False
    pending = dict(run_ids)
    while pending:
        for run_id, workflow in list(pending.items()):
            run = json.loads(gh("run", "view", str(run_id), "--json", "status,conclusion,url,jobs"))
            for job in run["jobs"]:
                key = (run_id, job["name"])
                state = job_state(job)
                if seen.get(key) != state:
                    seen[key] = state
                    print(f"{workflow} / {job['name']}: {state}", flush=True)
                if job["status"] == "completed" and job["conclusion"] not in ("success", "skipped"):
                    failed = True
                    # A cancelled job stopped because of another job or a newer push.
                    if job["conclusion"] in FAILED and key not in reported:
                        reported.add(key)
                        print_failure(job)
            if run["status"] == "completed":
                print(f"{workflow}: {run['conclusion']} {run['url']}", flush=True)
                failed = failed or run["conclusion"] != "success"
                del pending[run_id]
        if pending:
            time.sleep(interval)
    return failed


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run", nargs="?", type=int, help="a run id; default: the runs of HEAD")
    parser.add_argument("--interval", type=int, default=30, help="seconds between polls")
    parser.add_argument("--start-wait", type=int, default=120, help="seconds to wait for a run of HEAD to appear")
    args = parser.parse_args()
    try:
        if args.run:
            name = json.loads(gh("run", "view", str(args.run), "--json", "workflowName"))["workflowName"]
            run_ids = [(args.run, name)]
        else:
            run_ids = runs_for_head(args.start_wait)
        sys.exit(1 if wait(run_ids, args.interval) else 0)
    except GhError as error:
        print(error, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
