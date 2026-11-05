# Village baseline

This example preserves a small part of the CodingQuests village layout.
The baseline contains Ground, Lane, HouseA, HouseB, four lanterns, and 19 nearby trees.
`world.tscn` supplies all 154 asset placements.
The ground uses the source plane size and colour.

The current prepared textures are a 512-pixel diagnostic.
The original textures exceed the host's fixed frame memory during PNG decoding.
Source-resolution restoration and human composition review remain pending.
Read [the diagnostic evidence](EVIDENCE.md) for measurements and loading constraints.
The conversion preserves the original source hashes for that restoration.

## Build and capture

Ordinary builds use committed GLBs.
They require neither Blender nor Godot.

```sh
python3 examples/village/source/validate.py
roc scripts/build.roc -- game village
scripts/screenshot.sh village /tmp/village.png 600
python3 examples/village/fixtures/capture.py /tmp/village-evidence --movie
```

The movie command requires `ffmpeg`.
The fixture captures 1920 by 1080 physical pixels.
The fixture checks both building collisions, selection, mouse look, and the free camera.
It saves camera poses and a route checksum in `observations.json`.
Run the fixture twice and compare `route_sha256` to check repeatability.
The fixture uses seed zero.
Placement does not depend on the seed.

## Controls

| Input | Action |
| --- | --- |
| 1 | Start the source hero push. |
| 2 | Show the source orbit view. |
| 3 | Reset first-person walking to the source tour start. |
| T | Start the source tour with its 1.5-second hold. |
| F | Enable the free camera at the current eye position. |
| WASD | Move relative to camera yaw. |
| Shift | Walk at the source jog speed. |
| Mouse, Q, E | Turn the camera. |
| Space, Control | Move the free camera vertically. |
| Tab | Toggle mouse capture. |
| Enter | Select the building under the centre ray. |
| R | Reset the hero view and selection. |
| Escape | Exit. |

The Bridge `view` port accepts `hero`, `square`, `walk`, `tour`, and `free`.
The hero view copies the source camera positions, look point, 14-second easing, and 75-degree lens.
The tour copies the source points and 1.45-metre-per-second speed.
The tour camera stays at first-person height and looks down the lane.
The original source uses a third-person ranger camera.

Walking stays 1.7 metres above flat ground.
Coarse source boxes prevent entry into HouseA and HouseB.
The player has a 0.3-metre collision margin.
The free camera ignores these boxes.
Selection uses a warm tint until the shared outline shader is available.

## Effective baseline settings

| Setting | Value |
| --- | --- |
| Physical and logical image | 1920 by 1080; high DPI off |
| Fixed simulation | 120 Hz |
| MSAA | 4 samples |
| Shadow map | 2048 by 2048 per cascade |
| Shadow cascades | 2; existing 150-metre range |
| Tone map | AgX; exposure 1 |
| Bloom and fog | Off |
| Lighting | Constant ambient and one shadowed directional light |
| Dynamic vegetation | Off |
| Prepared texture cap | 512 pixels; diagnostic only |

The diagnostic loads one asset every 0.1 simulation seconds to limit loading work.
The capture fixture waits 600 steps before verification.
Every baseline asset must resolve before the fixture takes evidence.
Foliage currently has the renderer's solid shadow silhouettes.
The baseline has no grass field, wind shader, sky lighting, haze, smoke, or dust.
These features belong to the later integration tasks.

## Prepare assets

Download the archive named in [the source investigation](../../docs/RESEARCH-GODOT-SCENE.md).
Keep its SHA-256 equal to `2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d`.

```sh
python3 examples/village/source/prepare.py /tmp/cq-godot-3d-village-look.zip
```

The diagnostic conversion requires Blender for texture resizing.
Set `--blender PATH` when Blender is elsewhere.
Set `--max-texture-side 0` to preserve original PNG payloads without Blender.
Use that setting after the PNG memory prerequisite passes.

The packer preserves mesh units, node roots, material names, vertex colours, and existing tangents.
It generates tangents where the source has none.
It embeds PNGs and buffers into GLB without changing mesh accessors.
It keeps scene placement in generated `Layout.roc` and `source/manifest.json`.
The manifest records original texture hashes, prepared GLB hashes, and material names.
The packer rejects scene transforms with shear.

Shared textures repeat in GLBs because the current loader requires embedded PNGs.
The original 33 GLBs occupy 384,288,532 bytes.
A temporary Git pack reduced those assets to 87,395,352 bytes.
The 512 diagnostic occupies 46,357,612 bytes before Git compression.

## Credits and terms

Quaternius created the models and textures under CC0 1.0.
CodingQuests created the source scene and scripts.
The source README permits using those scripts and shaders in games.
The baseline adapts source placement and camera data.

Read [the original README](source/UPSTREAM-README.md) and [the asset licence](source/LICENSE_CC0_Quaternius.txt).
The supplied archive remains outside this repository.
