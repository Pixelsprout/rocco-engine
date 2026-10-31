package engine

import "core:math"
import "core:math/linalg"

// With 2 to 4 cascades, the depth along the view where the last cascade ends.
SHADOW_DISTANCE :: f32(150)
// 0 is a linear split, 1 is a log split.
CASCADE_SPLIT_WEIGHT :: f32(0.5)
// The share of each cascade's depth range that blends into the next cascade.
CASCADE_BLEND :: f32(0.1)
CASCADE_RADIUS_STEP :: f32(1.0 / 16)

Cascade_Sphere :: struct {
	center: [3]f32,
	radius: f32,
}

// lo and hi are the bounds of the orthographic view in the Sun's view space.
Cascade_View :: struct {
	view_proj: Mat4,
	lo, hi:    [3]f32,
}

// The far depth of each cascade, by the practical split scheme. The last
// cascade ends at far exactly, and so does every entry past count.
cascade_splits :: proc(near, far: f32, count: int, weight: f32) -> (splits: [MAX_CASCADES]f32) {
	for i in 1 ..= count {
		share := f32(i) / f32(count)
		linear := near + (far - near) * share
		log := near * math.pow(far / near, share)
		splits[i - 1] = linear + (log - linear) * weight
	}
	for i in count - 1 ..< MAX_CASCADES {
		splits[i] = far
	}
	return
}

// Cascade index starts before the split of the cascade before it, so it also
// covers that cascade's whole blend band. The shader measures cascade 0 from
// depth 0, so its band does too.
cascade_slice_near :: proc(splits: [MAX_CASCADES]f32, near: f32, index: int) -> f32 {
	if index == 0 {
		return near
	}
	prev := splits[index - 2] if index > 1 else 0
	return splits[index - 1] - CASCADE_BLEND * (splits[index - 1] - prev)
}

// The smallest sphere on the view axis around the view between the depths
// near and far. The radius depends only on the depths, the field of view and
// the aspect, so the texel size stays fixed while the camera moves.
cascade_sphere :: proc(camera: Camera_Pose, aspect, near, far: f32) -> Cascade_Sphere {
	// The distance of a corner of the view from its axis, per unit of depth.
	k := math.tan(camera.fov_y / 2) * math.sqrt(1 + aspect * aspect)
	depth := (far + near) * (1 + k * k) / 2
	radius: f32
	if depth >= far {
		depth = far
		radius = far * k
	} else {
		radius = math.sqrt((far - depth) * (far - depth) + far * k * far * k)
	}
	radius = math.ceil(radius / CASCADE_RADIUS_STEP) * CASCADE_RADIUS_STEP
	return {center = camera.eye + v3_normalize(camera.target - camera.eye) * depth, radius = radius}
}

light_view_of :: proc(to_light: [3]f32) -> Mat4 {
	up := UP if abs(to_light.y) < 0.99 else [3]f32{0, 0, 1}
	return mat4_look_at({}, -to_light, up)
}

// The box in the Sun's view space around the 8 corners of box under model.
light_box :: proc(light_view: Mat4, model: Mat4, box: Box) -> Box {
	to_view := light_view * model
	lo := [3]f32{max(f32), max(f32), max(f32)}
	hi := -lo
	for corner in 0 ..< 8 {
		c := [3]f32 {
			box.max.x if corner & 1 != 0 else box.min.x,
			box.max.y if corner & 2 != 0 else box.min.y,
			box.max.z if corner & 4 != 0 else box.min.z,
		}
		v := (to_view * [4]f32{c.x, c.y, c.z, 1}).xyz
		lo = linalg.min(lo, v)
		hi = linalg.max(hi, v)
	}
	return {lo, hi}
}

// The centre snaps to whole texels in the Sun's view, so the map moves in
// whole texels and the shadow does not shimmer. The map is two texels wider
// than the sphere on each side, so after the snap the shader's 3 x 3 taps
// stay inside it. The depth range reaches every caster over the map's square, so
// a caster toward the Sun still casts.
cascade_view :: proc(light_view: Mat4, sphere: Cascade_Sphere, map_size: u32, placed: []Placed) -> Cascade_View {
	size := f32(map_size)
	half := sphere.radius * size / (size - 4)
	texel := 2 * half / size
	c := (light_view * [4]f32{sphere.center.x, sphere.center.y, sphere.center.z, 1}).xyz
	c.xy = linalg.floor(c.xy / texel) * texel
	view := Cascade_View {
		lo = {c.x - half, c.y - half, c.z - sphere.radius},
		hi = {c.x + half, c.y + half, c.z + sphere.radius},
	}
	for p in placed {
		if cascade_covers(view, p.light_box) {
			view.lo.z = min(view.lo.z, p.light_box.min.z)
			view.hi.z = max(view.hi.z, p.light_box.max.z)
		}
	}
	view.lo.z = math.floor(view.lo.z / SHADOW_GRID) * SHADOW_GRID
	view.hi.z = math.ceil(view.hi.z / SHADOW_GRID) * SHADOW_GRID
	view.view_proj = mat4_ortho_reversed(view.lo.x, view.hi.x, view.lo.y, view.hi.y, -view.hi.z, -view.lo.z) * light_view
	return view
}

// A box that touches the edge of the square counts.
cascade_covers :: proc(view: Cascade_View, box: Box) -> bool {
	return box.max.x >= view.lo.x && box.min.x <= view.hi.x && box.max.y >= view.lo.y && box.min.y <= view.hi.y
}
