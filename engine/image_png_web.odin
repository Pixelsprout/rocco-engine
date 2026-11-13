#+build freestanding
package engine

import "core:c"

// The web prebuild compiles stb_image.c from Odin's vendor/stb. The Odin
// binding vendor:stb/image is not used, because on wasm it brings Odin's
// libc-shim, and that clashes with emscripten's libc.
foreign import stb_image "env.o"

@(default_calling_convention = "c")
foreign stb_image {
	stbi_load_from_memory :: proc(buffer: [^]byte, len: c.int, x, y, channels_in_file: ^c.int, desired_channels: c.int) -> [^]byte ---
	stbi_image_free :: proc(pixels: rawptr) ---
}

// core:image/png imports core:os on every target but js, so the web host
// decodes with stb_image. It also keeps the high byte of a 16-bit channel.
png_decode :: proc(bytes: []byte) -> (width, height: int, rgba: []byte, ok: bool) {
	w, h, channels: c.int
	pixels := stbi_load_from_memory(raw_data(bytes), c.int(len(bytes)), &w, &h, &channels, 4)
	if pixels == nil {
		return 0, 0, nil, false
	}
	defer stbi_image_free(pixels)
	if w <= 0 || h <= 0 || w > IMAGE_MAX_SIDE || h > IMAGE_MAX_SIDE {
		return 0, 0, nil, false
	}
	rgba = make([]byte, int(w) * int(h) * 4, context.temp_allocator)
	copy(rgba, pixels[:len(rgba)])
	return int(w), int(h), rgba, true
}
