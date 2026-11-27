# Particles

Build the host with `roc scripts/build.roc host`.
Build the example with `roc scripts/build.roc game particles`.
Start `particles.bin` from this folder.

The left Emitter makes Alpha smoke with the built-in round sprite.
The right Emitter makes Alpha dust with a Pack image.
The centre Emitter makes Add sparks.
The back Emitter is a dust devil: its particles start on a small disc, rise, swirl about the Emitter and drift outward.
A cart drives in a circle with an exhaust Emitter in its Group.
The Group turns the exhaust velocity, and the trail stays in the world behind the cart.
The orientation sprite has a red top and a blue bottom.

- Press B to emit sparks.
- Press R to remove or restore all Emitters.
- Press U to unload the dust image.
- Press L to load the dust image again.
- Press O to show or hide the sprite orientation check.
- Press P to pause or resume the particles with `time_scale`.

Removed Emitters drain their particles.
Unloaded images omit their particles and log once.
The seed controls velocity spread.
The host never sends particle state across the game boundary.

Run `python3 scripts/particle_check.py` from the repository root for two native Bridge replays.
The check saves screenshots and compares their bytes.
It also checks initial bursts, Emitter removal, image unload, image reload, particle drain and sprite orientation.

Run `python3 examples/particles/source/make_dust.py` to rebuild the dust and orientation sprites.

The renderer reserves one buffer, one shader, two pipelines and 256 uniform slots for particles.
These reserves add to the mesh, cluster, environment and shadow budgets.

Integration validation on 2026-11-05 passed all 797 engine tests with normal and Spans builds.
All example and package Roc checks passed.
The benchmark checks and generated ABI, shader and documentation checks passed.
Two native Metal runs produced identical particle frames.
The runs checked initial bursts, paused frames, image unload, image reload, source removal and drain.
The graphics and allocator logs contained no errors.
Local artifacts are in `/tmp/rocco-particle-merged`.
The asymmetric sprite check failed before the UV correction and passed after it on native Metal.
Corrected replay artifacts are in `/tmp/rocco-particle-uv-after`.
Native OpenGL and D3D11 particle checks remain pending CI.
