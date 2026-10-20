package engine

// pf.Launch.default on the host side. Keep it equal to platform/Launch.roc.
launch_default :: proc() -> Launch {
	return {
		window = {width = 960, height = 540, title = roc_str_from_slice("rocco"), fullscreen = false, high_dpi = true, samples = .X4, vsync = true},
		step_hz = 120,
		shadow_map = 2048,
		capacity = {meshes = 64, skies = 16, draws = 16384, ui_quads = 16384},
	}
}
