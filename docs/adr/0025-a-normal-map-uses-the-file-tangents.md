# 0025: A normal map uses the file's tangents

Status: accepted, 2026-11-03. Milestone 36.

## Context

Milestone 36 draws glTF normal maps. A tangent-space normal map is baked
against a tangent frame: the directions in which u and v grow across each
face, and the side the bitangent points to. The renderer must rebuild the
same frame, or the light bends the wrong way where the frames differ.

glTF stores the frame as the optional `TANGENT` attribute, a VEC4 with the
handedness in w. Its spec says that a client with no `TANGENT` should make
MikkTSpace tangents. Blender bakes normal maps in MikkTSpace, and its glTF
export writes `TANGENT` only when the author ticks Data > Mesh > Tangents.
So many files that Agent Town will load have a normal map and no `TANGENT`.

## Decision

- Every `Vertex` carries `tangent: [4]f32`, with the glTF handedness:
  bitangent = cross(normal, tangent.xyz) * w. The vertex grows from 48 to 64
  bytes, and every pipeline keeps one layout.
- The loader reads `TANGENT` when the primitive has it. xyz turns with the
  node, and w flips under a mirroring node.
- Only a normal-mapped primitive with no `TANGENT` gets generated tangents,
  by Lengyel's method: the sums of dP/du and of -dP/dv over the vertex's
  triangles, Gram-Schmidt against the normal, and w from the side of the
  second sum, which points up the image. It notes `Generated_Tangents`: "a
  normal-mapped primitive has no TANGENT, so the host makes tangents that
  may not match the baker; export tangents".
- Every other primitive gets the placeholder (1, 0, 0, 1) and no note. It
  binds the flat normal image, so the tangent does not change its light.
- Cube, Sphere, Plane and Fallback have exact analytic tangents.
- The guide tells authors to tick Blender's Tangents export option.

## Considered options

- MikkTSpace at load time. Rejected for now: it is the only method that
  matches Blender's bake exactly, but it is a large algorithm that the host
  would carry in Odin or as a C library. It welds vertices and splits them
  again at seams, so it can change the vertex count after the loader has
  read the file. The export option gives the same tangents at no cost, and
  the note tells the author when the file lacks them. It stays on the
  roadmap's Later list.
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
- The vertex buffers grow by a third. Packed tangents can win the space back
  later.
- `examples/glow`'s panel writes `TANGENT`, and the Bridge check fails if
  its tangents turn round.
