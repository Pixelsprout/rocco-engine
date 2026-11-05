# Research: shadows from cutout materials

Date: 2026-11-04

Implementation: [ADR 0031](adr/0031-cutout-shadow-coverage.md) replaces the temporary rule below.
[Validation](CUTOUT-SHADOW-VALIDATION.md) records the implementation, mip evaluation, and reference Mac measurements.

## Question

How do modern engines cast shadows from alpha-tested (glTF MASK) materials, and what does each approach cost? Which approach fits rocco, and what would it cost here?

## This engine today

- The shadow pass draws once per Draw, over the Opaque and Mask range of the index buffer, in each of 1 to 4 cascades (`frame_render_shadow` and `frame_render_submit_shadow`, `engine/frame_render.odin:503-554`). `mesh_shadow_count` stops at the first Blend part (`engine/mesh.odin:488-498`).
- The shadow pipelines are depth-only (`colors = {0 = {pixel_format = .NONE}}`), cull BACK, CCW front faces, and slope bias -2 (`engine/render.odin:186-217`). The shadow vertex shader reads only `pos`, and `shadow_fs` is empty (`engine/shaders/basic.glsl:432-470`). The pass binds no texture.
- So a Mask part casts a shadow of its whole shape, and only from its front faces. A single leaf plane that faces away from the Sun casts no shadow.
- The Main pass draws the rigid Draws, then the skinned Draws. Each group runs in `Mesh_Pipeline` order: Opaque, Mask, Mask_Double_Sided (`engine/frame_render.odin:327-343`). Each change of mesh pipeline applies the lights block again (`engine/render.odin:328-338`).
- `mask_fs` computes the full surface colour, then discards if `color.a < material.w`. It discards only after every sample, so D3D keeps uniform control flow (`engine/shaders/basic.glsl:342-355`). The alpha is vertex colour alpha times base texture alpha.
- The uniform buffer reserves, per placed mesh part, `MAIN_UNIFORM_SLOTS` plus one shadow slot per cascade (`uniform_buffer_size`, `engine/render.odin:98-102`). `Shadow_Vs_Params` is one `mat4` (64 bytes), so `SHADOW_UNIFORM_SLOTS` is 1. The shadow pass uses one slot per Draw, so most of that reserve is unused today.
- Each pass may apply up to `skinned_draw_capacity` skin blocks of 4 KiB. `frame_room` counts one block per `Mesh_Pipeline` that a skinned Draw's parts use, against `len(fr.skins)` (`engine/frame_render.odin:449-470`). The shadow pass now applies one block per skinned Draw per cascade.
- `texture_build` box-filters alpha into each mip level (`engine/image.odin`). It builds mips only when the glTF sampler asks for a mipmap filter (`glb_sampler`, `engine/gltf.odin:889-912`).
- sokol binds each uniform block to one shader stage (`sg_shader_uniform_block.stage`, `sokol-odin/sokol/c/sokol_gfx.h:3988-3989`).
- Milestone 38 put "Cutout shadows for MASK, and a second shadow draw for double-sided MASK parts" out of scope. Task `wrtdfuuz` asks for this decision.

## Unreal Engine

