# Particles

Build the host with `roc scripts/build.roc -- host`.
Build the example with `roc scripts/build.roc -- game particles`.
Start `particles.bin` from this folder.

The left source emits Alpha smoke with the built-in round sprite.
The right source emits Alpha dust with a Pack image.
The centre source emits Add sparks.

- Press B to emit sparks.
- Press R to remove or restore all sources.
- Press U to unload the dust image.
- Press L to load the dust image again.

Removed sources drain their particles.
Unloaded images omit their particles and log once.
The seed controls velocity spread.
The host never sends particle state across the game boundary.

Run `python3 scripts/particle_check.py` from the repository root for two native Bridge replays.
The check saves screenshots and compares their bytes.
It also checks initial bursts, source removal, image unload, image reload and particle drain.

Run `python3 examples/particles/source/make_dust.py` to rebuild the original dust sprite.
