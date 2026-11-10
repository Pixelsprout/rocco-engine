# 0034: Children attach to a Joint

Status: accepted, 2026-11-10.

## Context

The Agent Town stage prototype carries an orb over an otter's pack. The orb
sits at a fixed offset and ignores the bob of the Clip. ADR 0016 left the
game no way to read a Joint, so it cannot place a mesh on one. The host
poses each Skin once per Frame, after the game's `view`.

## Decision

- A new Node, `Attach({ draw : U64, joint : Str }, List(Node))`. Its
  children's Poses are local to the named Joint of the Draw with that draw
  id.
- The children take the Joint's world position and rot, never its scale.
  This is the rule a Group follows (ADR 0002). A game scales the child's
  own Draw.
- The Attach can sit anywhere in the tree. The parent of the Attach does not
  move it; the Joint does.
- The joint is named by its node name in the .glb, not by its index. A
  name survives a re-export of the asset.
- The host poses the Skin, then places the children in the same Frame. The
  attached mesh follows the Clip with no lag.
- If the Draw does not exist, has no Skin, or its Skin has no Joint of that
  name, the host logs once per (draw, joint) and omits the children. The
  message lists the joint names of the Skin when there is one.

## Considered options

- A Query for the Joint's world Pose (dex n4zl3t3h). Rejected for visual
  attachment: the answer comes one step later, so the orb trails every bob
  by a step. It stays as a separate task for gameplay reads, such as a
  footstep position.
- Children on a Draw. Rejected: a Draw is a leaf, and a Draw with children
  would mix two jobs in one Node.
- A joint index. Rejected: an index changes when the asset is re-exported.
- The Joint's full matrix, scale included. Rejected: a scaled rig would
  scale the attached mesh, and no other Node passes a scale on.
- Draw the children at the Draw's Pose when the joint is unknown. Rejected:
  a mesh in the wrong place looks like a bug in the game. A clear log line
  is the policy for a missing Surface Shader too.

## Consequences

- A Vocabulary change. The host and every game rebuild (ADR 0012).
- The host must place attached children after skin posing and before it
  draws them. Attached Lights, Colliders and Speakers move with the Joint as
  well.
- Each Attach sends a short string across the seam in every Scene.
