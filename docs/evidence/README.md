# Evidence

Each report here shows that a feature or a decision was checked.
An ADR, a guide, a research note or a dex task result links to it.
Nothing in the build reads these files.

Benchmark reference runs go in `bench/results/`, as `docs/guides/benchmarks.md` describes.
One-off checks for a feature go here.

## Rules

1. Write one Markdown report per check, named `<topic>-YYYY-MM-DD.md`.
2. In the report, state the question, the result, the machine, the commit and the command that made the result.
3. Keep a small JSON summary beside the report only when the report cites its numbers.
4. Write raw data to `docs/evidence/raw/`. Git ignores that folder. If other people need the raw data, upload it as a GitHub release asset or keep a CI artifact, and write the URL and the SHA-256 in the report.
5. Keep each file under 1 MiB. `scripts/pre-push.sh` refuses a changed file under `docs/evidence/` that is larger.
6. Link every report from the document it supports. Delete a file that nothing links to.
7. Do not edit a report after the check. A new measurement gets a new dated report.

Older reports link raw archives at commit `82b7b17`, where the files are still in git history.
