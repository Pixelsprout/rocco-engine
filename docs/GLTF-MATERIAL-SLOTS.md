# glTF material slots and vertex colours

The importer records source materials before it merges materials or sorts parts.
`Mesh_Data.material_slots` contains every source material in source array order, including unused and unnamed materials.
Each entry stores the exact name, source material index, and linear RGBA base factor.
The source material index identifies a slot within this asset.
A changed source material array requires regenerated mesh helpers.
Part position never identifies a public slot.

Named materials produce separate parts even when their rendering values match.
Primitives using the same named source material share a part.
`Mesh_Data_Part.slot` and `Mesh_Part.slot` contain the source material index.
Alpha sorting moves parts without changing their slot values.
Bark and leaves therefore remain separate assignments after sorting.

Unnamed materials retain the previous value-based merging behaviour.
Their parts have no named slot.
A primitive without a material also has no named slot and retains its grey matte default.
No generated name depends on part order.

Duplicate names retain distinct source identities and distinct parts.
`mesh_material_slot` returns `Duplicate_Name` for an ambiguous name.
It returns `Unnamed` for an empty name and `Unknown_Name` for an absent name.
A helper generator must report these errors instead of choosing the first match.
A helper generator must also reject names that produce the same Roc identifier after conversion.
Rename ambiguous source materials before creating named helpers.
Unmodified meshes with duplicate names continue to render their imported materials.

## Vertex colour and alpha

The importer reads `COLOR_0` as float VEC3/VEC4 or normalized unsigned byte/short VEC3/VEC4.
It checks the accessor type, count, stride, offset, normalization flag, and buffer bounds.
Unsupported or malformed accessors return `Bad_Accessor`.
A VEC3 colour has alpha 1.
An absent `COLOR_0` has white RGBA.
The importer preserves linear values without sRGB conversion or premultiplication.

`Vertex.color` contains the component-wise product of `COLOR_0` and the base factor.
The existing renderer multiplies this value by the base texture exactly once.
Mask uses the resulting alpha for its cutoff in both colour and shadow passes.
Blend uses the resulting alpha for coverage.
Opaque ignores alpha for coverage through its existing pipeline.
The alpha mode still comes from the material, including when vertex alpha is below 1.

`Mesh_Data.vertex_colors` contains raw `COLOR_0` in vertex order.
`Mesh_Data.vertex_materials` records each vertex's source material index, including unnamed sources.
A value of -1 identifies the grey matte default without a source material.
This stream preserves source identity even when unnamed materials merge.
`mesh_table_add` transfers both streams and the slot metadata to `Mesh`.
The metadata survives upload and remains valid until mesh removal or table destruction.
The streams require 24 bytes per vertex on supported 64-bit targets, at most 1,572,840 bytes under the existing vertex limit.
The importer copies names and colours into the caller's allocator.
Parser scratch memory does not own these values.

Surface integration must upload `Mesh.vertex_colors` as its independent vertex colour input.
It must use the source material's base factor separately when resolving imported material values.
`Mesh.vertex_materials` supplies that source identity when unnamed materials share a part.
It must not multiply that factor into the raw stream before game hooks read grass weights.
The existing renderer continues to upload the factored `Vertex.color` stream.

## Geometry and conversion

The importer preserves UV0, tangents, texture semantics, and the existing node transform rules.
It does not recenter meshes or infer a deformation root from bounds.
Prepare deforming geometry around its authored local root during asset conversion.
Keep scene placement separate from the prepared mesh.
The prepared mesh root must describe mesh-local geometry; source node transforms still apply during import.

## Draw capacity

Named slots can increase part counts when source materials have equal rendering values.
Pip now has five parts for its five named materials.
`frame_room` counts actual part draws against `Capacity.draws` before submission.
`uniform_buffer_size` reserves uniforms for that same capacity.
The existing capacity checks still limit parts and skin blocks.
This change adds no GPU attributes, uniform blocks, or texture slots.
Set draw capacity from part draws when adding more named materials.

## Cutout mip coverage

MASK base textures preserve mip coverage when every vertex in a material run has the same combined alpha.
The effective texture cutoff is the imported cutoff divided by that combined alpha.
The texture cache includes this threshold and colour space in each variant key.
Opaque textures and MASK textures with different thresholds therefore keep separate mip data.
Variants count against the existing 16-texture limit per Mesh.
Equal effective thresholds share one variant.

Mip generation keeps base-level pixels and RGB values unchanged.
Each completed mip scales alpha to the closest available nonzero coverage at its effective cutoff.
A mip with positive base coverage retains at least one surviving texel when its averaged alpha permits it.
Small mips can exceed target coverage because their alpha bins cannot represent every requested fraction.
Variable vertex alpha keeps ordinary mips because interpolated alpha has no single texture threshold.
Surface overrides select owned ordinary-mip companions when alpha policy, cutoff, or base alpha changes.
Unchanged imported rules retain their coverage mips.
An arbitrary opacity hook has no statically known effective mip threshold.
