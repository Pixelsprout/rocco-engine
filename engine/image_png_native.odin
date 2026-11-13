#+build !freestanding
package engine

import "core:encoding/endian"
import "core:image/png"

// Returns RGBA8 in context.temp_allocator. A 16-bit channel keeps its high byte.
png_decode :: proc(bytes: []byte) -> (width, height: int, rgba: []byte, ok: bool) {
	img, err := png.load_from_bytes(bytes, {.alpha_add_if_missing}, context.temp_allocator)
	if err != nil {
		return 0, 0, nil, false
	}
	if img.width <= 0 || img.height <= 0 || img.width > IMAGE_MAX_SIDE || img.height > IMAGE_MAX_SIDE {
		return 0, 0, nil, false
	}
	if img.depth != 8 && img.depth != 16 {
		return 0, 0, nil, false
	}
	src := img.pixels[:]
	stride := img.depth / 8
	channels := img.channels
	count := img.width * img.height
	if channels < 1 || channels > 4 || len(src) < count * channels * stride {
		return 0, 0, nil, false
	}

	rgba = make([]byte, count * 4, context.temp_allocator)
	for i in 0 ..< count {
		px := src[i * channels * stride:]
		switch channels {
		case 1, 2:
			g := png_channel(px, 0, stride)
			rgba[i * 4 + 0], rgba[i * 4 + 1], rgba[i * 4 + 2] = g, g, g
			rgba[i * 4 + 3] = png_channel(px, 1, stride) if channels == 2 else 255
		case 3, 4:
			for k in 0 ..< 3 {
				rgba[i * 4 + k] = png_channel(px, k, stride)
			}
			rgba[i * 4 + 3] = png_channel(px, 3, stride) if channels == 4 else 255
		}
	}
	return img.width, img.height, rgba, true
}

// core:image/png leaves 16-bit channels in native byte order.
@(private = "file")
png_channel :: proc(px: []byte, k, stride: int) -> byte {
	if stride == 2 {
		n, _ := endian.get_u16(px[k * 2:], endian.PLATFORM_BYTE_ORDER)
		return byte(n >> 8)
	}
	return px[k]
}
