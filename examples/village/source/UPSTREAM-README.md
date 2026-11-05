# The 3D Village Look Project

This is the village from the CodingQuests video "Why Godot Games Look So Bad in 3D".

It has two scenes built from the same models:

- `scenes/default.tscn` uses the sun and environment Godot adds from the 3D view's preview menu.
- `scenes/finished.tscn` is the same village with twelve look changes. Each change is a switch you can turn on and off while the game runs.

With every switch off, the finished scene renders the same picture as the default scene. Nothing is hidden in the models.

Write-up and video: https://codingquests.io/blog/how-to-make-godot-3d-look-better

## Open it

1. Use Godot 4.7 or newer, with the Forward+ renderer.
2. In the Project Manager, click Import and pick the `project.godot` file in this folder.
3. The first open imports every model and texture. That takes a few minutes. Later opens are quick.
4. Press F5. The finished scene is the main scene.

## Controls

| Key | What it does |
|---|---|
| WASD | walk (camera-relative) |
| Shift / Alt | jog / sprint |
| Space | jump |
| Right mouse, Q / E, mouse wheel | look around, swing the camera, zoom |
| C | next camera: hero, follow, orbit, close |
| T / R | walk the tour route / go back to the start |
| H | show the list of switches and which are on |
| F12 | save a screenshot to the user:// folder |

## The twelve switches

Press a key to flip one switch. **K** turns them all off, **J** turns them all on, and **L** adds the next one in order. The best way to learn from this project: press K, then press L twelve times and watch what each step changes.

| Key | Switch | What it changes |
|---|---|---|
| 1 | Sun | Lower and warmer, about 30 degrees up, from the side. Softer shadow edges. |
| 2 | Sky | A sky shader (`shaders/sky.gdshader`) that also lights the shadows. |
| 3 | Tonemap + grade | AgX tonemapper, a little more exposure, cool shadows and warm highlights. |
| 4 | Ambient occlusion | SSAO and SSIL, so things that touch look like they touch. |
| 5 | Global illumination | SDFGI, so sunlight bounces off the ground onto the walls. |
| 6 | Atmosphere | Distance fog, a low ground mist and volumetric fog. |
| 7 | Foliage shader | Leaves sway, and each tree shades like one soft shape (`shaders/foliage.gdshader`). |
| 8 | Grass + ground | Grass bends from the root (`shaders/grass.gdshader`), and the ground mixes greens with worn dirt (`shaders/ground.gdshader`). |
| 9 | Grass field | 22,000 more copies of the same grass and flower models, drawn with MultiMesh. |
| 0 | Practical lights | Lanterns, glowing windows, and a fill light that only reaches the ranger. |
| - | Lens | A 55 degree field of view and a little far blur. This one changes the framing. |
| = | Polish | MSAA 2x + TAA, a vignette, film grain and floating dust. |

## Where the values live

Every number is in `scripts/look.gd`. The `SUN` and `ENV` dictionaries near the top hold the sun and environment settings. Each switch has an `_apply_...` function further down. Change a value, run the scene, and flip that switch to compare.

`PERF` in the same file has two profiles. `"optimised"` is what the scene uses. `"early"` is the first, slower version from the video's performance section: a bigger shadow map, higher soft-shadow quality, MSAA 4x and more grass. Run with `-- --perf=early` on the command line to try it.

These numbers suit a warm afternoon village. A darker game would keep the same switches with different values.

## Credits

All models and their textures are by Quaternius, released under CC0 (public domain). See `assets/LICENSE_CC0_Quaternius.txt`. The packs used are the Medieval Village MegaKit, Fantasy Props MegaKit, Stylized Nature MegaKit, Ultimate Stylized Nature, Universal Base Characters, Modular Character Outfits - Fantasy, and Universal Animation Library 1 and 2. You can find them at https://quaternius.com.

The scripts and shaders are by CodingQuests. Use them in your own games however you like.
