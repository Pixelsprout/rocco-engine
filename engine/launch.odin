package engine

import "core:fmt"
import "core:os"

LAUNCH_RULE_ZERO :: "must be above zero"
LAUNCH_RULE_UI_QUADS :: "must be at most 16384, so a u16 index reaches every UI vertex"
LAUNCH_RULE_MESHES :: "must be at least 4, for the Fallback mesh and the three Primitives"
LAUNCH_RULE_SKIES :: "must be at least 2, for the reserved slot and one sky"
LAUNCH_RULE_SOUNDS :: "must be at least 2, for the reserved slot and one Sound"
LAUNCH_RULE_SLOTS :: "must be at most 65536, so each slot gets an id"
LAUNCH_RULE_DRAWS :: "must be at most 2796197, so the uniform buffer size fits sokol's int"
// The rules above spell these numbers out.
#assert(UI_QUAD_LIMIT == 16384 && len(Primitive) == 4 && SKY_CAPACITY_MIN == 2 && SOUND_CAPACITY_MIN == 2)
#assert(SLOT_LIMIT == 65536 && DRAW_LIMIT == 2796197)

// pf.Launch.default on the host side. Keep it equal to platform/Launch.roc.
launch_default :: proc() -> Launch {
	return {
		window = {width = 960, height = 540, title = roc_str_from_slice("rocco"), fullscreen = false, high_dpi = true, samples = .X4, vsync = true},
		step_hz = 120,
		shadow_map = 2048,
		capacity = {meshes = 64, skies = 16, draws = 16384, ui_quads = 16384, sounds = 64, voices = 64},
	}
}

// Exits the process on a bad Launch, so a typo cannot change the run silently.
launch_check_or_exit :: proc(launch: Launch) {
	field, rule, ok := launch_check(launch)
	if !ok {
		fmt.eprintfln("Launch.%v %v, so the run ends", field, rule)
		os.exit(1)
	}
}

// Names the first bad field in the game's words and the rule it broke, or ok
// when every field passes. A zero fails before a bound.
launch_check :: proc(launch: Launch) -> (field: string, rule: string, ok: bool) {
	capacity := launch.capacity
	switch {
	case launch.window.width == 0:
		return "window.width", LAUNCH_RULE_ZERO, false
	case launch.window.height == 0:
		return "window.height", LAUNCH_RULE_ZERO, false
	case launch.step_hz == 0:
		return "step_hz", LAUNCH_RULE_ZERO, false
	case launch.shadow_map == 0:
		return "shadow_map", LAUNCH_RULE_ZERO, false
	case capacity.meshes == 0:
		return "capacity.meshes", LAUNCH_RULE_ZERO, false
	case capacity.skies == 0:
		return "capacity.skies", LAUNCH_RULE_ZERO, false
	case capacity.draws == 0:
		return "capacity.draws", LAUNCH_RULE_ZERO, false
	case capacity.ui_quads == 0:
		return "capacity.ui_quads", LAUNCH_RULE_ZERO, false
	case capacity.sounds == 0:
		return "capacity.sounds", LAUNCH_RULE_ZERO, false
	case capacity.voices == 0:
		return "capacity.voices", LAUNCH_RULE_ZERO, false
	case capacity.ui_quads > UI_QUAD_LIMIT:
		return "capacity.ui_quads", LAUNCH_RULE_UI_QUADS, false
	case capacity.meshes < len(Primitive):
		return "capacity.meshes", LAUNCH_RULE_MESHES, false
	case capacity.skies < SKY_CAPACITY_MIN:
		return "capacity.skies", LAUNCH_RULE_SKIES, false
	case capacity.sounds < SOUND_CAPACITY_MIN:
		return "capacity.sounds", LAUNCH_RULE_SOUNDS, false
	case capacity.meshes > SLOT_LIMIT:
		return "capacity.meshes", LAUNCH_RULE_SLOTS, false
	case capacity.skies > SLOT_LIMIT:
		return "capacity.skies", LAUNCH_RULE_SLOTS, false
	case capacity.sounds > SLOT_LIMIT:
		return "capacity.sounds", LAUNCH_RULE_SLOTS, false
	case capacity.voices > SLOT_LIMIT:
		return "capacity.voices", LAUNCH_RULE_SLOTS, false
	case capacity.draws > DRAW_LIMIT:
		return "capacity.draws", LAUNCH_RULE_DRAWS, false
	}
	return "", "", true
}

// The sample count of the render target and the pipelines.
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
