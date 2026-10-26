# 0016: Skinned meshes are posed in the host

Status: draft, 2026-10-26. Milestone 24 accepts it when it lands.

## Context

Milestone 24 gives the tutorial character a walk. A skinned .glb holds a
Skin and Clips: timed keys for each Joint. Something must sample the keys
at a time, mix two Clips for a fade, and move the vertices. `step` must
stay pure, and each Vocabulary change rebuilds the host and every game
(ADR 0012).

## Decision

- The Model owns the time. A Draw gains one field, `pose : { clip, time,
  fade_clip, fade_time, fade }`. `pf.Draw.default` gives all zeros: Clip
  id 0 is no Clip, and the mesh draws in its bind pose. The game wraps a
  looping time itself with the duration from the Manifest.
- The fade is in the one Vocabulary change. The Model moves the weight from
  0 to 1; the host samples both Clips and mixes each Joint, with slerp for
  rotations.
- Each Manifest mesh entry gains `clips : List({ name, id, duration })`.
  Clip ids are unique across a Pack and start at 1. A Draw that names a
  Clip of another mesh draws the bind pose and logs once.
- The loader keeps a skinned mesh in bind-pose space. A .glb with a Skin
  loads as one skinned mesh. More than one Skin, a mix of skinned and
  unskinned mesh nodes, more than 64 Joints, and CUBICSPLINE keys each fail
  the load with an error. Files with no Skin load as before.
- Channels: translation, rotation and scale, with LINEAR and STEP keys.
  Clips are in place; the Model owns the position.
- The host skins on the GPU. A second vertex layout, `Skinned_Vertex`, adds
  four joint indices and four weights as `u8x4` to the 48-byte vertex.
  Skinned meshes have their own pipeline and their own shadow pipeline. A
  skin uniform block per skinned Draw holds up to 64 Joint matrices.
  Normals use the skin matrix, so a Joint must have no non-uniform scale.
- A skinned mesh's box is padded at load by 25% of its largest extent, for
  culling and the shadow box.
- Between two Scenes, the renderer blends the time and the fade when the
  Clip is the same in both. Otherwise it takes the current values.

## Considered options

- Blend on the Roc side. Rejected: the game would need every key, would
  sample every Joint in Roc, and would send the pose across the seam each
  frame. The Model keeps the policy, the weight; the host does the math.
- A fade in a later milestone. Rejected: a second Vocabulary change.
- The Draw names Loop or Once, and the host wraps. Rejected: a hidden policy
  in the host. The game has the duration.
- A joint texture or storage buffers for the Joint matrices. Rejected for
  now: no other part of the engine uses them, and the tutorial character
  needs about 12 Joints. Either is a contained change if a rig needs more
  than 64.
- Root motion. Rejected: the Model owns the position.
- "Animation" as the name of a Clip. Rejected: it also names the feature
  and any value the Model moves each step.

## Consequences

- A rig with more than 64 Joints, morph targets, Clips on nodes with no
  Skin, and files that mix skinned and unskinned meshes do not load. Each
  is a follow-up task.
- The game cannot read a Joint's position back, so it cannot attach a mesh
  to a hand yet.
- Each skinned Draw costs one 4 KB uniform block per pass.
