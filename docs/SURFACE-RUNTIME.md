# Runtime Surface materials

Packs load `assets/shaders/NAME.shaderpack` as `shader/NAME`.
The engine loads compiled packages without generated Odin code.
The package parser validates every backend before GPU creation.
The native backend validates device limits before program creation.
All required programs form one generation.
A failed generation logs its reason and omits affected parts.

## Public assignments

Import `pf.Material` and the generated shader and Mesh helpers.

```roc
values = Foliage.material("surfaces", Foliage.material_default)
leaves = Tree.leaves("trees", values)
leaf_properties = {
    slot: Tree.slot_leaves("trees"),
    material: { ..Material.default, properties: [Roughness(0.4)] },
}
draw = {
    ..Draw.default,
    id: 10,
    mesh: tree,
    materials: [leaves],
    slot_materials: [leaf_properties],
    shader_values: [Foliage.draw("surfaces", Foliage.draw_default)],
}
scene = {
    ..Scene.empty,
    nodes: [Draw(draw)],
    shader_values: [Foliage.scene("surfaces", Foliage.scene_default)],
}
```

`Draw.material` changes every imported part.
`Material.surface(values)` sets its Surface.
`Draw.materials` accepts generated `Shader.SlotAssignment` records.
A named Surface replaces the whole-Draw Surface for that source material.
`Draw.slot_materials` changes named material properties and maps.
Its `Imported` Surface inherits the current Surface assignment.
A scalar-only slot change therefore retains a whole-Draw Surface.
A named property replaces the same whole-Draw property.
Unspecified properties, factors, and maps remain imported values.

Duplicate entries in either named list are invalid.
Two named Surface assignments for one slot are invalid.
Unknown slots and assignments from another Mesh are invalid.
Unnamed source materials accept whole-Draw changes.
They do not accept named assignments.

Material properties are base colour, roughness, metallic, emission, unlit, normal scale, occlusion strength, alpha policy, and sidedness.
Material texture assignments name base colour, metallic/roughness, emission, normal, or occlusion.
They reference `image/NAME` in a loaded Pack.
Shader texture assignments accept `image/NAME` for 2D and `sky/NAME` for cubes.
The declaration selects file colour decoding and sampler policy.
Linear image variants retain unmodified source pixels.
The UI image variant retains its edge bleed and sRGB decoding.

Constant texture defaults contain linear shader values.
Their components do not depend on the declaration's file colour space.
RGBA32F storage preserves negative values and HDR values.

## Imported data and coverage

Surface vertex buffers contain raw `COLOR_0`.
Resolved material uniforms contain the imported base factor multiplied by Draw tint.
Unnamed material runs split when their source identities differ.
Their factors remain separate even when the original renderer merged their parts.
These runs count against `Capacity.draws`.

Alpha and shader submission groups use resolved parts.
The imported Opaque prefix remains an optimization for unchanged materials only.
Colour and shadow submissions share parameters, textures, pose, Draw data, and simulation time.
Selection uses the same resolved materials and vertex programs.
Coverage programs expose material and environment resources.
Engine lighting blocks and clustered storage remain Colour resources.
Blend selection retains full-shape coverage.
The current shadow caster policy includes Opaque and Mask parts.
`casts_shadow = False` removes shadow fitting and submission only.

Explicit alpha-policy, cutoff, or base-alpha changes select ordinary mip companions.
Unchanged imported Mask rules retain their coverage mips.
An arbitrary opacity hook has no statically known mip threshold.
Both passes still evaluate its identical opacity function.
Declared maximum displacement expands local bounds before the Draw transform.
The expanded bounds feed shadow fitting and Blend sorting.
Later frustum culling must use `placed_box`.

## Pack lifetime

Asset references resolve through their named live Pack each frame.
Another Pack holding the same asset does not authorize a reference to an unloaded Pack.
Explicit unload invalidates dependent resolved materials at the next frame boundary.
The engine logs and omits their affected parts before any pass.
Reloading the referenced Pack permits fresh resolution with its new asset IDs.
Stale numeric IDs never resolve to replacement Shader assets.

