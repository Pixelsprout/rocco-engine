# Village effects

`Effects.roc` owns the village Post chain and particle sources.
`effects-shaders.json` contains the effects declarations for shared-file integration.
The ordinary build uses the combined `shaders.json`.
The hooks require no engine source changes.

The outline reads scene colour, scene depth, selected coverage, and selected depth.
Both occlusion policies use those same four inputs.
The shader compares reversed depth for the visible-only policy.
The through-wall policy uses selected coverage without the comparison.
The outline runs in HDR before bloom.
The colour effect runs after tone mapping.
The engine draws UI after both effects.

Selection uses the existing Enter ray and collider IDs.
Each selected building sets `Group.selected` once.
All descendant Draws contribute to one coverage union.
The game does not change their tint.
The game omits the outline Post when no Group is selected.
This avoids optional depth and Selection work during ordinary walking.

## Live controls

| Key | Effect |
| --- | --- |
| 9 | Toggle the outline. |
| 0 | Switch visible-only and through-wall outlines. |
| C | Toggle colour grading. |
| M | Stop or restore smoke emission. |
| N | Stop or restore dust emission. |
| P | Toggle the outline pulse. |
| G | Toggle the outline glow. |
| H | Show or hide the controls panel. |

The Bridge `effects` port accepts `all`, `none`, `outline`, `colour`, `smoke`, and `dust`.
It also accepts `visible`, `through`, `occlusion`, `pulse`, `glow`, and `controls`.
Use `width:1`, `width:2`, `width:3`, or `width:4` for physical-pixel outline widths.
All changes apply live.
The controls panel starts hidden.

Removing an emitter stops new particles.
Existing particles drain with the previous settings.
Restoring a source during its drain keeps its random sequence.
Restoring a fully drained source starts its sequence again.
These behaviours follow the existing Emitter contract.

## Smoke and dust

The smoke source uses `HouseA/Prop_Chimney2` from Layout.
The source mesh root is below its mouth.
The brick mouth corners lie at local Y 3.0.
The stone rim reaches local Y 3.177875.
The emitter uses local `(0, 3.20, 0)` after the placement rotation and scale.
Its world position is approximately `(-5.6, 8.6, 2.6)`.
The source manifest records the inspected corners and cumulative transform.

Smoke uses Alpha blending, five particles per second, and a seven-second lifetime.
It expands from 0.38 to 2.4 metres and drifts upward.
The sprite has deterministic soft lobes.
The archive has no smoke emitter; smoke implements the agreed village scope.

Dust follows the source's warm additive specks, seed 4242, and 14-second lifetime.
The source requests 160 particles in a box centered at `(0, 1.6, 4)`.
Its box half extents are `(5, 1.3, 14)`.
The current API has point sources with velocity spread.
The village approximates the source box with 40 fixed stratified sources.
Their total rate is `160 / 14` particles per second.
Their positions and velocity streams depend on the game seed.
The source's turbulence, box spawning, preprocess, and alpha ramp have no exact API equivalents.
The approximation uses small velocity spread and linear alpha decay.
It adds no particle engine features.
Dust builds up during the first 14 simulation seconds.

The scene uses 41 emitter slots from the existing 128-slot limit.
The unchanged engine simulator replay reaches 36 smoke and 160 dust particles at 1800 steps.
It retains those counts at 3600 steps.
The replay drains every particle and source within 1800 steps after removal.
A conservative lifetime boundary allows at most 236 live particles from the 8192-particle limit.
Each active source produces one particle batch.
The steady scene therefore adds at most 41 particle submissions.
The effects add two Images, two Shaders, zero Meshes, and zero Draws.
They require no Launch capacity increase.

The engine applies no scene fog to particles.
Smoke and dust therefore retain their colour through the distance haze.
Their finite lifetimes and village-local sources bound that difference.
The renderer depth-tests particles against opaque geometry without writing depth.
Alpha smoke shares source ordering with Blend Draws.
Additive dust draws after that ordering.

## Reproduction

Build the village with `roc scripts/build.roc game village`.
Run the fixture from the repository root:

```sh
python3 examples/village/fixtures/effects.py /tmp/village-effects --retina-1080
```

Use `--retina-1080` on the 2x Retina display to produce 1920 by 1080 physical pixels.
A 1x display uses the default 1920 by 1080 window.
The fixture requires 1080p output in either case.
The fixture keeps seeds, input sequences, and simulation steps in its report.
Its occluded comparison uses existing free-camera controls behind a tree.
It preserves every approved comparison view.

Regenerate the prepared sprite assets and verify the chimney source:

```sh
python3 examples/village/source/prepare_effects.py /path/to/cq-godot-3d-village-look.zip
```

The preparation verifies the established archive checksum.
Ordinary builds require neither the archive nor an image library.

## Integration

Keep the combined Layout and vegetation modules.
Merge the two entries from `effects-shaders.json` into the final shader declaration.
Request `Effects.assets` in Pack `effects` after the mesh and lighting requests.
Include every effects asset in readiness checks.
Do not use the mesh manifest length as the complete request count.

Store `Effects.default` and `Config.seed` in Model.
Fold the `effects` port through `Effects.compare` during each ready step.
Retain the independent keyboard controls when combining the input branches.
Set each building Group's `selected` field from its existing selected Group ID.
Keep the original Draw tint when constructing selected children.

Set `Scene.post` to `Effects.post(settings, selected_group)`.
Set `Scene.emitters` to `Effects.emitters(manifest, seed, settings)`.
Add `Port.listen("effects")` to the existing queries.
Keep UI in `Scene.ui`.
The baseline integration includes an optional opaque controls panel for UI parity checks.
Use the combined scene's mesh and material-part counts for its final Launch capacities.
Effects require only the existing particle limits and two additional Images.

The standalone effects declaration and combined declaration generate identical helpers.
The merger must regenerate the combined shader build metadata once.
Do not replace vegetation or lighting declarations with the effects-only declaration.
