import Vocabulary

# The Launch a game starts a record update from: today's host constants with
# high_dpi on. The host reads it once, before the window opens.
Launch := [].{
	default : Vocabulary.Launch
	default = {
		window: { width: 960, height: 540, title: "rocco", fullscreen: False, high_dpi: True, samples: X4, vsync: True },
		step_hz: 120,
		shadow_map: 2048,
		capacity: { meshes: 64, skies: 16, draws: 16384, ui_quads: 16384 },
	}
}

expect Launch.default == { window: { width: 960, height: 540, title: "rocco", fullscreen: False, high_dpi: True, samples: X4, vsync: True }, step_hz: 120, shadow_map: 2048, capacity: { meshes: 64, skies: 16, draws: 16384, ui_quads: 16384 } }
