# Environment lighting reference

Build the game with `roc scripts/build.roc -- game environment-lighting`.
Run the game from this folder.

The top row contains dielectric spheres.
The bottom row contains metal spheres.
Roughness increases from left to right: 0.05, 0.25, 0.5, and 1.
The white square uses an unlit material.
The scene contains no direct lights or ambient light.

Press S to change the cubemap.
Press N to remove the cubemap.
Press E to change exposure between 1 and 2.
Press U to unload the Sky Pack.
Press R to reload the Sky Pack.

Use `--1080` for a 1920 by 1080 physical window.
Use `--none` to start without a Sky.
Both options preserve the fixed comparison camera.

Run `python3 scripts/environment_check.py` from the repository root for image checks.
The check writes screenshots and numeric evidence under `build/environment-check/`.
It checks both material rows, roughness, exposure, missing resources, Pack unload, and Pack reload.
Metal, GL, and D3D use the same inputs and pixel thresholds.
The peak tolerance is 15 display code values between adjacent roughness settings.
The colour tolerance is 8 display code values between red and blue channels.
Within one backend, reload must reproduce identical PNG bytes.
Different backends can differ by two display code values on smooth surface interiors.
Polygon edges, mip interpolation, and highlights require separate inspection.

Run `python3 examples/environment-lighting/assets/source/prepare.py` to rebuild the prepared assets.
The script uses Python's standard library.
The assets contain no external source content.
