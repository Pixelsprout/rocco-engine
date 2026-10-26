# 0016: Skinned meshes are posed in the host

Status: accepted, 2026-10-26.

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
  0 to 1; the host samples both Clips and mixes each Joint, with lerp for
  translation and scale and slerp for rotation. The host clamps the fade to
  [0, 1]. At 0 it samples only `clip`, and at 1 only `fade_clip`.
- Clip id 0 on one side of a fade gives each Joint its rest TRS from the
  file on that side, and the mix runs as usual. Clip id 0 on both sides
  draws the bind pose.
- A time before the first key of a channel holds the first key, and a time
  after the last key holds the last key. The host never wraps a time.
- Each Manifest mesh entry gains `clips : List({ name, id, duration })`.
  Clip ids are unique across a Pack and start at 1. A Draw that names a
  Clip of another mesh on either side draws the bind pose and logs once
  for each Clip id, even when the fade leaves that side out.
- The loader keeps a skinned mesh in bind-pose space. A .glb with a Skin
  loads as one skinned mesh. More than one Skin, a mix of skinned and
  unskinned mesh nodes, more than 64 Joints, and CUBICSPLINE keys each fail
  the load with an error. Files with no Skin load as before.
- The loader orders the Joints parent first and folds the non-Joint nodes
  above a Joint into a fixed base matrix, so one pass in index order poses
  the Skin.
- Channels: translation, rotation and scale, with LINEAR and STEP keys.
  Clips are in place; the Model owns the position.
- The host skins on the GPU. A second vertex layout, `Skinned_Vertex`, adds
  four joint indices and four weights as `u8x4` to the 48-byte vertex.
  Skinned meshes have their own pipeline and their own shadow pipeline. A
  skin uniform block per skinned Draw holds up to 64 Joint matrices.
  Normals use the skin matrix, so a Joint must have no non-uniform scale.
- The host computes the skin matrices on the CPU once per Frame for each
  skinned Draw, and both passes upload them. In each pass the rigid Draws
  come first and the skinned Draws follow, so each pass switches pipeline
  at most once.
- The uniform buffer holds skin blocks for at most 256 skinned Draws per
  Frame, or `capacity.draws` if that is lower. Past it, the host drops the
  skinned Draws and logs once. The skin blocks take their space from the
  same 2 GiB buffer, so the largest `capacity.draws` shrinks.
- A skinned mesh's box is padded at load by 25% of its largest extent. The
  engine has no culling, so the box serves the shadow box.
- Between two Scenes, the renderer blends the time when the Clip is the
  same in both and the time did not go back, as it does when the game wraps
  a loop. It blends the fade time by the same rule with the fade Clip. It
  blends the fade only when both the Clip and the fade Clip are the same in
  both. Otherwise it takes the current values.

## Considered options

- Blend on the Roc side. Rejected: the game would need every key, would
  sample every Joint in Roc, and would send the pose across the seam each
  frame. The Model keeps the policy, the weight; the host does the math.
- A fade in a later milestone. Rejected: a second Vocabulary change.
- The Draw names Loop or Once, and the host wraps. Rejected: a hidden policy
  in the host. The game has the duration.
- A joint texture or storage buffers for the Joint matrices. Rejected for
  now: no other part of the engine uses them, and the tutorial character
  needs about 12 Joints. Either is a contained change if a Skin needs more
  than 64 Joints.
- Root motion. Rejected: the Model owns the position.
- "Animation" as the name of a Clip. Rejected: it also names the feature
  and any value the Model moves each step.

## Consequences

- A Skin with more than 64 Joints and a file that mixes skinned and
  unskinned meshes do not load. The host skips morph weight channels and
  the channels of nodes that are not Joints. Each is a follow-up task.
- The game cannot read a Joint's position back, so it cannot attach a mesh
  to a hand yet.
- Each skinned Draw costs one 4 KB uniform block per pass.
- A Scene with more than 256 skinned Draws drops the rest. A joint texture
  or storage buffers would lift the cap.
- On Linux, the skinned vertex shader needs 268 vec4 of uniforms, and
  OpenGL 4.3 promises 256. Mesa gives more, but a driver at the minimum
  may fail to build the skinned shader.
