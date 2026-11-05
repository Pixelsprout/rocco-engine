# Runtime Post effects

Import `pf.Post` and the generated shader helpers.
Add effect instances to `Scene.post`.

```roc
scene = {
    ..Scene.empty,
    shader_values: [Haze.scene("effects", Haze.scene_default)],
    post: [
        Post.before_bloom(Haze.draw("effects", Haze.draw_default)),
        Post.after_tone_map(Colour.draw("effects", Colour.draw_default)),
    ],
}
```

Set an instance's `enabled` field to `Bool.False` to disable it.
An instance takes generated Draw-scope values.
Scene-scope values come from `Scene.shader_values`.
Repeated references remain separate instances with independent values.
Each location preserves list order.
The host accepts the first 32 valid enabled instances.
The host logs and skips excess instances.

HDR effects read and write linear RGBA16F before bloom.
LDR effects read and write encoded display RGBA8 after tone mapping.
Each effect samples the previous output and writes a separate single-sample target.
The final LDR output copies into the existing target before UI submission.
UI retains the launch MSAA count and stays outside world effects.
Screenshots read the same final RGBA8 target.

All inputs use physical output dimensions.
`engine_post.viewport` contains width, height, reciprocal width, and reciprocal height.
`engine_post.frame.x` contains simulation-derived render time.
The remaining fields contain zero.
The production wrapper aligns input UVs across Metal, GL, and D3D11.

Scene depth uses R32F reversed device depth.
Depth clears to zero, and greater values are nearer.
A separate single-sample geometry pass produces depth for every launch MSAA count.
That pass draws Opaque and Mask geometry.
Blend geometry, particles, and the sky contribute no scene depth.
Surface Selection programs preserve deformation, alpha hooks, textures, skin poses, and render time.
Built-in coverage programs preserve imported vertex alpha, resolved alpha factors, and Mask cutoffs.
Reversed depth testing retains the nearest fragment.
GL clip conversion occurs before rasterization, so fragment depth already uses the engine's zero-to-one range.

The depth pass samples polygon edges once per pixel.
MSAA colour can therefore contain partial edge coverage where scene depth contains either geometry or the background.
This difference applies to Off, X2, X4, and X8 without hardware depth resolve.

Selection coverage and depth remain separate from scene depth.
Declared Selection inputs currently contain an empty union.
The later Selection task will draw the selected Group into these targets.
`Coverage_Target` provides R8 coverage, R32F depth, and one single-sample depth attachment.
`renderer_surface(.Selection)` writes this attachment layout.
`frame_render_depth` intentionally omits Blend geometry.
Selection submission must retain full-shape Blend coverage and Draws that do not cast shadows.

The host resolves values and validates pipelines before allocating optional inputs.
Empty, disabled-only, and invalid-only lists keep the original geometry, bloom, tone-map, and UI passes.
Only enabled valid effects allocate colour intermediates or requested depth and Selection targets.
Resize and DPI changes replace optional images with the main targets.
Removing the last dependent effect releases its optional images.
Failed effects log and skip without changing the remaining order.

The resource pools include ten optional images and eighteen optional views.
Each active location uses two colour images and four views.
Scene depth and Selection each use three images and five views.
The unused scene-coverage attachment permits reuse of validated Surface Selection programs.
Each generation reserves nine shaders and 63 pipelines, which also cover Post's two programs and two pipelines.
The fixed renderer adds two coverage shaders and six coverage pipelines.
The final LDR copy adds one shader and one pipeline.
Combined Surface, particle, Post and instancing pools reserve 328 shaders and 2095 pipelines.
Buffers reserve `3 * meshes + 7`.

For `D` accepted part draws and `C` cascades, uniform capacity reserves these bytes:

```text
(14 + 4*C)*D*256 + 341*256 + (3 + C)*min(D, 256)*4096
```

The fixed reserve includes 64 aligned blocks for 32 effect instances.
The separate scene-depth pass adds four aligned blocks and one skin palette per bounded submission.
Selection retains its separate existing reservation.
The combined Draw limit is 278653.

Build `examples/post` with `roc scripts/build.roc -- game post`.
Run `python3 scripts/post_check.py` from the repository root.
Set `ODIN` to the pinned compiler path when necessary.
The check records supported sample counts from native device queries.
The native target check tests resize, DPI, optional lifetime, depth sample count, and separate colour images.
Bridge checks test real geometry depth, Blend omission, Mask holes, deterministic deformation, effect order, failures, and UI parity.
CI runs these checks on Metal, GL, and D3D11.
A configured backend check remains pending until its native job passes.
