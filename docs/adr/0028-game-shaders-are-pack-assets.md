# 0028: Game shaders are Pack assets

Status: accepted, 2026-11-05.

## Context

The immersive village needs game-authored shaders, such as wind on grass
and a selection outline, that work with a published platform bundle. If the
engine generated source for each shader, every shader change in a game
would need an engine build.

## Decision

- The game's asset build compiles shaders. Authors write GLSL hooks, and
  the compiler in `platform/shader-tools` ships with the platform and
  compiles them through sokol-shdc for every backend. Invalid source stops
  the build.
- The engine loads Shader assets through Packs and owns their GPU
  resources (ADR 0003). A new Shader asset needs no engine rebuild.
- Each Shader asset records the version of the shader contract it targets
  and its binding layout. The engine rejects an incompatible asset with a
  clear log. `docs/guides/shader-contract.md` is the contract.
- There are two kinds. A Surface shader sets vertex movement, normals,
  material properties and the light response. A Post shader runs at a
  declared stage: in HDR before bloom, or after the tone map before the UI.
- The engine supplies transforms, lights, shadows and the pass variants.
  Default hooks keep the built-in PBR look. A Surface shader inherits the
  imported material unless the game overrides it.
- A game picks the look through plain values in the Scene, consistent with
  the Seam. The game build generates typed Roc helpers from shader
  declarations. A value has Scene, Material or Draw scope, and an omitted
  value takes its declared default.
- Meshes keep named Material slots. A Draw can override one slot or its
  whole material, and other slots keep their imported material.
- A shader declares its largest vertex displacement, and culling bounds
  grow by it.
- Colour, shadow and selection passes share one render time derived from
  the simulation, so fixed Bridge steps repeat the same shader pose.
- The engine gives a Post shader the Selection input only when an enabled
  effect asks for it. The Post shader owns the outline style and whether
  hidden parts show.
- Shader reload replaces the colour, shadow and selection variants
  together at a Frame boundary. It accepts only changes that keep the
  shader interface. An interface change needs a game rebuild and restart.
  A failed reload keeps the last valid shader and logs the error.
- A Shader asset that fails to load logs clearly. The engine substitutes no
  fallback: it omits the affected Mesh parts from every pass, or skips the
  Post effect.

## Considered options

- Generate engine source for each game shader. Rejected: each shader change
  would need an engine build, so a game could not ship against a published
  platform.
- A fallback shader or material on failure. Rejected: a wrong look hides
  the error. A clear log line and a missing part make it plain.
- Engine-drawn outlines, visible-only or through walls. Rejected: the
  engine supplies selection coverage and depth, and the game's Post shader
  chooses the policy.
- Custom sky shaders and arbitrary render passes. Rejected for now: they
  add resource and scheduling cost the reference scene does not need. The
  sky stays a cubemap.

## Consequences

- Normal buffers, motion vectors and frame history need later contract
  versions.
- The importer must keep source material identity before it merges or
  reorders Mesh parts.
