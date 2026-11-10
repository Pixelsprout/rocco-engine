# Cubemap environment lighting

`Environment.sky` selects both the background and surface lighting.
The renderer decodes the six source PNG faces as sRGB.
The background keeps the source resolution and original pixels.
The renderer adds all lighting in linear HDR.
The tone-map pass applies `Environment.exposure` once to the background and surfaces together.
Existing Ambient and direct lights remain additive.
Unlit materials keep their authored colour and emission.

## Preparation and update cost

Each loaded Sky owns three cubemaps.
The background uses the source RGBA8 sRGB faces without mipmaps.
The diffuse cubemap uses six 16 by 16 linear RGBA16F faces.
It stores cosine-integrated radiance divided by pi.
The specular cubemap uses linear RGBA16F faces with a complete mip chain.
Its base side is the smaller of the source side and 128.
Each mip uses GGX importance sampling at roughness `mip / maximum_mip`.
Both filters use 128 deterministic samples per output texel.
The specular base mip samples the source directly.
The CPU sampler reads across adjacent cubemap faces in linear light.

The specular resolution and filter sample count bound preparation and storage cost.
They approximate the lighting integral.
They do not reduce the background's source resolution.
Small bright details can show sampling error in rough reflections.
This path supports the existing LDR PNG Sky format.
It does not add an HDR source format or a GI solver.

Preparation runs once when the Pack loads the Sky.
Changing `Environment.sky` among loaded skies changes bindings and metadata only.
No convolution or lighting texture upload runs each Frame.
A sky blend draws into two blend cubes, described in "Sky blend".
Each lit fragment adds one diffuse sample and one explicit-LOD specular sample.
A missing Sky skips both samples through a uniform branch.

At a source side of at least 128, the two lighting cubes contain 1,060,848 logical bytes.
The diffuse cube uses 12,288 bytes.
The specular cube uses 1,048,560 bytes across eight mips.
Driver alignment and retained GPU resources can increase physical storage.
The source background adds `6 * side * side * 4` bytes.
A Sky uses three images, three views, and three samplers.
The renderer reserves these resources from the configured Sky capacity.
The renderer also owns one black fallback cube.

## Shader contract

The built-in material and published Surface wrapper use identical environment inputs and equations.
The fragment `fs_params` block contains 96 bytes within its 128-byte ceiling.
Its final vector is `environment_params = (enabled, specular_max_lod, 0, 0)`.
The clustered `fs_lights` block remains 512 bytes.
Fragment view and sampler slot 6 contains the diffuse cube.
Fragment view and sampler slot 7 contains the specular cube.
The four game texture slots remain 8 through 11.
The eight engine textures and four game textures fit the portable twelve-texture ceiling.
GL storage bindings remain compact at 0 through 2.

The diffuse response uses the surface normal and the nonmetallic base colour.
Schlick Fresnel removes reflected energy from the diffuse term.
Indirect reflectance uses the magnitude of the normal-view cosine on either side of the shading normal.
Visible geometry can have a view-opposed normal after canopy softening or normal mapping.
The signed normal still selects diffuse irradiance direction.
Direct lighting and geometric shadow bias retain their existing equations.
The specular response uses `reflect(-view, normal)` and `roughness * specular_max_lod`.
The existing split-sum BRDF fit scales that filtered radiance.
Material occlusion scales both environment terms.
Blend materials scale diffuse coverage while retaining specular response.
Surface hooks can change the normal, roughness, metallic value, colour, and occlusion before this calculation.
The `rocco_environment(direction, lod)` helper samples the specular cube at an explicit mip.
It returns zero when the Sky is absent.

The renderer selects the Sky before any surface submission.
A custom Surface renderer must use this same selected Sky and metadata.
Use `sky_lighting_params` to encode the metadata.
It must bind both reflected cube resources with the matching filtering samplers.

## Sky blend

`Environment.sky_blend` blends from `sky` toward `sky_blend.to` by `sky_blend.amount`.
The host clamps the amount to 0 through 1 and logs once when it clamps.
A `to` of 0, an unknown `to`, or an amount of 0 draws `sky` alone.
An amount of 1 draws `to` alone, with no blend work.
A `sky` of 0 with a known `to` blends from the clear colour and black lighting.

The background shader samples both background cubes and mixes them.
The lighting uses two blend cubes that the renderer makes on the first blend.
The diffuse blend cube has six 16 by 16 RGBA16F faces.
The specular blend cube has six 128 by 128 RGBA16F faces and eight mips.
Mip `m` reads each source at `m / 7` of that source's last mip.
One pass per face and mip writes the mix, 54 passes in all.
The passes run before the shadow pass, only when the skies or the amount change.
A blend that holds still draws no passes.

Mesh and Surface shaders read the blend cubes in slots 6 and 7.
Their metadata is `(1, 7, 0, 0)`.
So the shader contract does not change, and each lit fragment still takes one diffuse and one specular sample.

## Sky fog

`Environment.fog.sky` mixes the fog colour into the background.
The host clamps it to 0 through 1 and logs once when it clamps.
The mix is `fog.sky * (1 - max(direction.y, 0))^4`.
So the horizon and every direction below it take the full amount, and overhead takes none.
Sky fog does not depend on `fog.amount`, and it does not change the lighting.
The clear colour never fogs.

## Ownership and failures

The Sky table owns each Sky's name, source pixels, prepared pixels, and GPU textures.
Pack ownership uses the existing shared-asset reference counts.
Two Packs that reference the same Sky share its complete resource set.
Removing the final Pack reference destroys all three textures and advances the slot generation.
Sokol retains backend resources until their submitted GPU work can finish.
The next Frame resolves the new Sky generation before it submits surfaces.

Sky id zero selects no background or environment lighting.
An unknown or stale Sky id also selects neither result.
The host logs that invalid id once.
It binds its black cubes with zero metadata.
It preserves explicit Ambient and direct lights.
It never selects another loaded Sky as a substitute.
A missing or invalid PNG face rejects the entire Sky before table insertion.
A Pack reload receives a new generation and prepares all lighting resources again.

Sky and standalone Image loads use separate growing temporary arenas.
The loader releases these arenas on success and failure.
Returned error text uses the caller's temporary allocator.
Owned source pixels retain their original dimensions until upload.
The 1024-face regression test exceeds the fixed Frame arena's scratch capacity without reducing source resolution.
After upload, the Sky releases its CPU source and prepared pixels.

## Validation

The reference game contains four dielectric and four metallic spheres.
Roughness increases from 0.05 through 0.25 and 0.5 to 1.
It includes one unlit reference square and no Light nodes.
Its two cubemaps exchange warm and cool colour channels.
B steps the blend from warm toward cool through 0.5 and 1. F turns on a rose sky fog.
The Bridge check verifies colour changes, roughness peaks, exposure, absence, unload, and exact reload recovery.
It also verifies that a blend of 0.5 puts the background and every sphere between the two skies.
It verifies that a blend of 1 matches the cool sky exactly.
It verifies that sky fog changes the horizon far more than the top of the view.
The same check runs in Metal, GL, and D3D CI jobs.
Cross-compilation does not establish native screenshot agreement.

Run these commands from the repository root:

```sh
python3 scripts/build_shader.py --shdc build/shader-tools/sokol-shdc
roc scripts/build.roc host --release
roc scripts/build.roc game environment-lighting
python3 scripts/environment_check.py
python3 scripts/shader_assets/native.py --shdc build/shader-tools/sokol-shdc
ROCCO_SHDC=build/shader-tools/sokol-shdc python3 -m unittest scripts/test_shader_assets.py scripts/test_build_shader.py
odin test engine -debug
```
