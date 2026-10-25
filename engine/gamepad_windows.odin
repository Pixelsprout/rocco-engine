#+build windows
package engine

import "core:fmt"
import win32 "core:sys/windows"
import "core:time"

// core:sys/windows binds only LoadLibraryW, and the import-lib catalog
// (scripts/windows-import-libs/kernel32.def) has only LoadLibraryA.
foreign import kernel32 "system:Kernel32.lib"

XINPUT_DLL :: "xinput1_4.dll"
// Microsoft advises against a call of XInputGetState for an empty index in
// each frame.
XINPUT_EMPTY_CHECK_INTERVAL :: time.Second

// The foreign XInput procs of core:sys/windows link xinput.lib, so the
// backend gets XInputGetState from the DLL at run time.
Xinput_Get_State :: #type proc "system" (user: win32.XUSER, state: ^win32.XINPUT_STATE) -> win32.System_Error

// A pad's id is its XInput index. The shared slot table picks its slot.
Gamepad_Backend :: struct {
	lib:              win32.HMODULE,
	get_state:        Xinput_Get_State,
	connected:        [win32.XUSER_MAX_COUNT]bool,
	next_empty_check: time.Tick,
}

#assert(size_of(Xinput_Gamepad) == size_of(win32.XINPUT_GAMEPAD))

@(private = "file", default_calling_convention = "system")
foreign kernel32 {
	LoadLibraryA :: proc(name: cstring) -> win32.HMODULE ---
}

gamepad_backend_init :: proc(backend: ^Gamepad_Backend) {
	backend^ = {}
	lib := LoadLibraryA(XINPUT_DLL)
	if lib == nil {
		fmt.eprintln("the host cannot load " + XINPUT_DLL + "; it reports no gamepads")
		return
	}
	get_state := Xinput_Get_State(win32.GetProcAddress(lib, "XInputGetState"))
	if get_state == nil {
		fmt.eprintln(XINPUT_DLL + " has no XInputGetState; the host reports no gamepads")
		win32.FreeLibrary(lib)
		return
	}
	backend.lib = lib
	backend.get_state = get_state
}

// Writes each connected pad to out and returns the count. See Gamepad_Raw.
gamepad_backend_poll :: proc(backend: ^Gamepad_Backend, out: []Gamepad_Raw) -> int {
	if backend.get_state == nil {
		return 0
	}
	now := time.tick_now()
	check_empty := time.tick_diff(backend.next_empty_check, now) >= 0
	if check_empty {
		backend.next_empty_check = time.tick_add(now, XINPUT_EMPTY_CHECK_INTERVAL)
	}
	n := 0
	for &connected, index in backend.connected {
		if !connected && !check_empty {
			continue
		}
		state: win32.XINPUT_STATE
		connected = backend.get_state(win32.XUSER(index), &state) == .SUCCESS
		if connected && n < len(out) {
			out[n] = xinput_map(transmute(Xinput_Gamepad)state.Gamepad, u64(index))
			n += 1
		}
	}
	return n
}

gamepad_backend_shutdown :: proc(backend: ^Gamepad_Backend) {
	if backend.lib != nil {
		win32.FreeLibrary(backend.lib)
	}
	backend^ = {}
}
