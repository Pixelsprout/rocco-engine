# Issue tracker: dex

Issues and specs for this repo live as dex tasks in `.dex/tasks.jsonl`. The file is committed. Use the `dex` CLI; do not edit the JSONL by hand.

## Conventions

- A milestone or spec is a parent task. Its description holds the "Done when" criteria and decisions.
- An implementation issue is a subtask: `dex create "name" --description "..." --parent <id>`.
- Order is expressed with `--blocked-by <ids>` and `-p <n>` (lower runs first).
- Triage state is a `Triage: <label>` line at the top of the description (see `triage-labels.md`).
- Close a task with `dex complete <id> --result "..." --commit <sha>`, then commit `.dex/tasks.jsonl` as `chore(dex): Complete the <name> task`.

## When a skill says "publish to the issue tracker"

Run `dex create` with a full description (requirements, approach, done criteria) and the right `--parent`.

## When a skill says "fetch the relevant ticket"

Run `dex show <id> --full`. Add `--expand` to see the parent milestone. `dex list` shows the open tree; the first unblocked task is next.

## Wayfinding operations

- **Map**: the parent task; its description holds Notes / Decisions so far / Fog.
- **Child ticket**: a subtask with the question in its description, and a `Type:` line (`research`/`prototype`/`grilling`/`task`).
- **Blocking**: `--blocked-by`. A ticket is unblocked when every blocker is complete.
- **Frontier**: `dex list`; open, unblocked, not in progress; lowest priority number wins.
- **Claim**: `dex start <id>` before any work.
- **Resolve**: `dex complete <id> --result "<answer>" --no-commit`, then add a one-line pointer to the parent's description with `dex edit`.
