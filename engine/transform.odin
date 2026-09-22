package engine

Transform :: struct {
	position: [3]f32,
	rotation: quaternion128,
	scale: [3]f32,
}

TRANSFORM_IDENTITY :: Transform {
	position = {0, 0, 0},
	rotation = 1,
	scale = {1, 1, 1},
}

transform_to_mat4 :: proc(t: Transform) -> Mat4 {
	return mat4_translate(t.position) *
		   mat4_from_quat(t.rotation) *
		   mat4_scale(t.scale)
}
