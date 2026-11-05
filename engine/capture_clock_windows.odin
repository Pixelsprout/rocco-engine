#+build windows
package engine

import win32 "core:sys/windows"

capture_tick :: proc() -> i64 {
	tick: win32.LARGE_INTEGER
	win32.QueryPerformanceCounter(&tick)
	return i64(tick)
}

capture_frequency :: proc() -> i64 {
	frequency: win32.LARGE_INTEGER
	win32.QueryPerformanceFrequency(&frequency)
	return i64(frequency)
}

capture_clock_name :: proc() -> string { return "QueryPerformanceCounter" }
