#+build windows
package engine

import "core:os"
import win32 "core:sys/windows"
import sg "../sokol-odin/sokol/gfx"

EXPECTED_BACKEND :: sg.Backend.D3D11

// The host links with -no-crt, and Odin's no-CRT entry point leaves os.args
// empty. Windows still keeps the command line, so read argv[0] from it.
platform_program_name :: proc(allocator := context.allocator) -> string {
	if len(os.args) > 0 {
		return os.args[0]
	}
	count: i32
	argv := win32.CommandLineToArgvW(win32.GetCommandLineW(), &count)
	if argv == nil || count == 0 {
		return ""
	}
	defer win32.LocalFree(argv)
	name, err := win32.wstring_to_utf8(argv[0], -1, allocator)
	return name if err == nil else ""
}
