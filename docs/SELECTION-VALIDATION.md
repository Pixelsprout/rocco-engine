# Selected Group validation

Date: 2026-11-05.
Local backend: Metal.
The complete native matrix passed at Off, X2, X4, and X8.
[Metal evidence](evidence/selection/metal.json) records the binary and pixel checksums.
GL and D3D11 acceptance remains pending until the native CI jobs pass.

`Group.selected` supplies generic membership only.
All descendant Draws contribute to one coverage and nearest-depth union.
The game-authored `Outline` shader runs before bloom and chooses its occlusion policy from the same four Post inputs.

| Image | Content |
| --- | --- |
| [Coverage](evidence/selection/metal-coverage.png) | Red coverage, green selected depth, and blue scene depth |
| [Visible-only](evidence/selection/metal-visible.png) | HDR outline compares selected depth with scene depth |
| [Through-wall](evidence/selection/metal-through.png) | The same shader ignores the depth comparison |

The selected Group contains overlapping cubes, a nested Group, cutout foliage, transparent glass, and skinned Pip.
Every selected Draw disables shadow casting.
The wall and floor contribute scene depth independently.
The overlapping cubes have one perimeter without an internal outline.
Glass retains its complete Selection shape at zero alpha.

Run these commands from the repository root:

```sh
roc scripts/build.roc glue
roc scripts/build.roc host
roc scripts/build.roc inputs
ROCCO_SHDC="$PWD/build/shader-tools/sokol-shdc" roc scripts/build.roc game post
python3 scripts/post_check.py
```

Use the pinned Odin compiler from `scripts/linux/Dockerfile`.
The local compiler reported `dev-2026-08-nightly:902106f`.
The shader compiler SHA-256 was `92db37975ad7ff3c3c9bc27cba1503287377cb287ebabf60d1c6b597abfa3244`.

The native checks cover these cases:

- Off, X2, X4, and X8 colour MSAA with single-sample Selection targets.
- Unchanged coverage and selected depth when the front wall disappears.
- Combined coverage and nearest depth against separate left and right Draws.
- No internal outline at overlapping Draw boundaries.
- Full-shape alpha-zero glass with no scene-depth contribution.
- Shared Surface cutouts, wind, skin poses, and fixed-step reproducibility.
- Visible-only and through-wall HDR outlines from the same inputs.
- Outline contribution to bloom and unchanged UI.
- Live deselection and Pack unload.
- Coverage-only and depth-only declarations, resize, DPI, and target release.
- Simulated native allocation failure and dependent-effect omission.
- Built-in Blend and skinned Mask alpha-override parity across colour and coverage.

The strict normal and spans engine suites each passed 841 tests.
The changed public Group examples passed Roc checks, tests, and builds.
The Post example passed 125 Roc tests.
The shader generator and asset tests passed all 21 tests with the pinned shader compiler.
The generated public guide snippets passed their check.

Selection adds no GPU resource credits.
It reuses the existing target, coverage shader, pipeline, per-part uniform, and skin reservations.
Its grouped individual submissions preserve the 116-byte instance layout and existing stream reservation.

CI runs `scripts/post_check.py` on Metal, GL, and D3D11.
The local images and checks establish Metal behavior only.
