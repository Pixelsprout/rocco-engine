package engine

FIXED_DT :: f64(1.0 / 120.0)
MAX_FRAME_TIME :: f64(0.25)

Clock :: struct {
	accumulator: f64,
	time_scale:  f64, // 1.0 normal, 0.0 paused, 0.25 slow
	real_time:   f64, // Wall clock seconds since start
	game_time:   f64, // Simulated seconds, scaled up
	steps_taken: u64, // Number of steps taken since last reset
}

clock_init :: proc(c: ^Clock) {
	// Time scale is 1.0 by default, everything else is zeroed by default
	c.time_scale = 1.0
}

clock_add_frame	:: proc(c: ^Clock, frame_time: f64) {
	clamped_frame_time := min(frame_time, MAX_FRAME_TIME)
	c.real_time += clamped_frame_time

	// scale and add to accumulator
	c.accumulator += clamped_frame_time * c.time_scale
}

clock_next_step :: proc(c: ^Clock) -> (dt: f32, ok: bool) {
	// Guard: Stops our loop from running too fast
	if c.accumulator < FIXED_DT {
		return 0.0, false
	}

	// Subtract fixed dt from accumulator and increment steps taken
	c.accumulator -= FIXED_DT
	c.steps_taken += 1

	// advance game time
	c.game_time += FIXED_DT

	return f32(FIXED_DT), true
}

clock_alpha :: proc(c: ^Clock) -> f32 {
	return f32(c.accumulator / FIXED_DT)
}

clock_render_time :: proc(c: ^Clock) -> f64 {
	return c.game_time + c.accumulator
}
