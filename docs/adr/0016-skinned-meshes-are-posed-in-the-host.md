# 0016: Skinned meshes are posed in the host

Status: accepted, 2026-10-26.

## Context

Milestone 24 gives the tutorial character a walk. A skinned .glb holds a
Skin and Clips: timed keys for each Joint. Something must sample the keys
at a time, mix two Clips for a fade, and move the vertices. `step` must
stay pure, and each Vocabulary change rebuilds the host and every game.

## Decision

- The Model owns the time. A Draw carries a `pose : { clip, time,
  fade_clip, fade_time, fade }`. Clip id 0 is no Clip, and the mesh draws
  in its bind pose.
- The fade is in the same Vocabulary change. The Model moves the weight
  from 0 to 1. The host samples both Clips and mixes each Joint.
- The host never wraps a time. A time outside a channel's keys holds the
  nearest key. The game wraps a looping time itself, with the Clip
  duration from the Manifest.
- Each Manifest mesh entry lists its Clips with a name, an id and a
  duration. Clip ids are unique across a Pack.
- Clips are in place. The Model owns the position.
- The host skins on the GPU. It computes the Joint matrices on the CPU once
  per Frame for each skinned Draw.
- Between two Scenes, the renderer blends a time only when its Clip is the
  same in both and the time did not go back, so a wrapped loop does not
  play backwards.

## Considered options

- Blend on the Roc side. Rejected: the game would need every key, would
  sample every Joint in Roc, and would send the pose across the seam each
  frame. The Model keeps the policy, the weight; the host does the math.
- A fade in a later milestone. Rejected: a second Vocabulary change.
- The Draw names Loop or Once, and the host wraps. Rejected: a hidden policy
  in the host. The game has the duration.
- A joint texture or storage buffers for the Joint matrices. Rejected for
  now: the tutorial character needs about 12 Joints. Either is a contained change if a Skin needs more
  Joints than a uniform block holds.
- Root motion. Rejected: the Model owns the position.
- "Animation" as the name of a Clip. Rejected: it also names the feature
  and any value the Model moves each step.

## Consequences

- The Joint matrices travel in a uniform block, so the Joint count of a
  Skin and the skinned Draws per Frame have caps.
- Normals use the skin matrix, so a Joint must have no non-uniform scale.
