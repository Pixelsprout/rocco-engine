#+build linux
package main

foreign import gl "system:GL"

foreign gl {
	@(link_name = "glGetInternalformativ") gl_internal_format :: proc "system" (target, format, name: u32, count: i32, values: [^]i32) ---
}

supported :: proc(samples: i32) -> bool {
	if samples == 1 { return true }
	for format in ([3]u32{0x881A, 0x8058, 0x8CAD}) {
		count: i32
		gl_internal_format(0x9100, format, 0x9380, 1, &count)
		assert(count > 0 && count <= 32)
		values: [32]i32
		gl_internal_format(0x9100, format, 0x80A9, count, &values[0])
		found := false
		for value in values[:count] { if value == samples { found = true } }
		if !found { return false }
	}
	return true
}
