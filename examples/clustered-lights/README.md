# 200 clustered lamps

Run `roc scripts/build.roc -- game clustered-lights` after building the host and inputs.
Start `clustered-lights.bin` from this folder.

- Hold A or D to move the camera.
- Press P to pause lamp movement.
- Press L to switch Point lights off or on.

The 200 lamps illuminate one checker floor Mesh with one Material part.
A per-Draw list of eight lights leaves most of this floor dark.
The CPU cluster grid preserves every visible lamp contribution below its density limit.

Run `python3 scripts/cluster_check.py build/bridge-check/clustered.png` from the repository root for deterministic Bridge checks.
The check saves screenshots and numeric evidence.
CI runs the check on all three graphics backends.

The floor needs no external asset tool.
Run `python3 examples/clustered-lights/source/make_floor.py` to rebuild its committed GLB.
