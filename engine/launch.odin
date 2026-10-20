package engine

import "core:fmt"
import "core:os"

// pf.Launch.default on the host side. Keep it equal to platform/Launch.roc.
launch_default :: proc() -> Launch {
	return {
		window = {width = 960, height = 540, title = roc_str_from_slice("rocco"), fullscreen = false, high_dpi = true, samples = .X4, vsync = true},
		step_hz = 120,
		shadow_map = 2048,
		capacity = {meshes = 64, skies = 16, draws = 16384, ui_quads = 16384},
	}
}

// Exits the process on a bad Launch, so a typo cannot change the run silently.
launch_check_or_exit :: proc(launch: Launch) {
	field, ok := launch_check(launch)
	if !ok {
		fmt.eprintfln("Launch.%v must be above zero, so the run ends", field)
		os.exit(1)
	}
}

// Names the first bad field in the game's words, or ok when every field passes.
launch_check :: proc(launch: Launch) -> (field: string, ok: bool) {
	switch {
	case launch.window.width == 0:
		return "window.width", false
	case launch.window.height == 0:
		return "window.height", false
	case launch.shadow_map == 0:
		return "shadow_map", false
	}
	return "", true
}

// The sample count sokol takes for the swapchain and the pipelines.
msaa_sample_count :: proc(samples: Msaa) -> i32 {
	switch samples {
	case .Off:
		return 1
	case .X2:
		return 2
	case .X4:
		return 4
	case .X8:
		return 8
	}
	return 1
}
