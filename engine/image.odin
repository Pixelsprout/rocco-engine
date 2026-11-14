package engine

import sg "../sokol-odin/sokol/gfx"
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

// RGBA8, level 0 first. Every level's pixels sit in one allocation. Base
// colour is sRGB; a data texture such as metallic-roughness is linear.
Texture :: struct {
	levels:  []Image_Level,
	pixels:  []byte,
	sampler: Texture_Sampler,
	srgb:    bool,
	alpha_cutoff: f32,
}

// Gives each fully transparent pixel the average colour of the nearest
// pixels that have one, in waves out from the visible pixels. Alpha stays 0.
// Linear filtering then blends a visible edge with its own colour, not with
// the black of the transparent pixels. With no visible pixel, nothing changes.
image_bleed :: proc(width, height: int, rgba: []byte) {
	Reach :: enum u8 {
		None,
		Queued,
		Coloured,
	}
	reach := make([]Reach, width * height, context.temp_allocator)
	wave := make([dynamic]int, context.temp_allocator)
	next := make([dynamic]int, context.temp_allocator)
	for i in 0 ..< width * height {
		if rgba[i * 4 + 3] > 0 {
			reach[i] = .Coloured
			append(&next, i)
		}
	}
	for len(next) > 0 {
		clear(&wave)
		for i in next {
			for j in image_neighbours(width, height, i) {
				if j >= 0 && reach[j] == .None {
					reach[j] = .Queued
					append(&wave, j)
				}
			}
		}
		// A pixel takes its colour only from earlier waves, so the order in a
		// wave does not change the result.
		for i in wave {
			sum: [3]int
			n := 0
			for j in image_neighbours(width, height, i) {
				if j >= 0 && reach[j] == .Coloured {
					sum += {int(rgba[j * 4]), int(rgba[j * 4 + 1]), int(rgba[j * 4 + 2])}
					n += 1
				}
			}
			for k in 0 ..< 3 {
				rgba[i * 4 + k] = byte((sum[k] + n / 2) / n)
			}
		}
		for i in wave {
			reach[i] = .Coloured
		}
		wave, next = next, wave
	}
}

// An sRGB texture uploads as SRGB8A8, so the GPU decodes it to linear before filtering.
texture_upload :: proc(tex: Texture) -> Mesh_Texture {
	desc := texture_image_desc(tex)
	label := desc.label
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
				label = label,
			},
		),
	}
}

texture_image_desc :: proc(tex: Texture) -> sg.Image_Desc {
	label: cstring = "mesh-base-colour" if tex.srgb else "mesh-linear"
	desc := sg.Image_Desc {
		width        = i32(tex.levels[0].width),
		height       = i32(tex.levels[0].height),
		num_mipmaps  = i32(len(tex.levels)),
		pixel_format = .SRGB8A8 if tex.srgb else .RGBA8,
		label        = label,
	}
	desc.data = image_levels_data(tex.levels)
	return desc
}

// sokol takes every mip level as one packed range, so each level must
// follow the one before it in memory.
image_levels_data :: proc(levels: []Image_Level) -> sg.Range {
	size := 0
	for level in levels {
		assert(raw_data(level.pixels) == rawptr(uintptr(raw_data(levels[0].pixels)) + uintptr(size)))
		size += len(level.pixels)
	}
	return {ptr = raw_data(levels[0].pixels), size = uint(size)}
}

// Copies rgba into level 0. Each further level averages 2 x 2 texels of the
// one before, down to 1 x 1. An sRGB texture averages its colour in linear
// light. An odd side drops its last texel.
texture_build :: proc(width, height: int, rgba: []byte, sampler: Texture_Sampler, srgb: bool, allocator: mem.Allocator, alpha_cutoff: f32 = 0) -> Texture {
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
		srgb    = srgb,
		alpha_cutoff = alpha_cutoff if count > 1 && alpha_cutoff > 0 && alpha_cutoff <= 1 else 0,
	}
	copy(tex.pixels, rgba[:width * height * 4])
	tex.levels[0] = {width = width, height = height, pixels = tex.pixels[:width * height * 4]}

	to_linear: [256]f32
	for &v, i in to_linear {
		v = srgb_to_linear(f32(i) / 255) if srgb else f32(i) / 255
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
					out[k] = unorm8(linear_to_srgb(avg[k]) if srgb else avg[k])
				}
				out[3] = unorm8(avg[3])
			}
		}
		tex.levels[i] = dst
	}
	if alpha_cutoff > 0 && alpha_cutoff <= 1 {
		texture_preserve_alpha(tex, alpha_cutoff)
	}
	return tex
}


// The 8 pixels around pixel i. A neighbour past the edge is -1.
@(private = "file")
image_neighbours :: proc(width, height, i: int) -> (out: [8]int) {
	x, y := i % width, i / width
	n := 0
	for dy in -1 ..= 1 {
		for dx in -1 ..= 1 {
			if dx == 0 && dy == 0 {
				continue
			}
			nx, ny := x + dx, y + dy
			out[n] = ny * width + nx if nx >= 0 && nx < width && ny >= 0 && ny < height else -1
			n += 1
		}
	}
	return out
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

// Adjust only completed mips, so each box filter reads unscaled alpha.
texture_preserve_alpha :: proc(tex: Texture, cutoff: f32) {
	base := tex.levels[0].pixels
	visible := 0
	for i := 3; i < len(base); i += 4 {
		if f32(base[i]) / 255 >= cutoff { visible += 1 }
	}
	if visible == 0 { return }
	coverage := f32(visible) / f32(len(base) / 4)
	for level in tex.levels[1:] {
		histogram: [256]int
		for i := 3; i < len(level.pixels); i += 4 { histogram[level.pixels[i]] += 1 }
		desired := max(1, int(math.round(coverage * f32(level.width * level.height))))
		best := int(math.ceil(cutoff * 255))
		current := 0
		for n in histogram[best:] { current += n }
		error := abs(current - desired) if current > 0 else max(int)
		above := 0
		for threshold := 255; threshold > 0; threshold -= 1 {
			above += histogram[threshold]
			if above > 0 && abs(above - desired) < error {
				best, error = threshold, abs(above - desired)
			}
		}
		if error == max(int) { continue }
		// Quantization must leave the selected alpha bin above the shader cutoff.
		scale := math.ceil(cutoff * 255) / f32(best)
		for i := 3; i < len(level.pixels); i += 4 {
			level.pixels[i] = byte(clamp(math.round(f32(level.pixels[i]) * scale), 0, 255))
		}
	}
}
