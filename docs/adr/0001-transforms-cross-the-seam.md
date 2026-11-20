# 0001: Transforms cross the seam

Status: accepted, 2026-10-13.
Supersedes: ADR 0002 (A scale acts along its own axes).

## Context

A Draw carried one `yaw : F32`, and the Camera had no up vector. That was
enough for games on a flat floor. Kula needs more. Its ball rolls about any
axis and stands on the sides and undersides of blocks. With +y as the only
up, a camera that follows a ball on a wall looks along +y and the look-at
matrix is NaN.

Kula also squashes its ball along the ball's up while the ball spins. A
scale along the mesh's own axes (`T · R · S`) turns with the spin, so it
cannot keep the squash along up. A non-uniform scale also tilts normals
that the model matrix turns.

## Decision

- A Draw carries `rot : Quat`, a unit quaternion. The host slerps it
  between two Scenes. Roc does no slerp: the game sends one Pose per step.
- A Draw carries `scale_rot : Quat`. The model matrix is
  `T · R · F · S · F⁻¹`, where `F` is `scale_rot`, so `scale` acts along
  the axes of `scale_rot` and `rot` then turns the result. The host slerps
  `scale_rot` as it slerps `rot`.
- The vertex shader turns normals by the inverse transpose of the model's
  linear part. A zero scale factor gives 0, not infinity.
- The Camera carries `up : Vec3`. The host lerps and normalises it. If `up`
  is zero or lies along the view direction, the host uses world +y and
  logs once per run, so the view matrix is never NaN. Games must still set
  `up`.
- `Quat` lives in `packages/linalg` beside `Vec3`.

## Considered options

- A world-space squash: an axis and an amount applied after `rot`. It fits
  Kula, but it adds a second scale to every Draw.
- A full 3×3 linear part in place of `rot` and `scale`. The host could not
  slerp it between Scenes.

## Consequences

- A game that omits `rot` or `scale_rot` gets the identity from
  `pf.Draw.default`. A flat game uses `Quat.from_yaw`.
- A world-frame squash costs the game one `Quat.conjugate(rot)`.
- The host slerps `rot` and `scale_rot` apart, so between two Scenes their
  product can drift from the world axis by a second-order amount.
- A game that keeps a yaw converts it at the view edge.
