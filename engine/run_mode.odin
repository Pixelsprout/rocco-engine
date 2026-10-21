package engine

import "core:fmt"
import "core:os"

LOCKSTEP_ENV :: "ROCCO_LOCKSTEP"
HEADLESS_ENV :: "ROCCO_HEADLESS"

// Lockstep runs one fixed step and one render per Frame, whatever the time.
// Headless is Lockstep with no window and no GPU.
Run_Mode :: enum {
	Real_Clock,
	Lockstep,
	Headless,
}

// Exits the process on a bad value, so a typo cannot produce a normal run.
run_mode_from_env :: proc(exit_after_frames: int, bridge: bool) -> Run_Mode {
	lockstep := run_switch_from_env(LOCKSTEP_ENV)
	headless := run_switch_from_env(HEADLESS_ENV)
	mode, ok := run_mode_make(lockstep, headless, exit_after_frames, bridge)
	if !ok {
		fmt.eprintfln("%v=1 needs %v or %v, so the run ends", HEADLESS_ENV, EXIT_AFTER_FRAMES_ENV, BRIDGE_ENV)
		os.exit(1)
	}
	return mode
}

@(private = "file")
run_switch_from_env :: proc(name: string) -> bool {
	value := os.get_env(name, context.temp_allocator)
	on, ok := run_switch_parse(value)
	if !ok {
		fmt.eprintfln("%v must be 0 or 1, got %q", name, value)
		os.exit(1)
	}
	return on
}

// Treat an empty value as unset.
run_switch_parse :: proc(value: string) -> (on, ok: bool) {
	switch value {
	case "", "0":
		return false, true
	case "1":
		return true, true
	}
	return false, false
}

// A Headless run has no window to close, so it needs a Frame count or a
// Driver to quit it. A Bridge run is Lockstep.
run_mode_make :: proc(lockstep, headless: bool, exit_after_frames: int, bridge := false) -> (mode: Run_Mode, ok: bool) {
	if headless {
		return .Headless, exit_after_frames > 0 || bridge
	}
	return .Lockstep if lockstep || bridge else .Real_Clock, true
}