Shader resources remain in bounded retirement slots for three render frames.
Retiring generations count against the 32-generation capacity.
Sokol also defers native Metal resource release beyond in-flight use.
Imported image and cube destruction uses Sokol's native retirement rules.
Resolved material descriptions live only in the frame arena.
They cannot retain stale GPU bindings across frames.

The later reload task must reserve staging capacity before GPU creation.
It must retain the current generation and its dependencies after any failed reload.
An explicit dependency Pack unload still invalidates those dependent descriptions.

## Capacity

The table permits 32 live, staged, or retiring generations together.
Each Surface reserves nine shader handles and up to 63 pipeline handles.
Disabled layouts omit their programs.
Pipeline keys contain generation ownership, pass, layout, alpha policy, culling, formats, and sample count.
Blend and Opaque share solid coverage keys outside colour rendering.
The initial table has one launch sample count and fixed pass formats.

Each Mesh reserves three buffers.
Each imported texture can add one ordinary-mip companion.
The original 16-texture import limit therefore reserves at most 32 GPU textures per Mesh.
Each Image reserves sRGB and linear image/view pairs.
Each Sky reserves its source sRGB cube, source linear cube, diffuse cube, and specular cube.
Each Shader reserves four game samplers and four constant images/views.

Every applied uniform block reserves 256-byte alignment.
The parser rejects variants above these aligned limits:

| Pass | Rigid or instanced | Extra skinned bytes |
| --- | ---: | ---: |
| Colour | 1536 | 4096 |
| Shadow | 1024 | 4096 |
| Selection | 1024 | 4096 |
| Post location | 512 | unavailable |

The arena includes one Selection submission per accepted part draw.
Post integration must add its separate scene-depth submissions and effect costs.
Additional formats or sample counts require additional pipeline credits.
Particle reservations must remain additive to these reservations.
The combined renderer reserves `3 * meshes + 6` buffers, 321 shaders and 2082 pipelines.
With `D` part draws and `C` cascades, the uniform arena reserves these bytes:

```text
(10 + 4*C)*D*256 + 277*256 + (2 + C)*min(D, 256)*4096
```

The combined Draw limit is 321682.

## Checks and later integration

Build `examples/surface` and run `python3 scripts/surface_check.py`.
The script checks deterministic wind, named changes, cutout shadows, casting, Pack invalidation, invalid versions, and default PBR parity.
The desktop CI jobs run the same native check on Metal, GL, and D3D11.
A configured CI job is not native execution evidence until that job passes.
The merged Metal fixture passed with both 820-test engine suites on 2026-11-05.
The engine checks used CI-pinned Odin `902106f`.
The two-run particle fixture also passed, including sprite orientation.
The shader compiler suite passed all 35 tests.
The ABI and built-in shaders regenerated without byte changes.
Local native artifacts are in `/tmp/rocco-surface-particles-merged`.
Surface OpenGL and D3D11 acceptance remains pending CI.

Post integration can call `renderer_surface` with `Surface_Pass.Selection`.
Use `placed_draw_params` and `frame_render_part_params` to preserve colour and coverage inputs.
Use `Placed.draw_id` to match selected Draws.
That pipeline writes R8 coverage and R32F depth with a separate depth attachment.
It needs two colour attachments and one sample.
Post integration must retain non-casters in selection.
It must generate separate scene depth when MSAA prevents portable depth sampling.

Reload integration can reuse package validation, program creation, and bounded retirement.
It must retain requested Pack membership to recover failed first loads.
The current Pack cache retains successful held IDs and logs failed asset names.
It must switch complete compatible generations at a frame boundary.
Instancing can reuse `Shader_Layout.Instanced` and `Surface_Instance`.
The instance stream uses 116 bytes with scalar model and normal columns.
Model, normal and tint begin at byte offsets 0, 64 and 100.
Odin matrix alignment must not add padding to this vertex stream.
Its batch key must include all material values, game values, textures, and Draw data.
Only model, normal transform, and tint may vary inside one batch.
