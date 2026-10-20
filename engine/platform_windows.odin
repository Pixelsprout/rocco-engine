#+build windows
package engine

import "core:os"
import win32 "core:sys/windows"
import sg "../sokol-odin/sokol/gfx"

EXPECTED_BACKEND :: sg.Backend.D3D11

// The host links with -no-crt, and Odin's no-CRT entry point leaves os.args
// empty. Windows still keeps the command line, so read the words from it.
platform_command_line :: proc(allocator := context.allocator) -> []string {
	if len(os.args) > 0 {
		return os.args
	}
	count: i32
	argv := win32.CommandLineToArgvW(win32.GetCommandLineW(), &count)
	if argv == nil || count <= 0 {
		return nil
	}
	defer win32.LocalFree(argv)
	words := make([]string, count, allocator)
	for &word, i in words {
		w, err := win32.wstring_to_utf8(argv[i], -1, allocator)
		if err != nil {
			return nil
		}
		word = w
	}
	return words
}
