package engine

import sg "../sokol-odin/sokol/gfx"
import "core:math"
import "core:math/linalg"
import "core:mem"

SKY_DIFFUSE_SIDE :: 16
SKY_SPECULAR_SIDE :: 128
SKY_FILTER_SAMPLES :: 128

// Each level packs six RGBA16F faces in SKY_FACES order.
Sky_Lighting_Texture :: struct {
	levels: []Image_Level,
	pixels: []byte,
}

Sky_Lighting :: struct {
	diffuse: Sky_Lighting_Texture,
	specular: Sky_Lighting_Texture,
}

sky_lighting_delete :: proc(lighting: Sky_Lighting, allocator: mem.Allocator) {
	for tex in ([2]Sky_Lighting_Texture{lighting.diffuse, lighting.specular}) {
		delete(tex.levels, allocator)
		delete(tex.pixels, allocator)
	}
}

sky_lighting_build :: proc(side: int, pixels: []byte, allocator: mem.Allocator) -> Sky_Lighting {
	lighting := Sky_Lighting {
		diffuse = sky_lighting_texture(SKY_DIFFUSE_SIDE, false, allocator),
		specular = sky_lighting_texture(min(side, SKY_SPECULAR_SIDE), true, allocator),
	}
	linear: [256]f32
	for &v, i in linear { v = srgb_to_linear(f32(i) / 255) }
	for level, mip in lighting.specular.levels {
		roughness := f32(mip) / f32(max(len(lighting.specular.levels) - 1, 1))
		sky_filter_level(level, side, pixels, &linear, roughness, false)
	}
	sky_filter_level(lighting.diffuse.levels[0], side, pixels, &linear, 1, true)
	return lighting
}

sky_lighting_texture :: proc(side: int, mipmaps: bool, allocator: mem.Allocator) -> Sky_Lighting_Texture {
	count, total, size := 1, side * side * 6 * 8, side
	if mipmaps {
		for size > 1 {
			size = max(size / 2, 1)
			total += size * size * 6 * 8
			count += 1
		}
	}
	tex := Sky_Lighting_Texture {levels = make([]Image_Level, count, allocator), pixels = make([]byte, total, allocator)}
	offset := 0
	size = side
	for &level in tex.levels {
		bytes := size * size * 6 * 8
		level = {size, size, tex.pixels[offset:][:bytes]}
		offset += bytes
		size = max(size / 2, 1)
	}
	return tex
}

sky_filter_level :: proc(level: Image_Level, side: int, pixels: []byte, linear: ^[256]f32, roughness: f32, diffuse: bool) {
	out := ([^]f16)(raw_data(level.pixels))[:len(level.pixels) / 2]
	for face in 0 ..< 6 {
		for y in 0 ..< level.height {
			for x in 0 ..< level.width {
				n := sky_face_direction(face, 2 * (f32(x) + 0.5) / f32(level.width) - 1, 2 * (f32(y) + 0.5) / f32(level.height) - 1)
				color: [3]f32
				if roughness == 0 && !diffuse {
					color = sky_sample(side, pixels, linear, n)
				} else {
					up := [3]f32{0, 1, 0} if abs(n.y) < 0.999 else {1, 0, 0}
					t := v3_normalize(linalg.cross(up, n))
					b := linalg.cross(n, t)
					weight: f32
					for i in 0 ..< SKY_FILTER_SAMPLES {
						u := (f32(i) + 0.5) / SKY_FILTER_SAMPLES
						v := sky_radical_inverse(u32(i))
						phi := 2 * f32(math.PI) * v
						cos_theta := math.sqrt(1 - u)
						if !diffuse {
							a := roughness * roughness
							cos_theta = math.sqrt((1 - u) / (1 + (a * a - 1) * u))
						}
						sin_theta := math.sqrt(max(1 - cos_theta * cos_theta, 0))
						h := t * (sin_theta * math.cos(phi)) + b * (sin_theta * math.sin(phi)) + n * cos_theta
						l := h if diffuse else h * (2 * linalg.dot(n, h)) - n
						w := f32(1) if diffuse else max(linalg.dot(n, l), 0)
						if w > 0 {
							color += sky_sample(side, pixels, linear, l) * w
							weight += w
						}
					}
					color /= max(weight, 1e-6)
				}
				at := ((face * level.height + y) * level.width + x) * 4
				out[at + 0], out[at + 1], out[at + 2], out[at + 3] = f16(color.x), f16(color.y), f16(color.z), 1
			}
		}
	}
}

