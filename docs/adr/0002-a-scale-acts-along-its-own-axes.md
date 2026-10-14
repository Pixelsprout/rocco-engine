# 0002: A scale acts along its own axes

Status: accepted, 2026-10-14.

## Context

The host built each model matrix as `T · R · S`. The scale acted along the
mesh's axes, before `rot`.

Kula squashes its ball along the ball's up (`games/kula/SPEC.md`, "Idle
bob"). The ball's `rot` is its spin. A scale along a mesh axis turns with
the spin, so `T · R · S` cannot keep the squash along up. The original
builds `Orient · Morph · Spin` for this.

The shader also turned normals by the model matrix. Under a non-uniform
scale that tilts them. At the bob's scale, a 45° normal is off by about 9°.

## Decision

- A Draw carries `scale_rot : Quat`. The model matrix is
  `T · R · F · S · F⁻¹`, where `F` is `scale_rot`.
- The host slerps `scale_rot` between two Scenes, as it slerps `rot`. When
  the two ends are equal, it skips the slerp.
- The vertex shader takes `normal_model`, the inverse transpose of the
  model's linear part. The host builds it from the same rotations and the
  reciprocal scale. A zero scale factor gives 0, not infinity.

Two other options were rejected:

- A world-space squash, an axis and an amount applied after `rot`. It fits
  Kula, but it adds a second scale to every Draw.
- A full 3×3 linear part in place of `rot` and `scale`. The host could not
  slerp it between Scenes.

## Consequences

- Every game sets `scale_rot` on each Draw. Most use `Quat.identity`.
- A world-frame squash costs the game one `Quat.conjugate(rot)`.
- The host slerps `rot` and `scale_rot` apart. Between two Scenes their
  product can drift from the world axis by a second-order amount.
- A Draw is 80 bytes instead of 64. `Vs_Params` grows by one `mat4`.
- `packages/linalg` gains `Quat.conjugate` and `Quat.between`.
