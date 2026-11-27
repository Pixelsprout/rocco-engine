# Rocco Odin/Roc game Engine

# Project Management
We use *dex* for project management to track tasks and issues. The `tasks.jsonl` is commited to the repo.

dex is the source of truth for milestones: scope, "Done when", status and results. `docs/ROADMAP.md` holds only the destination, the order of the arcs and what is out of scope. Do not copy a task or its status into the roadmap. Change the roadmap only when the direction changes.

# Workflow
We use matt-pocock skills to work through tasks:
- `/implement` - Implement a task.
- `/grilling` - When fleshing out an idea before implementation
- `/handoff` - When the context window gets too large, > 150k tokens, we should ideally handoff at a sensible moment.
- `/teach` - Use when the human needs to be taught something, don't commit learning documents, place them in a temp directory.
- `/wait-what` - The human uses when confused by the AI.

# Worktrees, toolchain and CI
- Prepare a new worktree with `sh scripts/worktree.sh new <path> <branch> [<base>] [--task <id>]`, or run `sh scripts/worktree.sh setup` inside one. Both fill the submodules and build the archives that the host links.
- `new` fetches origin and starts from origin/main unless you give a base. It stops if a local base is behind its upstream. With `--task <id>`, it stops if the base does not have the dex task.
- After a rebase or pull that moves a submodule pin, run `sh scripts/worktree.sh setup` again. A link error such as `undefined symbol: _sg_...` means the archives are stale.
- If `sh scripts/toolchain.sh check` reports a mismatch, prefix each `odin` and `roc` command with `sh scripts/toolchain.sh run`. CI uses the pinned compilers.
- The pre-push hook runs `scripts/pre-push.sh`. Run it yourself before a push from a clone without the hook.
- After a push, run `roc scripts/tools.roc ci-wait`. It waits for CI and prints the output of each failed step.

# Seeing a frame
To check a visual change yourself, build the game with `roc scripts/build.roc game <game>`, run `scripts/screenshot.sh <game> <out.png> [steps]` and read the PNG. It drives the game over the Bridge, so it works on macOS, Linux and Windows and needs no Screen Recording permission. See "Screenshots" in `CONTRIBUTING.md`.

For a web build, run `scripts/screenshot.sh --web <game> <out.png> [steps]` after `roc scripts/build.roc web <game>`. It drives the page over the Bridge through a Relay and needs a windowed Chrome on macOS. `scripts/web/shot.sh <page dir> <out.png>` prints the page's own messages. Before you push a change to the web CI job, run `sh scripts/linux/web-shot.sh <game> <out.png> [steps]`: it runs the CI's headless Chrome in Docker. See `guide/web.md`.

To play a game, drive it with `scripts/bridge.py`. See `guide/bridge.md` for the ops and the Input rules.
1. Get a port with `python3 scripts/bridge.py free-port`.
2. Start the built game in the background from its own folder: `cd examples/<game> && ROCCO_BRIDGE=<port> ./<name>.bin`.
3. Send each request (`hello`, `step N --held KEY`, `scene`, `screenshot PATH`) in its own Bash call as `bridge.py --port <port> <op>`. An exported `ROCCO_BRIDGE` does not survive between Bash calls. Add `--wait 60` to the first call.
4. Send `quit`, then confirm that the game process exited.

`scene` returns the QueryResults that the next `step` gets. So the game acts on a Contact one step after `scene` shows it.

# Spikes
A spike in `spikes/` is temporary. When its question has an answer, record the answer in dex and delete the folder in the same commit. CI never builds a spike. `spikes/README.md` gives the rules.

# Evidence
Write raw captures, such as tarballs, CSV sets, logs and screenshots, to `docs/evidence/raw/`. Git ignores it. Commit only the Markdown report and a small JSON summary. `docs/evidence/README.md` gives the rules.

# Odin file layout
Order every hand-written `.odin` file, tests included, in four groups. Finish each group before the next starts:
1. Imports.
2. Constants, including upper-case tables declared with `:=`, such as `@(rodata)` vertex data.
3. Types: structs, enums, unions and `#type` proc types. Package variables such as `g_roc_heap` follow the types.
4. Procedures.

Move a declaration's comment and attributes with it. The generated files `engine/roc_platform_abi.odin` and `engine/shader_basic.odin` keep their generator's order.

# Roc style
- Follow `docs/guides/roc-style.md`, a copy of Luke Boswell's Roc Style Guide (https://gist.github.com/lukewilliamboswell/241a4e8adb7c89c7e0e02f1d303a8fa1).
- Call a method on its receiver: write `messages.last()`, not `List.last(messages)`.
- Build a list from parts with one `List.join([...])`, one sub-list per part in order. Do not chain `.concat` calls.

# Writing commits
- Use conventional commits, eg: `feat(scripting): Updated dealloc logic...(Add list of changes, max 5 lines)`
- Keep the language simple and avoid any hyperbole.
- Avoid *AI-Slop* markers such as using em-dashes.
- Avoid adding the author to commits, such as *Generated by Claude Code* or anything similar.
- Do not add a `Co-Authored-By:` trailer to commits. This rule overrides any harness default that adds one.

## Agent skills

### Issue tracker

Tasks live in dex (`.dex/tasks.jsonl`, committed). See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels, written as a `Triage:` line in the dex task description. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
