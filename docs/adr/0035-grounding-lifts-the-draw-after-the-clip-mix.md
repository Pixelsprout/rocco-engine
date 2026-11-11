# 0035: Grounding lifts the Draw after the Clip mix

Status: accepted, 2026-11-11.

## Context

ADR 0016 poses each Skin in the host: it samples two Clips and mixes them per
Joint by the fade. A per-Joint mix of two different leg poses shortens the
leg. The Agent Town otter sinks 6.3 cm in a walk-to-run fade, and 3.7 cm at a
matched phase. Its Clips are baked at every frame, so the fix is not in the
keys. The otter walks on flat ground and its run has airborne phases. No
Clip marks its foot contacts.

## Decision

- A Draw gains `ground : { feet : List(Str) }`. An empty list, the default,
  turns Grounding off.
- Each entry is the node name of a foot Joint in the .glb, as an Attach names
  its Joint (ADR 0034).
- After the Clip mix, the host compares each named foot Joint's height in
  model space with its height in the bind pose. If a foot is below its bind
  height, the host lifts the whole Draw by the depth of the lowest foot.
- The host never lowers the Draw. A jump or a bound keeps its airborne phase.
- The lift applies at every step while `feet` is not empty, not only during
  a fade. A Clip that dips a foot below its bind height is lifted too.
- The lift is in model units, before the Draw's scale. Attached children and
  shadows follow the lifted Joints.
- An unknown foot name logs once per (draw, joint) and is skipped.

## Considered options

- Two-bone IK with foot contacts. Deferred: it also fixes sliding and contact
  snaps, but it needs contact data that no Clip has yet. It stays a dex task.
- Lift and lower. Rejected for now: lowering flattens airborne phases. On
  uneven ground a foot reaches down, and the IK task must then move the
  pelvis both ways.
- Grounding in the game, through a Joint read-back. Rejected: the read-back
  is one step late, and the game would need a way to override Joints.
- Joint ids resolved through the Manifest. Rejected: names match Attach and
  need no Manifest change.
- A sole offset per foot, or the lowest skinned vertex. Rejected: the bind
  pose already stands on the ground, and a vertex pass costs CPU time.

## Consequences

- A Vocabulary change. The host and every game rebuild (ADR 0012).
- Each grounded Draw sends a few short strings across the seam in every
  Scene.
- A rig must bind with its feet on the ground for Grounding to work.
- Phase sync stays in the game, through `Mesh.synced_time`. It stops the
  legs scissoring in a fade, but it does not stop the sink.
