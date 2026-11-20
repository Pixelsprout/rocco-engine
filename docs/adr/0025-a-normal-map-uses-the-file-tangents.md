# 0025: A normal map uses the file's tangents

Status: accepted, 2026-11-03.

## Context

The host draws glTF normal maps. A tangent-space normal map is baked
against a tangent frame: the directions in which u and v grow across each
face, and the side the bitangent points to. The renderer must rebuild the
same frame, or the light bends the wrong way where the frames differ.

glTF stores the frame as the optional `TANGENT` attribute, with the
handedness in w. Its spec says that a client with no `TANGENT` should make
MikkTSpace tangents. Blender bakes normal maps in MikkTSpace, but its glTF
export writes `TANGENT` only when the author ticks Data > Mesh > Tangents.
So many files have a normal map and no `TANGENT`.

## Decision

- Every vertex carries a tangent with the glTF handedness, so every
  pipeline keeps one vertex layout.
- The loader reads `TANGENT` when the primitive has it.
- Only a normal-mapped primitive with no `TANGENT` gets generated tangents,
  by Lengyel's method. The loader notes `Generated_Tangents`, which tells
  the author to export tangents.
- Every other primitive gets a placeholder tangent and no note. It binds
  the flat normal image, so the tangent does not change its light.
- Primitives and the Fallback mesh have exact analytic tangents.
- The guide tells authors to tick Blender's Tangents export option.

## Considered options

- MikkTSpace at load time. Rejected for now: it is the only method that
  matches Blender's bake exactly, but it is a large algorithm that the host
  would carry in Odin or as a C library. It welds vertices and splits them
  again at seams, so it can change the vertex count after the loader has
  read the file. The export option gives the same tangents at no cost, and
  the note tells the author when the file lacks them.
- A screen-space cotangent frame from derivatives in the fragment shader.
  Rejected: it needs no tangents, but it matches no baker, shows the
  triangles on a curved face, and costs shader work for every pixel.
- Lengyel tangents for every primitive. Rejected: a primitive with no
  normal map reads no tangent, so the work and the note would serve nothing.

## Consequences

- A file that exports `TANGENT` draws as baked, on every platform.
- A file without it still draws, and its normal map is right on flat faces.
  On curved faces, UV seams and mirrored UVs the light can show creases,
  and the log names the fix.
- Every vertex buffer grows to hold the tangent, whether or not the mesh
  has a normal map.