sky_radical_inverse :: proc(input: u32) -> f32 {
	bits := input
	bits = (bits << 16) | (bits >> 16)
	bits = ((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1)
	bits = ((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2)
	bits = ((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4)
	bits = ((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8)
	return f32(bits) * 2.3283064365386963e-10
}

// PNG rows start at the top on every backend's cubemap faces.
sky_face_direction :: proc(face: int, u, v: f32) -> [3]f32 {
	directions := [6][3]f32{{1, -v, -u}, {-1, -v, u}, {u, 1, v}, {u, -1, -v}, {u, -v, 1}, {-u, -v, -1}}
	return v3_normalize(directions[face])
}

sky_direction_face :: proc(d: [3]f32) -> (face: int, u, v: f32) {
	x, y, z := abs(d.x), abs(d.y), abs(d.z)
	if x >= y && x >= z {
		return (0 if d.x >= 0 else 1), (-d.z if d.x >= 0 else d.z) / x, -d.y / x
	}
	if y >= z {
		return (2 if d.y >= 0 else 3), d.x / y, (d.z if d.y >= 0 else -d.z) / y
	}
	return (4 if d.z >= 0 else 5), (d.x if d.z >= 0 else -d.x) / z, -d.y / z
}

sky_sample :: proc(side: int, pixels: []byte, linear: ^[256]f32, direction: [3]f32) -> [3]f32 {
	face, u, v := sky_direction_face(direction)
	x, y := (u + 1) * 0.5 * f32(side) - 0.5, (v + 1) * 0.5 * f32(side) - 0.5
	x0, y0 := int(math.floor(x)), int(math.floor(y))
	fx, fy := x - f32(x0), y - f32(y0)
	color: [3]f32
	for dy in 0 ..< 2 {
		for dx in 0 ..< 2 {
			px, py, pf := x0 + dx, y0 + dy, face
			if px < 0 || px >= side || py < 0 || py >= side {
				pf, u, v = sky_direction_face(sky_face_direction(face, 2 * (f32(px) + 0.5) / f32(side) - 1, 2 * (f32(py) + 0.5) / f32(side) - 1))
				px, py = clamp(int((u + 1) * 0.5 * f32(side)), 0, side - 1), clamp(int((v + 1) * 0.5 * f32(side)), 0, side - 1)
			}
			at := ((pf * side + py) * side + px) * 4
			w := (fx if dx == 1 else 1 - fx) * (fy if dy == 1 else 1 - fy)
			color += [3]f32{linear[pixels[at]], linear[pixels[at + 1]], linear[pixels[at + 2]]} * w
		}
	}
	return color
}

sky_lighting_upload :: proc(tex: Sky_Lighting_Texture, allocator: mem.Allocator) -> Mesh_Texture {
	desc := sg.Image_Desc {type = .CUBE, width = i32(tex.levels[0].width), height = i32(tex.levels[0].height), num_slices = 6, num_mipmaps = i32(len(tex.levels)), pixel_format = .RGBA16F, label = "sky-lighting"}
	for level, i in tex.levels { desc.data.mip_levels[i] = {ptr = raw_data(level.pixels), size = uint(len(level.pixels))} }
	image := sg.make_image(desc)
	delete(tex.levels, allocator)
	delete(tex.pixels, allocator)
	return {image = image, view = sg.make_view({texture = {image = image}}), sampler = sg.make_sampler({min_filter = .LINEAR, mag_filter = .LINEAR, mipmap_filter = .LINEAR, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, wrap_w = .CLAMP_TO_EDGE, label = "sky-lighting"})}
}

sky_lighting_params :: proc(sky: ^Sky) -> [4]f32 {
	if sky == nil { return {} }
	return {1, sky.specular_max_lod, 0, 0}
}
