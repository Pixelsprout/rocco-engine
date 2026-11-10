package engine

import sg "../sokol-odin/sokol/gfx"

// The blended specular cube matches the largest sky specular cube, 128 down
// to 1 texel.
SKY_BLEND_SPECULAR_MIPS :: 8

#assert(1 << (SKY_BLEND_SPECULAR_MIPS - 1) == SKY_SPECULAR_SIDE)

// The image-based light the mesh shaders read in this Frame.
Environment_Light :: struct {
	diffuse, specular: Mesh_Texture,
	params:            [4]f32,
}

// faces holds a colour attachment for each face of each mip, face first.
Sky_Blend_Cube :: struct {
	texture: Mesh_Texture,
	side:    int,
	mips:    int,
	faces:   [6 * SKY_BLEND_SPECULAR_MIPS]sg.View,
}

// The targets are made on the first blend. from, to and amount are the last
// blend drawn, so a blend that holds still draws no passes.
Sky_Blend_Target :: struct {
	made:              bool,
	pip:               sg.Pipeline,
	diffuse, specular: Sky_Blend_Cube,
	from, to:          sg.Image,
	amount:            f32,
}

// Must run outside any pass, because each blended face is a pass of its own.
// A blend from no sky starts at no image-based light.
environment_light :: proc(r: ^Renderer, view: Sky_View) -> Environment_Light {
	if view.to == nil {
		if view.from == nil {
			return {diffuse = r.black_cube, specular = r.black_cube}
		}
		return {view.from.diffuse, view.from.specular, sky_lighting_params(view.from)}
	}
	b := &r.sky_blend
	if !b.made {
		sky_blend_make(b)
	}
	from_diffuse, from_specular, from_lod := r.black_cube, r.black_cube, f32(0)
	if view.from != nil {
		from_diffuse, from_specular, from_lod = view.from.diffuse, view.from.specular, view.from.specular_max_lod
	}
	if b.from != from_specular.image || b.to != view.to.specular.image || b.amount != view.amount {
		b.from, b.to, b.amount = from_specular.image, view.to.specular.image, view.amount
		sky_blend_cube(b, &b.diffuse, from_diffuse, view.to.diffuse, 0, 0, view.amount)
		sky_blend_cube(b, &b.specular, from_specular, view.to.specular, from_lod, view.to.specular_max_lod, view.amount)
	}
	return {b.diffuse.texture, b.specular.texture, {1, SKY_BLEND_SPECULAR_MIPS - 1, 0, 0}}
}

@(private = "file")
sky_blend_make :: proc(b: ^Sky_Blend_Target) {
	b.pip = sg.make_pipeline(
		{
			shader = sg.make_shader(cube_blend_shader_desc(sg.query_backend())),
			sample_count = 1,
			colors = {0 = {pixel_format = .RGBA16F}},
			depth = {pixel_format = .NONE},
			cull_mode = .NONE,
			label = "sky-blend",
		},
	)
	sky_blend_cube_make(&b.diffuse, SKY_DIFFUSE_SIDE, 1)
	sky_blend_cube_make(&b.specular, SKY_SPECULAR_SIDE, SKY_BLEND_SPECULAR_MIPS)
	b.made = true
}

@(private = "file")
sky_blend_cube_make :: proc(cube: ^Sky_Blend_Cube, side, mips: int) {
	image := sg.make_image(
		{
			type = .CUBE,
			usage = {color_attachment = true},
			width = i32(side),
			height = i32(side),
			num_slices = 6,
			num_mipmaps = i32(mips),
			pixel_format = .RGBA16F,
			label = "sky-blend",
		},
	)
	sampler := sg.make_sampler({min_filter = .LINEAR, mag_filter = .LINEAR, mipmap_filter = .LINEAR, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, wrap_w = .CLAMP_TO_EDGE, label = "sky-blend"})
	cube^ = {texture = {image = image, view = sg.make_view({texture = {image = image}}), sampler = sampler}, side = side, mips = mips}
	for mip in 0 ..< mips {
		for face in 0 ..< 6 {
			cube.faces[mip * 6 + face] = sg.make_view({color_attachment = {image = image, mip_level = i32(mip), slice = i32(face)}})
		}
	}
}

// Mip m of the target holds roughness m / (mips - 1), so each source is read
// at that roughness times its own last mip.
@(private = "file")
sky_blend_cube :: proc(b: ^Sky_Blend_Target, cube: ^Sky_Blend_Cube, from, to: Mesh_Texture, from_lod, to_lod, amount: f32) {
	for mip in 0 ..< cube.mips {
		roughness := f32(mip) / f32(max(cube.mips - 1, 1))
		side := max(cube.side >> uint(mip), 1)
		for face in 0 ..< 6 {
			gfx_begin_pass({action = {colors = {0 = {load_action = .DONTCARE}}}, attachments = {colors = {0 = cube.faces[mip * 6 + face]}}, label = "sky-blend"})
			sg.apply_pipeline(b.pip)
			sg.apply_bindings({views = {VIEW_blend_from_tex = from.view, VIEW_blend_to_tex = to.view}, samplers = {SMP_blend_from_smp = from.sampler, SMP_blend_to_smp = to.sampler}})
			params := Cube_Blend_Params {
				target = {f32(face), f32(side), 0, 0},
				lods   = {roughness * from_lod, roughness * to_lod, 0, 0},
				amount = {amount, 0, 0, 0},
			}
			sg.apply_uniforms(UB_cube_blend_params, {ptr = &params, size = size_of(Cube_Blend_Params)})
			sg.draw(0, 3, 1)
			gfx_end_pass()
		}
	}
}
