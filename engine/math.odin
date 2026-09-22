package engine

import "core:math"
Mat4 :: matrix[4, 4]f32

mat4_identity :: proc() -> Mat4 {
	return Mat4{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

mat4_perspective :: proc(fovy, aspect, near, far: f32) -> Mat4 {
	f := 1.0 / math.tan(fovy / 2.0)

	a := far / (near - far)
	b := far * near / (near - far)

	return Mat4{
		f / aspect, 0, 0, 0,
		0, f, 0, 0,
		0, 0, a, b,
		0, 0, -1, 0,
	}
}

mat4_perspective_reversed :: proc(fovy, aspect, near, far: f32) -> Mat4 {
	f := 1.0 / math.tan(fovy / 2.0)

	a := near / (far - near)
	b := near * far / (far - near)

	return Mat4{
		f / aspect, 0, 0, 0,
		0, f, 0, 0,
		0, 0, a, b,
		0, 0, -1, 0,
	}
}

mat4_perspective_reversed_infinite :: proc(fovy, aspect, near: f32) -> Mat4 {
	f := 1.0 / math.tan(fovy / 2.0)

	return Mat4{
		f / aspect, 0, 0, 0,
		0, f, 0, 0,
		0, 0, 0, near,
		0, 0, -1, 0,
	}
}

mat4_rotate_z :: proc(rad: f32) -> Mat4 {
	c := math.cos(rad)
	s := math.sin(rad)

	return Mat4{
		c, -s, 0, 0,
		s, c, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

mat4_translate :: proc(v: [3]f32) -> Mat4 {
	return Mat4{
		1, 0, 0, v.x,
		0, 1, 0, v.y,
		0, 0, 1, v.z,
		0, 0, 0, 1,
	}
}

mat4_scale :: proc(v: [3]f32) -> Mat4 {
	return Mat4{
		v.x, 0, 0, 0,
		0, v.y, 0, 0,
		0, 0, v.z, 0,
		0, 0, 0, 1,
	}
}

mat4_from_quat :: proc(q: quaternion128) -> Mat4 {
	y_sq := q.y * q.y
	z_sq := q.z * q.z
	x_sq := q.x * q.x

	return Mat4{
		1 - 2 * (y_sq + z_sq), 2 * (q.x * q.y - q.w * q.z), 2 * (q.x * q.z + q.w * q.y), 0,
		2 * (q.x * q.y + q.w * q.z), 1 - 2 * (x_sq + z_sq), 2 * (q.y * q.z - q.w * q.x), 0,
		2 * (q.x * q.z - q.w * q.y), 2 * (q.y * q.z + q.w * q.x), 1 - 2 * (x_sq + y_sq), 0,
		0, 0, 0, 1,
	}
}

mat4_look_at :: proc(eye, target, up: [3]f32) -> Mat4 {
	f := v3_normalize(target - eye)
	r := v3_normalize(v3_cross(f, up))
	u := v3_cross(r, f)

	return Mat4{
		r.x, r.y, r.z, -v3_dot(r, eye),
		u.x, u.y, u.z, -v3_dot(u, eye),
		-f.x, -f.y, -f.z, v3_dot(f, eye),
		0, 0, 0, 1,
	}
}

v3_dot :: proc(a, b: [3]f32) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

quat_dot :: proc(a, b: quaternion128) -> f32 {
	return a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z
}

v3_cross :: proc(a, b: [3]f32) -> [3]f32 {
	return [3]f32{
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x,
	}
}

v3_length :: proc(v: [3]f32) -> f32 {
	return math.sqrt(v3_dot(v, v))
}

v3_normalize :: proc(v: [3]f32) -> [3]f32 {
	return v / v3_length(v)
}

quat_from_axis_angle :: proc(axis: [3]f32, rad: f32) -> quaternion128 {
	c := math.cos(rad / 2.0)
	s := math.sin(rad / 2.0)

	n := v3_normalize(axis)

	return quaternion(w = c, x = n.x * s, y = n.y * s, z = n.z * s)
}

// divide all four components by sqrt of the sum of squares
quat_normalize :: proc(q: quaternion128) -> quaternion128 {
	len := math.sqrt(q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z)
	return quaternion(w = q.w / len, x = q.x / len, y = q.y / len, z = q.z / len)
}

quat_nlerp :: proc(a, b: quaternion128, t: f32) -> quaternion128 {
	w := a.w + (b.w - a.w) * t
	x := a.x + (b.x - a.x) * t
	y := a.y + (b.y - a.y) * t
	z := a.z + (b.z - a.z) * t
	return quat_normalize(quaternion(w = w, x = x, y = y, z = z))
}

quat_slerp :: proc(a, b: quaternion128, t: f32) -> quaternion128 {
	b_ := b
	cos_theta := quat_dot(a, b_)

	// flip b_ if negative along with cos_theta
	if cos_theta < 0 {
		b_ = -b_
		cos_theta = -cos_theta
	}

	if cos_theta > 0.9995 {
		return quat_nlerp(a, b_, t)
	}

	omega := math.acos(cos_theta)

	w := a.w * math.sin((1 - t) * omega) + b_.w * math.sin(t * omega)
	x := a.x * math.sin((1 - t) * omega) + b_.x * math.sin(t * omega)
	y := a.y * math.sin((1 - t) * omega) + b_.y * math.sin(t * omega)
	z := a.z * math.sin((1 - t) * omega) + b_.z * math.sin(t * omega)
	return quat_normalize(quaternion(w = w, x = x, y = y, z = z))
}

// How far apart two orientations are in degrees
apart :: proc(a, b: Mat4) -> f32 {
	sum := f32(0)
	for k in 0..<3 {
		for r in 0..<3 {
			sum += a[k, r] * b[k, r]
		}
	}

	return math.to_degrees(math.acos(math.clamp((sum - 1) / 2, -1, 1)))
}