- A Masked material discards a pixel where Opacity Mask is under the Opacity Mask Clip Value ([Material Blend Modes](https://dev.epicgames.com/documentation/en-us/unreal-engine/material-blend-modes-in-unreal-engine), [Material Properties](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-material-properties)).
- "Cast Dynamic Shadow as Masked" makes a translucent material cast shadows "as masked" ([Material Properties](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-material-properties)). This implies a masked shadow path, but the page does not describe it.
- Epic's renderer source is behind an Epic account, so this note did not read it. A forum thread shows the opacity mask also runs in the shadow depth pixel shader, and a reply tests `SHADOW_DEPTH_SHADER` to skip one effect there ([Unreal forum](https://forums.unrealengine.com/t/opacity-mask-shadow-with-pixel-depth-problem/363929)). This is a secondary source.
- Two-sided: the Two Sided material property, and the per-primitive `bCastShadowAsTwoSided` ("cast dynamic shadows as if it were a two sided material", [4.26 API](https://docs.unrealengine.com/4.26/en-US/API/Runtime/Engine/Components/UPrimitiveComponent/), from a search snippet).
- "Dither Opacity Mask", with TAA, gives "a form of limited translucency" ([Material Properties](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-material-properties)).

## Unity (URP and HDRP)

- URP: with Alpha Clipping on, the material compiles `_ALPHATEST_ON`. The `ShadowCaster` pass then passes the UV, samples the base map alpha, and calls `AlphaDiscard(... albedoAlpha * _BaseColor.a, _Cutoff)` ([ShadowCasterPass.hlsl L63-L75](https://github.com/Unity-Technologies/Graphics/blob/0efc28ea742b1966b9dd9cc4489e58b986a13faf/Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl#L63-L75)).
- The URP `ShadowCaster` pass has `ColorMask 0` and `Cull[_Cull]`, the same cull property as the lit pass ([Lit.shader L202-L246](https://github.com/Unity-Technologies/Graphics/blob/0efc28ea742b1966b9dd9cc4489e58b986a13faf/Packages/com.unity.render-pipelines.universal/Shaders/Lit.shader#L202-L246)). So Render Face "Both" also casts from both faces. Render Face offers Front, Back and Both ([URP Lit reference](https://docs.unity3d.com/6000.3/Documentation/Manual/urp/lit-shader.html), from a search snippet).
- HDRP: Alpha Clipping has an optional second "Shadow Threshold" for "whether it should render shadows for a pixel" ([HDRP 12 Alpha Clipping](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@12.0/manual/Alpha-Clipping.html)).
- The texture importer has `mipMapsPreserveCoverage`. It rescales mip alpha "so coverage is preserved", and it is off by default ([Unity scripting reference](https://docs.unity.com/en-us/engine/current/script-reference/unityeditor/textureimporter/mipmapspreservecoverage)).

## Godot 4

- Alpha Scissor, Alpha Hash and Depth Pre-Pass materials "can cast shadows". Alpha-blended materials "don't cast shadows" ([Standard Material 3D](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)).
- The scene shader runs the same alpha code in its depth mode, which the shadow pass uses. Alpha Scissor discards where `alpha < alpha_scissor_threshold` ([scene_forward_clustered.glsl L1347-L1360](https://github.com/godotengine/godot/blob/fefec82d74b46f5e6cc31f373071058f80a5cbee/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L1347-L1360)). Alpha Hash discards against a hashed threshold ([L1401-L1415](https://github.com/godotengine/godot/blob/fefec82d74b46f5e6cc31f373071058f80a5cbee/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L1401-L1415)).
- `compute_alpha_hash_threshold` is the hashed alpha test of Wyman and McGuire ([scene_forward_aa_inc.glsl L12-L39](https://github.com/godotengine/godot/blob/fefec82d74b46f5e6cc31f373071058f80a5cbee/servers/rendering/renderer_rd/shaders/scene_forward_aa_inc.glsl#L12-L39)).
- Two-sided: `GeometryInstance3D.cast_shadow` ON "will take culling into account". DOUBLE_SIDED "will not take culling into account, so all faces will be taken into account" ([GeometryInstance3D](https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html)).
- Alpha Antialiasing (Edge Blend, Edge Clip) uses alpha to coverage and needs MSAA ([Standard Material 3D](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)). Its edge function scales alpha up by `1 + mip * 0.25` and sharpens it with `fwidth` ([scene_forward_aa_inc.glsl L45-L56](https://github.com/godotengine/godot/blob/fefec82d74b46f5e6cc31f373071058f80a5cbee/servers/rendering/renderer_rd/shaders/scene_forward_aa_inc.glsl#L45-L56)).

## Bevy

- `AlphaMode::Mask(f32)` sets alpha to 0 or 1 at a threshold ([alpha.rs L13-L21](https://github.com/bevyengine/bevy/blob/4c344352e063923257e50efd65f265fea76bb4ff/crates/bevy_material/src/alpha.rs#L13-L21)).
- The shadow queue adds `MAY_DISCARD` for Mask, Blend, Premultiplied, Add and AlphaToCoverage ([light.rs L2585-L2591](https://github.com/bevyengine/bevy/blob/4c344352e063923257e50efd65f265fea76bb4ff/crates/bevy_pbr/src/render/light.rs#L2585-L2591)). A material without it uses a separate depth-only draw function ([L2631-L2640](https://github.com/bevyengine/bevy/blob/4c344352e063923257e50efd65f265fea76bb4ff/crates/bevy_pbr/src/render/light.rs#L2631-L2640)).
- The prepass discards a Mask fragment under its cutoff. It discards a Blend, Add or AlphaToCoverage fragment under a fixed 0.05 ([pbr_prepass_functions.wesl L17-L39](https://github.com/bevyengine/bevy/blob/4c344352e063923257e50efd65f265fea76bb4ff/crates/bevy_pbr/src/render/pbr_prepass_functions.wesl#L17-L39)). So Bevy's Blend materials cast a cutout shadow.
- Two-sided: `cull_mode` defaults to `Some(Face::Back)`, and `double_sided` does not change culling ([pbr_material.rs L654-L681](https://github.com/bevyengine/bevy/blob/4c344352e063923257e50efd65f265fea76bb4ff/crates/bevy_pbr/src/pbr_material.rs#L654-L681)). The material's `specialize` sets the pipeline cull mode ([L1614-L1626](https://github.com/bevyengine/bevy/blob/4c344352e063923257e50efd65f265fea76bb4ff/crates/bevy_pbr/src/pbr_material.rs#L1614-L1626)), and the prepass pipeline calls it ([prepass/mod.rs L385](https://github.com/bevyengine/bevy/blob/4c344352e063923257e50efd65f265fea76bb4ff/crates/bevy_pbr/src/prepass/mod.rs#L385)).
- `AlphaMode::AlphaToCoverage` needs MSAA. Without MSAA it acts as Mask at 0.5 ([alpha.rs L36-L47](https://github.com/bevyengine/bevy/blob/4c344352e063923257e50efd65f265fea76bb4ff/crates/bevy_material/src/alpha.rs#L36-L47)).

## Filament

- The depth variant runs the material for `masked` blending and discards where `alpha < getMaskThreshold()` ([surface_depth_main.fs L30-L40](https://github.com/google/filament/blob/5ce4cbf19051729d74db9ba33ad5bd04cf6b4f37/shaders/src/surface_depth_main.fs#L30-L40)).
- With `transparentShadow`, it discards where interleaved gradient noise is at least the alpha ([L42-L48](https://github.com/google/filament/blob/5ce4cbf19051729d74db9ba33ad5bd04cf6b4f37/shaders/src/surface_depth_main.fs#L42-L48)). The docs say transparent shadows "work best with variance shadow maps (VSM) and blurring enabled" ([Filament Materials](https://google.github.io/filament/main/materials.html)).
- `doubleSided` sets culling to none and flips back-face normals. `masked` turns alpha to coverage on automatically ([Filament Materials](https://google.github.io/filament/main/materials.html)).

## three.js

- `getDepthMaterial` makes a per-material depth material when `map` or `alphaMap` is set and `alphaTest > 0`. It copies `map`, `alphaMap` and `alphaTest` ([WebGLShadowMap.js L431-L495](https://github.com/mrdoob/three.js/blob/c6a4b78be1a3d7839399410cc157950c5fd6e58b/src/renderers/webgl/WebGLShadowMap.js#L431-L495)).
- With `alphaToCoverage`, the shadow uses a fixed `alphaTest` of 0.5 as an approximation (L495).
- `shadowSide` defaults to `null`. Then a FrontSide material casts from its back faces, and a DoubleSide material casts from both (L51, L486-L490; [Material.js L342](https://github.com/mrdoob/three.js/blob/c6a4b78be1a3d7839399410cc157950c5fd6e58b/src/materials/Material.js#L342)).
## Babylon.js

- The standard shadow map shader "already handles" alpha testing for StandardMaterial and PBRMaterial ([Babylon.js Shadows](https://doc.babylonjs.com/features/featuresDeepDive/lights/shadows)).
- `transparencyShadow` lets transparent objects cast. `enableSoftTransparentShadow` dithers the shadow map by the fragment alpha. `forceBackFacesOnly` renders back faces to cut bias (same page).

## Mipmaps and alpha thinning

- Box-filtered mips average alpha, so fewer texels pass a fixed cutoff in smaller mips. Castaño reports leaves that "faded out becoming almost transparent" with distance ([Computing Alpha Mipmaps](https://ludicon.com/castano/blog/articles/computing-alpha-mipmaps/)).
- A shadow map texel often covers many texture texels, mostly in far cascades. So the shadow pass picks a smaller mip, and a thin cutout loses its shadow first. This follows from the mip selection. No source here measures it.
- Fix 1, coverage-preserving mips: scale each level's alpha so the share of texels over the cutoff matches level 0. Castaño finds the scale by bisection, and NVTT implements it (same article). Unity (`mipMapsPreserveCoverage`) and DirectXTex (`ScaleMipMapsAlphaForCoverage`, which takes the "alpha test reference value") ship it ([DirectXTex wiki](https://github.com/microsoft/DirectXTex/wiki/ScaleMipMapsAlphaForCoverage)). The fix needs the cutoff at load time.
- Fix 2, mip-scaled and sharpened alpha in the shader: Godot scales alpha by the mip level and sharpens it with `fwidth` (see Godot above). Ben Golus's article on alpha to coverage describes this method, but this note could not open it (HTTP 403).
- Fix 3, hashed alpha testing: compare alpha with a stable hashed threshold, not a fixed cutoff. The paper says this keeps distant geometry from vanishing, at the cost of some noise ([Wyman and McGuire, I3D 2017](https://research.nvidia.com/labs/rtr/publication/wyman2017hashed)). Godot ships it as Alpha Hash.
- Fix 4, alpha to coverage: Main pass only, with MSAA. The shadow map has one sample.

## Blended shadows (brief)

- Godot: blended materials cast no shadow. Bevy: Blend casts a cutout at alpha 0.05. Filament and Babylon.js: an opt-in dither by alpha. Unreal: "Cast Dynamic Shadow as Masked" (sources above).
- For rocco, a later dithered shadow for BLEND parts could reuse a mask shadow pipeline with a noise threshold in place of the cutoff. rocco has no TAA. Only the 3 x 3 PCF in `sun_visibility_in` would smooth the noise (`engine/shaders/basic.glsl:204-224`).

## Cost on tile-based GPUs

- Apple: HSR puts fragments from shaders that discard or write depth in a "feedback" class. "Alpha tested foliage falls into this category." Draw opaque, then feedback, then translucent ([WWDC20 10632](https://developer.apple.com/videos/play/wwdc2020/10632/)). Apple's [TBDR article](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering) says A11 and later GPUs "improve fragment discard performance", with no figure.
- Arm Mali: "Do not use discard in the fragment shader, as it forces a late ZS test." Render alpha-tested geometry front-to-back with depth testing on. The Fragment Prepass of Mali-G725 and later handles discard, but the guide still says to minimise it. For shadow maps, use a tightly packed position-only buffer ([Arm GPU Best Practices 101897, issue 10](https://documentation-service.arm.com/static/67a62b17091bfc3e0a947695): sections "Fragment Prepass", 5.6 and 10.12).
- Qualcomm Adreno: early Z rejection is off when "Discard" is used. A discard draw turns off LRZ writes for that draw. Run discard shaders after the opaque draws. For depth-only rendering, "use an empty fragment shader" so the driver can use Fast-Z ([Adreno best practices](https://docs.qualcomm.com/doc/80-78185-2/topic/mobile_best_practices.html)).
- Imagination PowerVR: an alpha-tested primitive "cannot write data to the depth buffer until the fragment shader has executed". Submit opaque, then alpha-tested, then blended ([PowerVR: Do Not Use Discard](https://docs.imgtec.com/starter-guides/powervr-architecture/html/topics/rules/do-not-use-discard.html)).
- Depth-only against textured: the vendors agree on the direction, but none gives a number. A textured mask draw adds UV and colour fetch, one texture sample per fragment, and a late depth test. It also loses the empty-shader fast path on Adreno. Keep the Opaque range on the empty shader, and draw it first.

## Comparison

| Engine | Cutout shadow default | Two-sided option | Fix for thinning |
| --- | --- | --- | --- |
| Unreal | Masked clips in shadow depth (forum evidence) | Two Sided material, Shadow Two Sided per primitive | None found |
| Unity URP | Alpha Clipping discards in ShadowCaster | Render Face, same `Cull[_Cull]` | `mipMapsPreserveCoverage` (off) |
| Unity HDRP | Alpha Clipping, optional Shadow Threshold | Not checked | Same importer option |
| Godot 4 | Scissor and Hash cast cutouts. Blend casts none | `cast_shadow` Double-Sided | Alpha Hash, Alpha Antialiasing edge |
| Bevy | Mask discards in the shadow prepass. Blend at 0.05 | `cull_mode: None` | Alpha to coverage (Main pass) |
| Filament | `masked` discards in the depth variant | `doubleSided` | `masked` turns on alpha to coverage |
| three.js | `alphaTest` with `map` or `alphaMap` | `shadowSide` (default: back faces) | Alpha to coverage, 0.5 in shadows |
| Babylon.js | Alpha test in the shadow shader | `forceBackFacesOnly` | Soft transparent shadow (dither) |
| rocco | Whole shape, front faces only | None | None |

## Options for rocco

### (a) Keep whole-shape shadows

- Pipelines added: none. Draws per cascade: 1 per casting Draw. Budget: no change.
- Shader: no change. D3D: no concern.
- Risk: a fence or grate casts a solid slab. A leaf plane that faces away from the Sun casts nothing. Every engine above does better by default.

### (b) Mask shadow pipelines, one shadow draw per Mask part

- Pipelines added: 4. They are `shadow_mask` (cull BACK), `shadow_mask_double_sided` (cull NONE), and the skinned variants. They use 2 new programs that share one fragment shader. Index the shadow pipelines by `Mesh_Pipeline`, as `mesh_pipeline_desc` does for the Main pass.
- Draws per cascade: 1 depth-only draw over the Opaque range, if the Draw has Opaque parts, plus 1 draw per placed Mask part. A tree with a trunk and one leaf part goes from 1 to 2 draws per cascade. Use `Placed.parts`, not the whole mesh, so a Draw cut by the draw capacity stays in budget.
- Order: for each cascade, draw every depth-only range first, then every Mask part, by pipeline. The TBDR guides ask for this order, and it limits pipeline changes.
- Uniform budget: put the cutoff in `Shadow_Vs_Params` (64 to 80 bytes, still 1 slot of 256). Then each draw applies 1 block. The draws per Draw are at most its placed parts, so `uniform_buffer_size`, `SHADOW_UNIFORM_SLOTS` and `DRAW_LIMIT` do not change.
- Do not add a fragment uniform block. That doubles the slots of a Mask part and breaks the budget for a mesh of only Mask parts. The fix would be `SHADOW_UNIFORM_SLOTS` 2, which drops `DRAW_LIMIT` from about 1,195,000 to about 761,000 and adds 1 KiB per part at 4 cascades.
- Skin blocks: a skinned Draw applies its block once per shadow pipeline it uses. That set is part of the `Mesh_Pipeline` set that `frame_room` already counts for the Main pass. So each cascade stays under the `skinned_draw_capacity` blocks that `uniform_buffer_size` reserves per pass. Lights blocks and `UNIFORM_SPARE_SLOTS` do not change, because shadow pipelines apply no lights.
- Shader: a vertex shader that reads `pos`, `col` and `uv`. It writes `v_uv`, the vertex alpha, and the cutoff as a `flat` varying. The fragment shader samples `base_tex`, multiplies by the vertex alpha, then discards under the cutoff. The pipeline binds the part's base texture and sampler. `Submit_Shadow` needs the part and the pipeline.
- D3D: sample `base_tex` first, then discard, with no branch before the sample. The cutoff arrives as a varying, so the HLSL compiler cannot prove a branch on it uniform. This is the rule `mask_fs` already follows.
- Risk: more draws and texture binds per cascade. Late depth on the Mask draws on TBDR GPUs, including Apple silicon Macs. Thin cutouts still thin out in far cascades. A double-sided caster may need more bias against acne. The frame render tests and the fake submits change.

### (c) Cheaper options

- (c1) Two-sided whole shape. The loader orders Mask parts single-sided, then double-sided. The shadow pass draws 1 culled range and 1 range with cull NONE, with no texture. It adds 2 pipelines, at most 2 draws per Draw, and fits the same budget. It fixes leaves that face away from the Sun, but not the holes.
- (c2) A per-mesh flag set at load. A Mask part with no alpha under its cutoff, in level 0 and in the vertex colours, joins the depth-only range. Only a mesh with a real hole pays for (b). Mask parts that share a base texture and cutoff can also be one contiguous range, and so one draw.
- (c3) A Launch switch, off by default, that turns (b) on. Games that do not need cutouts pay nothing. This adds a Launch field, not a Vocabulary change.
- (c4) Coverage-preserving mips. `texture_build` scales each level's alpha to keep the coverage of level 0 at the part's cutoff. The cost is at load only, and it also helps the Main pass. A texture that parts with different cutoffs share needs one cutoff, or one copy for each.

## Recommendation

- Do (b), on by default, with the double-sided pipeline. Every surveyed engine casts cutout shadows from alpha-tested materials, and the author picks MASK on purpose.
- Add (c2), so a mesh without real holes keeps 1 shadow draw per cascade.
- Keep the cutoff in `Shadow_Vs_Params`, and use `Placed.parts`. Then the uniform buffer, `DRAW_LIMIT` and the skin-block count need no change.
- Add (c4) for Mask base textures as a separate, small task. Hashed alpha and alpha to coverage can wait.
- Measure the shadow pass before and after on an Apple silicon Mac with the `examples/mask` scene, and record the result in `docs/BENCHMARKS.md`.

## Method and limits

- Engine source was read at pinned commits: Unity Graphics `0efc28e`, Godot `fefec82`, Bevy `4c34435`, Filament `5ce4cbf`, three.js `c6a4b78`. Line numbers hold for those commits only.
- Unreal source needs an Epic account and was not read. Unreal claims come from Epic docs and one forum thread.
- The URP Render Face options and the Unreal `bCastShadowAsTwoSided` text come from search snippets. The pages were not opened.
- Apple's TBDR article and the Arm web guide render with JavaScript. This note used the WWDC20 transcript and the Arm PDF, issue 10.
- Ben Golus's alpha to coverage article returned HTTP 403. O3DE was not covered.

## Open questions

- Does Unreal's shadow depth pass clip by the opacity mask by default, and which faces does it cull for a one-sided material? Only secondary evidence was found.
- What does a textured mask shadow draw cost against a depth-only draw on Apple silicon? No vendor gives a number.
- Do desktop GPUs (NVIDIA, AMD, Intel) lose early Z for a discard draw that writes depth? No vendor document was checked.
- Does Blender's glTF exporter write a mipmap `minFilter`? If not, rocco builds no mips for those textures, and thinning does not occur.
- Does HDRP cast from both faces of a double-sided material? Not checked.
- How much extra bias does a cull NONE caster need at rocco's slope bias of -2 and normal offset of 0.05? Test it in `examples/mask`.
