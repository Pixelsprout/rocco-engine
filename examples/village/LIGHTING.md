# Village lighting

The lighting implementation uses the source sun, six source practical lights, source window slots, and source ground palette.
The approved camera, lens, route, placement, and mesh textures remain separate from lighting.
Combined foliage and lighting review remains pending.
Final Mac and PC presets and independent effect costs remain pending.

## Integration

1. Merge `lighting-shaders.json` into the combined `shaders.json`.
2. Load `Lighting.assets` together in one Pack named `lighting`.
3. Require every lighting asset to resolve before showing the scene.
4. Store `Lighting.Settings` in the Model with `Lighting.default`.
5. Fold messages from the `lighting` port with `Lighting.compare`.
6. Emit `Lighting.ground(settings)` once instead of the baseline plane.
7. Append `Lighting.nodes(settings)` to the Scene nodes.
8. Use `Lighting.environment(manifest, settings)` for the Scene environment.
9. Apply `Lighting.windows(draw, { asset, settings })` to each prepared Draw.

The window function appends two partial properties to material slot overrides.
It changes only `MI_WindowGlass`, source material 1, on `Window_Thin_Round1` and `Window_Wide_Round1`.
It preserves imported maps, roughness, metallic values, alpha mode, other slots, and existing overrides.
Each window mesh retains its asset name as its Pack name, matching the baseline loading scheme.
If the integrator changes mesh Pack names, update the two generated slot calls in `Lighting.windows`.

The lighting Pack contains one Sky, two Images, and one Surface shader.
The primitive ground adds one Draw.
The six practical lights add no Draws and cast no local shadows.
Window helpers add no meshes beyond the prepared layout.
No lighting Post effect or extra depth input is required.

The foliage Pack can also request `image/T_Noise_Terrain`.
Both Packs share the image through the engine's reference counts.
The shared file remains `assets/images/T_Noise_Terrain.png`.
Sample it as linear data with linear filtering and repeated coordinates.
Sample `image/ground_mask` as linear data with linear filtering and clamped coordinates.

## Comparison controls

The `lighting` port accepts `all`, `none`, `sun`, `sky`, `exposure`, `bloom`, `haze`, `lamps`, and `ground`.
`all` restores every switch.
`none` disables every switch.
Each individual name toggles only its switch.
The lamps switch controls six lights and warm window properties together.
The sun switch removes the direct light when disabled.
The sky switch removes both the background and surface environment lighting.
No additive Ambient light compensates for the disabled sky.

Run the required game build before captures:

```sh
roc scripts/build.roc game village
python3 examples/village/fixtures/lighting.py /tmp/village-lighting --require-1080
```

The fixture starts a new process for each comparison.
It uses seed zero and equal steps after readiness.
It records cameras, actual dimensions, settings, hashes, and native logs.
It checks surface changes in the lower image quarter when the sky switch changes.
The default views are hero, square, and the route after 480 fixed steps.
Use `--views tour --steps 2400` to compare a later route point.
The `--require-1080` option rejects captures with different physical dimensions.

The game can call `Display.window(config, window)` in `launch`.
The default requests 1920 by 1080 logical pixels with high DPI disabled.
On a 2x Retina display, `--retina-1080` requests 960 by 540 logical pixels with high DPI enabled.
Both choices target 1920 by 1080 physical pixels.
The fixture verifies the actual dimensions independently.
Window settings require a restart.

```roc
window: Display.window(config, { ..Launch.default.window, title: "Village" }),
```

```sh
python3 examples/village/fixtures/lighting.py /tmp/village-lighting --retina-1080 --require-1080
```

## Source preparation

Ordinary builds use prepared images and require neither Blender nor Godot.
Prepare the lighting assets with Python's standard library:

```sh
python3 examples/village/source/prepare_lighting.py /tmp/cq-godot-3d-village-look.zip
```

The script verifies archive SHA-256 `2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d`.
It copies the original 512-square noise PNG and 256-square ground mask PNG without changing their bytes.
It records source and output hashes in `source/lighting-manifest.json`.
It samples the source sky equations at time zero into six 256-square faces.
The source colour parameters use sRGB conversion before linear calculations.
The noise and ground mask remain data textures.

The prepared sky is LDR sRGB RGB8.
The source contains HDR glow values, but the current Sky accepts LDR PNG faces.
Preparation clips 15,824 of 393,216 texels in at least one channel before sRGB encoding.
The source omits its bright sun disc during cubemap lighting.
Preparation follows that lighting pass, so the shared background also omits the disc.
The shared background and lighting cannot reproduce the source's separate background-only disc.
Clouds remain fixed at time zero.
The source uses ambient sky energy 0.6, while its sky shader uses energy 1.
The current Environment has no separate intensity for sky lighting.
The prepared cube uses energy 1 for both paths.
Combined appearance review must judge this shared-intensity approximation.
Sky filtering uses the existing deterministic diffuse and specular preparation described in `docs/ENVIRONMENT-LIGHTING.md`.
This is an LDR environment approximation, not an HDR radiance reconstruction.

The ground hook ports the source's mask coordinates, three noise scales, wear, palette, and tree shade.
The source's anisotropic mipmapped noise sampler becomes the contract's linear sampler at LOD zero.
The source's separate specular control has no matching built-in material field.
Ground roughness remains 0.95 and metallic remains zero.

## Atmosphere choices

The sun keeps source direction `(0.84, -0.52, 0.16)` and energy 2.6.
Light colours and window colours use source sRGB values converted to linear values.
Exposure remains 1.12 with AgX.
Bloom uses threshold 1.2, knee 0.5, and strength 0.18.
The engine's bloom differs from Godot's soft-light glow.
Existing distance fog supplies haze from 14 to 120 metres, with amount 0.38.
It approximates the source's distance atmosphere without its volumetric fog, ground volume, or light shafts.
The surface fog path does not fog sky or particle sprites.

Height fog and contact occlusion remain deferred until combined fixed-view comparisons show a need.
No custom sky renderer or speculative GI method was added.
Clustered lamp stability still needs complete-layout route verification after integration.
The six source light positions remain independent of lantern mesh roots.

## Credits

Quaternius created the model textures, including terrain noise, under CC0 1.0.
CodingQuests supplied the ground mask and created the source ground and sky shaders and lighting settings.
The source README permits shader and script use in games.
Read `source/UPSTREAM-README.md` and `source/LICENSE_CC0_Quaternius.txt` for the original terms.
The source archive remains outside the repository.
