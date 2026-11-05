# Canopy indirect light correction

Date: 2026-11-05.
Base: `96497af`.
Task: `0x87t0gi`.
Native backend: Metal on Apple M5.
OpenGL and D3D11 native acceptance remain pending.
Human foliage and lighting acceptance remains pending.
This work provides no performance acceptance evidence.

## Reproduction and cause

The combined canopy showed near-black cards behind the lit outer leaves.
The Surface hook's two face-sign multiplications correctly preserve the same canopy normal on both card faces.
Visible leaf cards can therefore retain shading normals that point away from the eye.

The environment response clamped negative N·V to 0.0001 before Schlick Fresnel.
For dielectric F0 of 0.04, its diffuse multiplier became 0.000479904.
This suppressed nearly all diffuse environment light on those cards.
The source canopy's tint and occlusion did not cause that suppression.
The direct shadow path did not cause it either.

Every full-scene comparison used seed zero, field seed 777, and the complete prepared layout.
The scene reached readiness at step 95.
The capture selected the canopy view and advanced another 243 fixed steps.
The eye was `(-13, 4, 12)`.
The target was `(-12.399621, 4.389418, 11.301502)`.
The vertical field of view was `1.3089969` radians.
Every capture contained 1920 by 1080 physical pixels.
The owned processes used `taskpolicy -a`.
Other development work shared the machine.

The image region covered x `[700,1250)` and y `[400,950)`.
A near-black pixel had every RGB channel below 20.

| Comparison | Near-black pixels |
| --- | ---: |
| Original complete lighting | 35,549 |
| Original environment lighting only | 46,336 |
| Diagnostic constant diffuse reflectance, environment only | 744 |
| Corrected complete lighting | 2,987 |
| Corrected environment lighting only | 3,671 |

The signed-cosine diagnostic marked canopy pixels with N·V at or below zero.
It matched 43,768 of the 46,336 near-black environment-only pixels.
The constant-reflectance control restored 43,755 of those matched pixels.
Their median RGB channel value rose from 9.67 to 51.33.
Positive-cosine canopy pixels changed from median 45.67 to 49.00 in that diagnostic.
The constant multiplier isolated the cause; it is not the correction.

## Correction

Built-in shaders and published Surface templates now use `abs(N·V)` for indirect reflectance.
The Schlick diffuse coefficient and environment BRDF fit use that cosine magnitude.
Indirect reflection evaluates the same material angle from either side of its shading normal.
Reflection direction already remains invariant when the normal sign changes.
The signed normal still selects diffuse irradiance direction.

Direct lighting retains its existing clamped cosine and equations.
The correction preserves direct attenuation, shadow bias, source casting, alpha coverage, and deformation.
The correction preserves imported textures, factors, roughness, metallic values, and occlusion.
It adds no Ambient, light, emission, binding, parameter, or public field.
It preserves the existing contract version and package interfaces.
Front-facing indirect response remains unchanged.
The native front-facing control remained pixel-identical before and after the correction.

The corrected image retains normal grazing-angle darkness.
The correction does not flatten canopy shading or remove occlusion.
The separate source-backlight approximation remains unchanged.

## Regression and checks

The minimal regression uses the existing Surface example and one uniform white cubemap.
It compares equal and opposite authored normals with the source same-face normal policy.
It retains imported leaf colour and cutouts.
It uses no Ambient or direct lights.
The regression verifies both rigid and instanced submissions.
It also compares built-in materials against an empty Surface under the same environment.

Before the correction, the rigid comparison failed with mean RGB difference 5.053263.
After the correction, rigid and instanced comparisons had mean difference zero.
The native built-in/default-Surface comparison also had mean difference zero.
The fixture verifies a loaded Sky and visible leaf pixels before comparing images.
This prevents equal black or omitted geometry from satisfying the test.

```sh
roc scripts/build.roc -- game surface
RUN_PREFIX='taskpolicy -a' python3 scripts/indirect_surface_check.py /tmp/canopy-ab/regression-final
RUN_PREFIX='taskpolicy -a' python3 scripts/surface_check.py /tmp/canopy-ab/surface-native
```

The existing Surface regression passed named-slot inheritance, wind replay, cutout shadows, casting switches, Pack lifetime, failures, and default PBR parity.
All 855 engine tests passed with pinned Odin `902106f`, strict style, and vet checks.
All 19 shader asset tests passed with the pinned shader compiler enabled.
The release host and both game builds passed.
The shader compiler emitted Metal, GL 4.3, and HLSL variants successfully.
The built-in shader generator reproduced its output byte-for-byte on a second run.
The particle shader output did not change.
The three Surface example interface fingerprints matched their pre-correction fingerprints.
The native regression now runs beside the Surface check in all three desktop CI paths.
Those future jobs must provide the remaining GL and D3D native evidence.

The generator used shader compiler pin `11d0cf678105d614d675e6d9bd2aaf3eeff12f8c`.
The corrected village binary SHA-256 was `4e86994afcc7d0bf252609b83bd7b3884f99b5f4c92e2d7c8de765a8d117a43a`.
The original binary SHA-256 was `6a2f97a61edef947f54bd73423800f26274630754c60e60ce317f5e202968409`.

## Artifacts

The agent inspected the negative-cosine mask, constant-reflectance control, and corrected complete-lighting image.
All artifacts remain outside the repository under `/tmp/canopy-ab/`.

| Path | Contents |
| --- | --- |
| `baseline-all/` | Original complete-lighting PNG, settings, camera, steps, hashes, and log |
| `baseline-ibl/` | Original environment-only capture |
| `negative-mask/` | Signed-cosine mask at the same pose |
| `constant-ibl/` | Controlled diffuse-only diagnostic |
| `corrected-all/` | Corrected complete-lighting capture |
| `corrected-ibl/` | Corrected environment-only capture |
| `contracts/` | Separate baseline and diagnostic compiler templates |
| `correlation.json` | Pixel counts and mask correlation |
| `regression-before/` | Native regression images before the correction |
| `regression-final/` | Passing native images, logs, and result JSON |
| `regression-comparison.json` | Failing difference and unchanged front-facing control |
| `surface-native/` | Existing Surface regression artifacts |
| `interface-parity.json` | Unchanged Surface package fingerprints |

The capture driver is `/tmp/rocco-canopy-ab.py`.
The driver accepts the repository path, output path, and optional `--ibl-only` or `--check-dark`.
It fixes the camera, simulation steps, seed, physical size, and pixel region.
The original `--check-dark` run failed with 35,549 pixels against a 5,000-pixel limit.
The corrected run passed with 2,987 pixels.
The diagnostic templates affected only temporary compiled assets.
No diagnostic mask, constant-reflectance branch, or temporary logging remains in repository source.

## Native backend verification

CI run 42017935944 passed the indirect-light regression on Metal, GL, and D3D11.
Rigid and instanced opposed-normal comparisons each changed zero channels.
The default Surface comparison also changed zero channels on every backend.
[Recorded evidence](canopy-indirect-backends-2026-11-05.json) includes artifact identifiers and archive checksums.
The later village fixture failed on hosted display sizes and a long Bridge request.
Those failures keep full-scene acceptance open.
