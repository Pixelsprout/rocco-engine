# Immersive village

This example contains the complete prepared CodingQuests village layout.
It uses 1,436 source placements, 93 meshes, and a 22,000-placement vegetation field.
The source field seed is 777.
The source camera equations, 75-degree lens, route points, and cumulative transforms remain intact.

The game includes source lighting, ground, wind, canopy shading, grass, named window materials, outlines, smoke, and dust.
The game keeps geometry hidden until every mesh, image, Sky, and Shader Pack resolves.
A failed asset keeps the loading error visible.
The original baseline composition approval remains recorded in [EVIDENCE.md](EVIDENCE.md).
Combined appearance and final performance acceptance remain open.

Read [COMBINED-EVIDENCE.md](COMBINED-EVIDENCE.md), [LIGHTING.md](LIGHTING.md), [source/README-FOLIAGE.md](source/README-FOLIAGE.md), and [EFFECTS.md](EFFECTS.md) for contracts and limitations.

## Build and capture

Ordinary builds use committed GLBs and images.
They require neither Blender, Godot, Pillow, nor the source archive.

```sh
python3 examples/village/source/validate.py
roc scripts/build.roc -- game village
python3 examples/village/fixtures/scene_effects.py /tmp/village-native
```

The native fixture keeps the complete layout and full default density.
It checks asset readiness, wind, particles, selection policies, colour, UI, seeds, and clean native exits.
It uses bounded fixed steps rather than a performance workload.
The second process repeats its images and cameras.
The third process checks alternate particle source seeds.

On a 2x Retina display, append `--retina-1080` to each fixture command.
The game then requests 960 by 540 logical pixels with high DPI enabled.
Other displays use the default 1920 by 1080 window with high DPI disabled.
The strict fixtures verify actual physical dimensions of 1920 by 1080.
For hosted native compatibility, append `--hosted-compat` to the `scene_effects.py` command.
This mode requires exactly 960 by 540 physical and logical pixels with high DPI disabled.
It preserves the 16:9 camera aspect, full density, effects, and simulation schedule.
Each capture records its actual dimensions and evidence mode.
Hosted compatibility does not establish final 1080p appearance or performance acceptance.
Window settings require a restart.

Capture the four foliage and lighting review views with effects disabled:

```sh
python3 examples/village/fixtures/foliage.py /tmp/village-foliage --hero-steps 240 --replay --retina-1080
```

Capture a bounded route preview with the combined effects checks:

```sh
python3 examples/village/fixtures/scene_effects.py /tmp/village-review --retina-1080 --movie
```

The preview records eight camera poses at 120-step intervals along the unchanged source tour.
The preview covers its first eight simulation seconds.
The script retains frame hashes and the movie, then removes its raw frames.
The movie requires `ffmpeg`.

The longer interaction and route fixture remains available:

```sh
python3 examples/village/fixtures/capture.py /tmp/village-route --retina-1080 --movie
```

That fixture checks source Draw loading, both initial house collisions, Group selection, mouse look, and the free camera.
It saves camera poses and a route checksum in `observations.json`.
The fixture uses seed zero.
Fixed source placement and the generated field do not depend on the game seed.
Particle streams do depend on the game seed.

## Controls

| Input | Action |
| --- | --- |
| 1, 2, 3 | Start the source hero push, square view, or first-person walk. |
| T | Start the source tour with its 1.5-second hold. |
| F | Enable the free camera at the current eye position. |
| WASD | Move relative to camera yaw. |
| Shift | Walk at the source jog speed. |
| Mouse, Q, E | Turn the camera. |
| Space, Control | Move the free camera vertically. |
| Tab | Toggle mouse capture. |
| Enter | Select the building under the centre ray. |
| R | Reset the hero view and selection. |
| 4, 5, 6 | Toggle wind, canopy shading, or grass shading. |
| 7, 8 | Toggle the field or source casting. |
| 9, 0 | Toggle the outline or switch its occlusion policy. |
| C, M, N | Toggle colour grading, smoke, or dust. |
| P, G, H | Toggle outline pulse, glow, or the controls panel. |
| Escape | Exit. |

The `view` Bridge port accepts `hero`, `square`, `walk`, `tour`, `free`, `foliage`, and `canopy`.
The `vegetation`, `lighting`, `effects`, and `quality` ports expose independent live controls.
Their module documents list exact messages.
Walking uses all six rotated source collision boxes with a 0.3-metre margin.
The free camera ignores these boxes.
Selection sets one house Group and preserves its imported Draw colours.
The outline uses the full selected Group union.

## Current settings and gates

The default retains all source content and the full generated field.
Field visibility uses 65 metres plus a ten-metre fade margin.
Startup uses X4 MSAA, 2048 shadow maps, and two cascades.
Lighting uses AgX, exposure 1.12, bloom, haze, the prepared sky, sun, and six practical lights.
Named quality settings are diagnostic choices, not measured machine recommendations.

The sky is a fixed-time LDR approximation.
Vegetation shading and dust spawning contain documented source approximations.
Smoke and dust receive no scene fog.
Human appearance review and native backend acceptance remain open for the combined scene.
Controlled optimized CPU runs reduced p95 from 48.41–51.94 ms to 27.94–29.12 ms.
Frame-local Surface resolution reuse preserves the full scene and seven exact comparison images.
Read the [CPU evidence](../../docs/evidence/surface-reuse-cpu-2026-11-06.json).
Real-clock CPU, GPU, pacing, per-effect, and reference PC acceptance remain open.
No density or texture reduction establishes a performance preset in this checkpoint.

Functional fixtures do not enable Spans automatically.
Performance capture must explicitly select an instrumented host and its output path.

## Prepare assets

Keep the source archive outside the repository.
Its SHA-256 is `2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d`.
Read [the source investigation](../../docs/RESEARCH-GODOT-SCENE.md).
The complete converter requires Pillow only for the two source JPEG images.
Read [the preparation instructions](source/README-FOLIAGE.md) before regenerating assets.
The converter preserves original PNG payloads, decoded JPEG pixels, mesh units, material names, colours, and tangents.
It keeps placement outside the mesh vertices.

## Credits and terms

Quaternius created the models and textures under CC0 1.0.
CodingQuests created the source scene and scripts.
The source README permits using those scripts and shaders in games.
Read [the original README](source/UPSTREAM-README.md) and [the asset licence](source/LICENSE_CC0_Quaternius.txt).
