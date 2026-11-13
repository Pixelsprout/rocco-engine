package engine

import "core:math"
import "system"

CAMERA_SPEED :: f32(4.0)
CAMERA_SENSITIVITY :: f32(0.0025)
CAMERA_SWEEP_ENV :: "ROCCO_DEBUG_CAMERA_SWEEP"

PITCH_LIMIT :: f32(math.PI / 2 - 0.001)

// The fly camera behind ROCCO_DEBUG_CAMERA=1. It replaces Scene.camera.
Debug_Camera :: struct {
	eye, up:    [3]f32,
	yaw, pitch: f32,
	fovy, near: f32,
	sweep:      bool,
	sweep_time: f32,
}

camera_init :: proc(c: ^Debug_Camera) {
	c.eye = [3]f32{2, 1.5, 5}
	c.up = [3]f32{0, 1, 0}
	c.fovy = 1.0471976
	c.near = 0.001
	c.yaw = 0
	c.pitch = 0
	c.sweep = system.get_env(CAMERA_SWEEP_ENV, context.temp_allocator) == "1"
}

camera_basis :: proc(c: ^Debug_Camera) -> (forward, right, up: [3]f32) {
	forward = camera_forward(c)
	right = v3_normalize(v3_cross(forward, c.up))
	up = v3_cross(right, forward)
	return
}

camera_look :: proc(c: ^Debug_Camera, latch: ^Input_Latch) {
	c.yaw -= latch.frame_mouse.x * CAMERA_SENSITIVITY
	c.pitch -= latch.frame_mouse.y * CAMERA_SENSITIVITY
	c.pitch = math.clamp(c.pitch, -PITCH_LIMIT, PITCH_LIMIT)
}

camera_forward :: proc(c: ^Debug_Camera) -> [3]f32 {
	cp := math.cos(c.pitch)
	return [3]f32{-math.sin(c.yaw) * cp, math.sin(c.pitch), -math.cos(c.yaw) * cp}
}

camera_target :: proc(c: ^Debug_Camera) -> [3]f32 {
	return c.eye + camera_forward(c)
}

camera_view :: proc(c: ^Debug_Camera) -> Mat4 {
	return mat4_look_at(c.eye, camera_target(c), c.up)
}

// Reversed-Z with an infinite far plane spreads depth precision evenly.
// See https://www.reedbeta.com/blog/depth-precision-visualized/
camera_proj :: proc(c: ^Debug_Camera, aspect: f32) -> Mat4 {
	return mat4_perspective_reversed_infinite(c.fovy, aspect, c.near)
}

camera_move :: proc(c: ^Debug_Camera, delta: [3]f32) {
	c.eye += delta * CAMERA_SPEED
}

camera_fly :: proc(c: ^Debug_Camera, latch: ^Input_Latch, dt: f32) {
	if c.sweep {
		camera_sweep(c, dt)
		return
	}
	forward, right, up := camera_basis(c)

	if (forward != [3]f32{0, 0, 0}) {
		forward = v3_normalize(forward)
	}
	if (right != [3]f32{0, 0, 0}) {
		right = v3_normalize(right)
	}
	if (up != [3]f32{0, 0, 0}) {
		up = v3_normalize(up)
	}

	if latch.held[.W] {
		camera_move(c, forward * dt)
	}
	if latch.held[.S] {
		camera_move(c, -forward * dt)
	}
	if latch.held[.A] {
		camera_move(c, -right * dt)
	}
	if latch.held[.D] {
		camera_move(c, right * dt)
	}
}

camera_sweep :: proc(c: ^Debug_Camera, dt: f32) {
	c.sweep_time += dt
	cycle := c.sweep_time - f32(int(c.sweep_time / 2)) * 2
	c.yaw = f32(math.PI) * (cycle if cycle <= 1 else 2 - cycle)
	c.pitch = 0.35 * math.sin(c.sweep_time * f32(math.PI))
	direction := [3]f32{1, 0, 0}
	switch int(c.sweep_time / 3) % 4 {
	case 1: direction = [3]f32{-1, 0, 0}
	case 2: direction = [3]f32{0, 0, -1}
	case 3: direction = [3]f32{0, 0, 1}
	}
	camera_move(c, direction * dt)
}
