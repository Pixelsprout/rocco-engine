# 0001: Orientation crosses the seam

Status: accepted, 2026-10-13.

## Context

A Draw carried one `yaw : F32`. The host turned every mesh about +y by it.
The Camera had no up vector. The host always used +y. That was enough for
games on a flat floor.

Kula needs more. Its ball rolls about any axis and stands on the sides and
undersides of blocks. With +y as the only up, a camera that follows a ball
on a wall looks along +y and `mat4_look_at` returns NaN.

## Decision

- A Draw carries `rot : Quat`, a unit quaternion `{ x, y, z, w }`. The host
  slerps `rot` between two Scenes and builds the model matrix from it.
- The Camera carries `up : Vec3`. The host lerps `up` and normalises it.
- The host does not guess either value. If `up` is zero or lies along the
  view direction, the host uses world +y and logs once per run. This guard
  stops a NaN view matrix. Games must still set `up`.
- A Collider keeps `yaw : F32`. Collision runs in the ground plane, and
  `engine/collision.odin` does not change.
- `Quat` lives in `packages/linalg` beside `Vec3`, with `identity`,
  `from_yaw`, `from_axis_angle`, `mul` and `rotate`. `mul` is the Hamilton
  product, like Odin's `*`.

## Consequences

- Every game sets `rot` on each Draw. A flat game uses `Quat.identity` or
  `Quat.from_yaw`.
- The camera package sets `up` to world +y. A game that turns the camera
  over replaces `up` with a record update.
- Roc does no slerp. The game sends one pose per step, and the host blends.
- A game that keeps a yaw, such as the entity game, converts it at the view
  edge. Its colliders still read the yaw.
- A Draw is 64 bytes instead of 56, and a Camera is 40 bytes instead of 28.
