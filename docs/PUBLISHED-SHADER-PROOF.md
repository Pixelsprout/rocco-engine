# Published shader authoring proof

The independent evidence review found no blocker in the reviewed scope.
The reviewer changed no repository files and ran no native builds.

[CI 41994811623](https://github.com/Pixelsprout/rocco-engine/actions/runs/41994811623) passed all eight jobs.
The pull request head is `b0b0a26d149269154e95ebbff2225b793a444979`.
The tested merge commit is `2b9f159546cbf954eb4eb995bb2ac420d0b3cf40`.
GitHub records both `b0b0a26` and main commit `6a436bf` as its parents.
The candidate records the tested merge commit correctly.

[Candidate SDK 13401395248](https://github.com/Pixelsprout/rocco-engine/actions/runs/41994811623/artifacts/13401395248) has SHA-256 `f9e8a28e01ca077855abc4c778a7a19823345e6591f324bbf2e944715d151d3b`.
The downloaded archive matches GitHub's digest.
All seven inner checksums match.
The fixture and five SDK archives contain no Odin source or Git checkout.
Each backend's 101 extracted SDK files match the published candidate bytes.
CI captured ordinary release hosts before Spans benchmarks.
Linux rebuilt its ordinary release hosts before capture.

| Native proof | Result | Checks | Artifact |
| --- | --- | ---: | --- |
| Metal | Passed | 172 | [13399874963](https://github.com/Pixelsprout/rocco-engine/actions/runs/41994811623/artifacts/13399874963) |
| GL 4.3 | Passed | 172 | [13401365955](https://github.com/Pixelsprout/rocco-engine/actions/runs/41994811623/artifacts/13401365955) |
| D3D11 | Passed | 173 | [13399954760](https://github.com/Pixelsprout/rocco-engine/actions/runs/41994811623/artifacts/13399954760) |

All external jobs omit checkout and Odin installation.
Each proof confirms Odin remains absent before and after compilation.
Windows links with `LIB` unset.
All proofs record the same candidate ID, digest, run, and tested commit.
They use Roc `nightly-2026-10-11-7d256b9` and checksum-pinned shader compiler `11d0cf678105d614d675e6d9bd2aaf3eeff12f8c`.
The JSON record retains platform download URLs, executable hashes, compiler hashes, and build commands.

Independent PNG checks confirm deterministic wind and distinct simulation poses.
Live Surface edits change 14,288 GL pixels and 14,289 Metal/D3D11 pixels.
Invalid source retains the changed valid frame.
Source correction restores the baseline exactly.
Post edits change 1,895 GL pixels and 1,897 Metal/D3D11 pixels.
Post correction restores the baseline exactly.
Invalid packages and changed interfaces retain the valid frame.
The rebuilt game accepts the changed interface after restart.
Both outline policies use the same selected Group.
Their images differ by 886 pixels on every backend.
The policy toggle restores the baseline exactly.
Visual inspection confirms tree cutouts, foliage shadows, the separate marker, wall occlusion, and both outline policies.
The fixture checks typed Bark/Leaves helpers, imported materials, Pack unload, first-load failure, and recovery.

[Windows Bridge artifact 13400079887](https://github.com/Pixelsprout/rocco-engine/actions/runs/41994811623/artifacts/13400079887) matches its published digest.
Valid, missing, and invalid first-load paths passed live reload checks.
The native proof passed 24 compatible swaps, 24 failed pipeline candidates, and two failed program candidates.
It covered 63 Surface pipeline keys and two Post locations.
Both final resource reports contain zero shaders, pipelines, samplers, images, views, and retained CPU bytes.
The native failure harness deliberately produced 48 pipeline-pool errors and eight shader-compilation errors.
Its log contains no panic or validation failure.
The three live reload game logs contain no graphics error, panic, or validation failure.
The Windows shader suite ran 38 tests successfully, with one skip.
The native Windows publication tests apply on `win32`.

Each backend's 31 external logs contains no graphics error, panic, or validation failure.
D3D11 emits X3556 integer-division and X4000 `sun_visibility` compiler warnings.
Expected shader rejection diagnostics appear during deliberate failures.
Earlier local unpublished proof does not satisfy this published gate.
These CI results establish compatibility and authoring evidence, not reference-PC performance or final village acceptance.
Independent review also verified D3D11 timing and world-direction evidence.

The complete record is [the published proof JSON](evidence/published-shader-authoring-2026-11-05.json).
The original downloaded archives and selected JSON, logs, and PNGs remain in `/tmp/rocco-candidate-review/`.
