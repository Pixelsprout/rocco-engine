package engine

import "core:fmt"
import "core:math"
import "system"

// Reads the target that the last Frame drew and saves it at path, in
// physical pixels. Only a windowed run has a target.
screenshot_save :: proc(r: ^Renderer, path: string) -> (size: [2]i32, error: string) {
	size = r.target.size
	if size.x <= 0 || size.y <= 0 {
		return size, "no Frame has been drawn yet"
	}
	rgba := make([]byte, int(size.x) * int(size.y) * 4, context.temp_allocator)
	error = platform_read_target(r.target.color.image, size, rgba)
	if error == "" {
		error = screenshot_write(path, size, rgba)
	}
	return
}

// The window shows the target as opaque, so the PNG is opaque too. rgba is
// top row first.
screenshot_write :: proc(path: string, size: [2]i32, rgba: []byte) -> (error: string) {
	png := screenshot_png(size, rgba)
	if err := system.write_entire_file(path, png); err != nil {
		return fmt.tprintf("the host cannot write %q: %v", path, system.error_string(err))
	}
	return ""
}

// Makes rgba opaque and encodes it in the temp allocator.
screenshot_png :: proc(size: [2]i32, rgba: []byte) -> []byte {
	for i := 3; i < len(rgba); i += 4 {
		rgba[i] = 255
	}
	return png_encode(int(size.x), int(size.y), rgba, allocator = context.temp_allocator)
}

// dpi is physical pixels per logical pixel.
screenshot_logical_size :: proc(physical: [2]i32, dpi: f32) -> [2]i32 {
	if dpi <= 0 {
		return physical
	}
	return {i32(math.round(f32(physical.x) / dpi)), i32(math.round(f32(physical.y) / dpi))}
}

// For a backend that reads the bottom row first.
rows_flip :: proc(pixels: []byte, row: int) {
	if row <= 0 {
		return
	}
	rows := len(pixels) / row
	for y in 0 ..< rows / 2 {
		top := pixels[y * row:][:row]
		bottom := pixels[(rows - 1 - y) * row:][:row]
		for i in 0 ..< row {
			top[i], bottom[i] = bottom[i], top[i]
		}
	}
}
