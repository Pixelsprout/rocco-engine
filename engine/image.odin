package engine

import sg "../sokol-odin/sokol/gfx"
import "core:encoding/endian"
import "core:image/png"
import "core:math"
import "core:mem"

// sokol takes at most 16 mip levels, and a 32768 texel side needs all 16.
IMAGE_MAX_SIDE :: 1 << 15

Texture_Sampler :: struct {
	min_filter:    sg.Filter,
	mag_filter:    sg.Filter,
	mipmap_filter: sg.Filter,
	wrap_u:        sg.Wrap,
	wrap_v:        sg.Wrap,
	mipmaps:       bool,
}

Image_Level :: struct {
	width, height: int,
	pixels:        []byte,
}

// RGBA8 in sRGB, level 0 first. Every level's pixels sit in one allocation.
Texture :: struct {
	levels:  []Image_Level,
	pixels:  []byte,
	sampler: Texture_Sampler,
}

// Returns RGBA8 in frame memory. A 16-bit channel keeps its high byte.
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
	src := img.pixels.buf[:]
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

// Base colour is sRGB, so the GPU decodes it to linear before filtering.
texture_upload :: proc(tex: Texture) -> Mesh_Texture {
	desc := sg.Image_Desc {
		width        = i32(tex.levels[0].width),
		height       = i32(tex.levels[0].height),
		num_mipmaps  = i32(len(tex.levels)),
		pixel_format = .SRGB8A8,
		label        = "mesh-base-colour",
	}
	for level, i in tex.levels {
		desc.data.mip_levels[i] = {ptr = raw_data(level.pixels), size = uint(len(level.pixels))}
	}
	image := sg.make_image(desc)
	s := tex.sampler
	return {
		image = image,
		view = sg.make_view({texture = {image = image}}),
		sampler = sg.make_sampler(
			{
				min_filter = s.min_filter,
				mag_filter = s.mag_filter,
				mipmap_filter = s.mipmap_filter,
				wrap_u = s.wrap_u,
				wrap_v = s.wrap_v,
				label = "mesh-base-colour",
			},
		),
	}
}

// Copies rgba into level 0. Each further level averages 2 x 2 texels of the
// one before in linear light, down to 1 x 1. An odd side drops its last texel.
texture_build :: proc(width, height: int, rgba: []byte, sampler: Texture_Sampler, allocator: mem.Allocator) -> Texture {
	count := 1
	total := width * height * 4
	if sampler.mipmaps {
		w, h := width, height
		for w > 1 || h > 1 {
			w, h = max(w / 2, 1), max(h / 2, 1)
			total += w * h * 4
			count += 1
		}
	}

	tex := Texture {
		levels  = make([]Image_Level, count, allocator),
		pixels  = make([]byte, total, allocator),
		sampler = sampler,
	}
	copy(tex.pixels, rgba[:width * height * 4])
	tex.levels[0] = {width = width, height = height, pixels = tex.pixels[:width * height * 4]}

	to_linear: [256]f32
	for &v, i in to_linear {
		v = srgb_to_linear(f32(i) / 255)
	}
	offset := width * height * 4
	for i in 1 ..< count {
		src := tex.levels[i - 1]
		w, h := max(src.width / 2, 1), max(src.height / 2, 1)
		dst := Image_Level{width = w, height = h, pixels = tex.pixels[offset:][:w * h * 4]}
		offset += w * h * 4
		for y in 0 ..< h {
			for x in 0 ..< w {
				x0, y0 := min(2 * x, src.width - 1), min(2 * y, src.height - 1)
				x1, y1 := min(2 * x + 1, src.width - 1), min(2 * y + 1, src.height - 1)
				corners := [4]int{y0 * src.width + x0, y0 * src.width + x1, y1 * src.width + x0, y1 * src.width + x1}
				sum: [4]f32
				for c in corners {
					p := src.pixels[c * 4:]
					sum += {to_linear[p[0]], to_linear[p[1]], to_linear[p[2]], f32(p[3]) / 255}
				}
				avg := sum / 4
				out := dst.pixels[(y * w + x) * 4:]
				for k in 0 ..< 3 {
					out[k] = unorm8(linear_to_srgb(avg[k]))
				}
				out[3] = unorm8(avg[3])
			}
		}
		tex.levels[i] = dst
	}
	return tex
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

texture_delete :: proc(tex: Texture, allocator: mem.Allocator) {
	delete(tex.levels, allocator)
	delete(tex.pixels, allocator)
}

srgb_to_linear :: proc(c: f32) -> f32 {
	return c / 12.92 if c <= 0.04045 else math.pow((c + 0.055) / 1.055, 2.4)
}

linear_to_srgb :: proc(c: f32) -> f32 {
	return c * 12.92 if c <= 0.0031308 else 1.055 * math.pow(c, 1 / 2.4) - 0.055
}

unorm8 :: proc(c: f32) -> byte {
	return byte(math.round(clamp(c, 0, 1) * 255))
}
