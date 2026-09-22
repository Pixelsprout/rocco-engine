package engine

import "core:fmt"
import "core:math"

probe_point :: proc(label: string, m: Mat4, p: [4]f32) {
	// multiply and then print the clip-space result and result after dividing by w
	c := m * p
	ndc := [3]f32{ c.x / c.w, c.y / c.w, c.z / c.w }

	fmt.printfln("%s: clip %v, ndc %v", label, c, ndc)
}

probe_basis :: proc(label: string, m: Mat4) {
	r := [3]f32{m[0, 0], m[0, 1], m[0, 2]}
	u := [3]f32{m[1, 0], m[1, 1], m[1, 2]}
	b := [3]f32{m[2, 0], m[2, 1], m[2, 2]}

	det := v3_dot(v3_cross(r, u), b)

	fmt.printfln("%s: |r| %.4f |u| %.4f |b| %.4f",
		label, v3_length(r), v3_length(u), v3_length(b))
	fmt.printfln("%s: r.u %.4f r.b %.4f u.b %.4f det %+.4f",
		label, v3_dot(r, u), v3_dot(r, b), v3_dot(u, b), det)
}

probe_transform :: proc(label: string, m: Mat4) {
	x4 := m * [4]f32{1, 0, 0, 0}
	y4 := m * [4]f32{0, 1, 0, 0}
	x := [3]f32{x4.x, x4.y, x4.z}
	y := [3]f32{y4.x, y4.y, y4.z}

	x_length := v3_length(x)
	y_length := v3_length(y)
	dot_product := v3_dot(x, y)
	cos_angle := dot_product / (x_length * y_length)
	angle := math.to_degrees(math.acos(cos_angle))

	fmt.printfln("%s: |x| %.4f |y| %.4f x.y %+.4f angle %.4f deg",
		label, x_length, y_length, dot_product, angle)
}
