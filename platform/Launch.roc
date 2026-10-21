import Vocabulary

## Gives the Launch that your game starts a record update from. The host reads
## a Launch once, before the window opens.
Launch := [].{

	## A 960 by 540 window titled "rocco", not fullscreen, with `high_dpi` on,
	## 4x MSAA and vsync. A step rate of 120 Hz, a 2048 shadow map, 64 meshes,
	## 16 skies, 16384 Draws and 16384 UI quads. To keep all of it, write
	## `launch = |_config| Launch.default`.
	default : Vocabulary.Launch
	default = {
		window: { width: 960, height: 540, title: "rocco", fullscreen: False, high_dpi: True, samples: X4, vsync: True },
		step_hz: 120,
		shadow_map: 2048,
		capacity: { meshes: 64, skies: 16, draws: 16384, ui_quads: 16384 },
	}
}

expect Launch.default == { window: { width: 960, height: 540, title: "rocco", fullscreen: False, high_dpi: True, samples: X4, vsync: True }, step_hz: 120, shadow_map: 2048, capacity: { meshes: 64, skies: 16, draws: 16384, ui_quads: 16384 } }
