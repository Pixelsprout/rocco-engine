# rocco notes

Ideas and findings that are not in the task list yet.

## Hot reload after a Model type change

Recorded 2026-09-24. Milestone 2 supports hot reload only when the `Model`
type does not change. A changed type is undefined, because the host cannot
see the layout.

The follow-up: the platform wrappers export a layout fingerprint of `Model`,
for example `model_version_for_host`. After a reload the host compares it
with the old one. If it differs, the host drops the old box and calls `init`
again. The state is lost, but the run does not crash.

## Findings from the milestone 2 grilling

Recorded 2026-09-24, on `nightly-2026-09-12-220fd47`.

- OdinGlue fails on `U32` before it reaches `Str` or `Box`:
  `OdinGlue: no Odin spelling for u32 (type id 4)`.
- The Zig glue emits `RocStr` (24 bytes, up to 23 bytes inline, small when
  the last byte has its top bit set), `RocBox` as an opaque pointer, and
  `decref` and `incref` for every struct. A list of records that hold a `Str`
  has a 16-byte header in front of the data. Other lists and strings have an
  8-byte header. The refcount is the `isize` just before the data.
- A local package works as the camera library. `camera/main.roc` is
  `package [Camera] {}` with `import Camera`. `Camera.roc` must hold a
  nominal type: `Camera := [].{ View : {...}, look_at = ..., follow = ... }`.
  A structural alias nested in the nominal type, such as `Cam.View`, unifies
  with the platform's inline camera record. The app header adds
  `cam: "../../packages/camera/main.roc"`.
- An exposed platform module also works, but it needs `exposes [Camera]` and
  `import Camera` in the platform body. `import pf.Camera` then clashes with
  a local alias named `Camera`.
- When `roc check` fails, `roc test` still prints "All (N) tests passed" and
  exits 1. Scripts must read the exit code.

## Follow-ups from the milestone 5 grilling

Recorded 2026-09-30. Neither is milestone 5 work. Do them when a check needs
them.

- **A scripted input switch for the alloc check.** `scripts/alloc-check.sh`
  runs each game with no input, so it never sees a spawn step. A host switch
  such as `ROCCO_INPUT_SCRIPT` would replay a fixed key sequence, and the
  check could then count the allocations of a step that spawns and one that
  sweeps. Until then, Roc tests and a hand run prove runtime create and
  destroy.
- **A host allocation count on the report line.** The `alloc` line counts
  Roc allocations only. The host reserves the pairing map at init, so the
  renderer stays allocation-free up to 4096 draws by construction, not by
  measurement. A count of permanent-arena allocations per frame on the same
  line would let the alloc check assert zero.

## A settle call for same-step contact resolution

Recorded 2026-10-11, from the milestone 7 grilling. Not milestone work.

Contacts for Scene n reach step n + 1, because positions come out of `step`,
the host sees them through `view`, and Roc never asks the engine a question
mid-step. Unity and Rapier report contacts after the move in the same way,
and a game's response lands a frame later. Platformer fixes such as coyote
time and jump buffering are game-side code.

If a game ever needs the response in the same step, the escape is a second
call per fixed step:

```roc
settle : Model, List(Contact) -> Model
```

The host runs `step`, then `view`, tests the Scene, calls `settle` with the
contacts, then runs `view` again. It costs a vocabulary change and a second
extract per step, about 10 microseconds today. Roc still never calls the
engine. Do this only when the stranger check or a later game shows a feel
problem that the one-step latency causes.

## Findings from the second arc grilling

Recorded 2026-10-11, on `nightly-2026-09-27-a3ce7f1`.

- `import "level1.txt" as level1 : Str` embeds a file at compile time.
  Checked with a basic-cli app: it checks, runs and prints the file.
- App-local modules work as type modules: a headerless file whose top-level
  type matches the filename, such as `World := [].{ Model : {...} }`. The
  `module [...]` header still works but the compiler warns it is deprecated.
- The platform's required `Model` can be an alias: `Model : World.Model`.
- `roc test main.roc` runs the `expect`s of every imported module, the
  app's and the platform's.
- sokol MSAA: `sapp_desc.sample_count` on the window; pipelines inherit the
  count through `sglue_environment()`; the backend resolves in end-pass.
- Clay (nicbarker/clay): one C header, no dependencies, flexbox-like
  layout, one caller arena, no allocation per frame. `EndLayout` returns a
  sorted list of render commands and draws nothing. Text is measured by a
  callback. Official Odin bindings ship a prebuilt static library per OS and
  a script to rebuild it. zlib licence.
- GPUI is Rust, owns its renderer and windowing, has no C ABI and no
  layout-only mode. roc-gui copies its element model. The idea transfers,
  the code does not.
- roc-ray CI: five runners build the hosts, the Linux linker inputs are a
  content-addressed release with a lock file, and a release job copies the
  host archives into the target directories and runs `roc bundle` to a
  `.tar.zst` asset that apps name by URL.
- Odin `core:image/png` decodes PNG through core zlib. `core:image` also
  reads baseline JPEG, BMP, TGA and QOI.
