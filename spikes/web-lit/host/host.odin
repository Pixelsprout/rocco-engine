// The web side of the lit slice. It loads the slice Scene's Packs from the
// preloaded file system and draws the Scene each frame through the real
// renderer, with a fixed Scene and no steps. See spikes/web-lit/README.md.
package web_lit

import "base:runtime"
import "core:fmt"
import "core:mem"
import sapp "rocco:sokol-odin/sokol/app"
import sg "rocco:sokol-odin/sokol/gfx"
import sglue "rocco:sokol-odin/sokol/glue"
import slog "rocco:sokol-odin/sokol/log"
import "rocco:engine/arenas"
import engine "slice:engine"
import scene "spike:scene"

// The "env.o" name makes the wasm import module "env". emcc resolves these
// against emscripten's libc.
foreign import env "env.o"

ASSETS :: "/assets"
SAMPLE_RATE :: 48000
// WebGPU supports 1 and 4 samples only, so any MSAA draws with 4.
WEB_MSAA :: engine.Msaa.X4
// The frame that the check script captures. The console names it.
REPORT_FRAME :: 30

Web_State :: struct {
	launch:       engine.Launch,
	packs:        engine.Packs,
	audio:        engine.Audio,
	renderer:     engine.Renderer,
	frame_render: engine.Frame_Render,
	particles:    engine.Particles,
	meshes:       scene.Meshes,
	scene:        engine.Scene,
	frames:       int,
}

g_context: runtime.Context
// Freestanding Odin has no default temp allocator.
g_temp: arenas.Arena
g: Web_State

@(default_calling_convention = "c")
foreign env {
	puts :: proc(s: cstring) -> i32 ---
	memalign :: proc(alignment, size: uint) -> rawptr ---
	free :: proc(ptr: rawptr) ---
}

@(export, link_name = "rocco_web_main")
web_main :: proc "c" () -> i32 {
	context = runtime.default_context()
	#force_no_inline runtime._startup_runtime()
	context.allocator = {libc_allocator_proc, nil}
	context.temp_allocator = arenas.allocator(&g_temp)
	g_context = context
	engine.roc_heap_init(context.allocator)
	g.launch = scene.launch()
	if g.launch.window.samples != .Off { g.launch.window.samples = WEB_MSAA }
	// On emscripten sapp.run starts the requestAnimationFrame loop and returns.
	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			cleanup_cb = cleanup,
			width = i32(g.launch.window.width),
			height = i32(g.launch.window.height),
			high_dpi = false,
			sample_count = 1,
			window_title = "rocco web lit slice",
			logger = {func = slog.func},
		},
	)
	return 0
}

// host_build and host_open_window without the Seam, the audio and the UI.
init :: proc "c" () {
	context = g_context
	perm := context.allocator
	capacity := g.launch.capacity
	engine.packs_init(&g.packs, ASSETS, context.allocator)
	engine.mesh_table_init(&g.renderer.meshes, int(capacity.meshes), perm, context.allocator)
	engine.sky_table_init(&g.renderer.skies, int(capacity.skies), perm, context.allocator)
	engine.image_table_init(&g.renderer.images, int(capacity.images), perm, context.allocator)
	engine.sound_table_init(&g.audio.sounds, engine.SOUND_CAPACITY_MIN, SAMPLE_RATE, perm, context.allocator)
	engine.packs_attach(&g.packs, &g.renderer.meshes, &g.renderer.skies, &g.renderer.images, &g.audio, perm)
	engine.frame_render_init(&g.frame_render, int(capacity.draws), int(capacity.groups), g.launch.shadow_map, int(g.launch.shadow_cascades), perm)
	engine.particles_init(&g.particles, perm)
	g.frame_render.particles = &g.particles
	g.renderer.shaders = &g.packs.shaders
	g.frame_render.packs = &g.packs

	props, _ := engine.pack_load(&g.packs, scene.PROPS, scene.PROP_ASSETS[:], context.allocator)
	scene.meshes_from(&g.meshes, props)
	surfaces, _ := engine.pack_load(&g.packs, scene.SURFACES, scene.SURFACE_ASSETS[:], context.allocator)
	puts(fmt.ctprintf("init: props %v, surfaces %v", props, surfaces))

	sg.setup(gfx_desc(capacity, int(g.launch.shadow_cascades)))
	puts(sg.query_backend() == .WGPU ? "init: sokol_gfx backend WGPU" : "init: sokol_gfx backend is not WGPU")
	engine.renderer_init(&g.renderer, g.launch)
	g.frame_render.submits = engine.renderer_submits(&g.renderer)
	g.scene = scene.view(g.meshes)
	for &s in g.packs.shaders.assets {
		if s.live {
			puts(fmt.ctprintf("init: shader %v ready %v failed %v", s.name, s.ready, s.failed))
		}
	}
	puts("init: renderer ready")
}

// app_gfx_desc of engine/app.odin, which the slice leaves out.
gfx_desc :: proc(capacity: engine.Capacity, cascades: int) -> sg.Desc {
	textures := engine.texture_pool_size(capacity)
	return {
		environment = sglue.environment(),
		logger = {func = slog.func},
		buffer_pool_size = 3 * i32(capacity.meshes) + 5 + 2,
		shader_pool_size = engine.SHADER_ASSET_LIMIT * 9 + 32 + 1 + 3 + 5,
		pipeline_pool_size = engine.SHADER_ASSET_LIMIT * engine.SHADER_PIPELINE_LIMIT + 64 + 2 + 7 + 9,
		image_pool_size = textures,
		sampler_pool_size = textures,
		view_pool_size = engine.view_pool_size(capacity),
		uniform_buffer_size = engine.uniform_buffer_size(capacity, cascades),
	}
}

frame :: proc "c" () {
	context = g_context
	window := engine.Ui_Window{size = {sapp.widthf(), sapp.heightf()}, dpi = sapp.dpi_scale()}
	view := engine.frame_render_camera(&g.frame_render, g.scene, g.scene, 0, window.size.x / window.size.y)
	engine.frame_render_draw(&g.frame_render, g.scene, g.scene, 0, view, &g.renderer.meshes, &g.renderer.skies, &g.renderer.images, nil, window)
	sg.commit()
	g.frames += 1
	if g.frames == REPORT_FRAME {
		puts(fmt.ctprintf("frame %v: window %v dpi %v, placed draws %v", g.frames, window.size, window.dpi, len(g.frame_render.placed)))
	}
	arenas.free_all(&g_temp)
}

cleanup :: proc "c" () {
	context = g_context
	sg.shutdown()
	arenas.destroy(&g_temp)
}

// Odin's own wasm allocator grows memory beside emscripten's sbrk, so the
// host allocates through libc.
libc_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		ptr := memalign(uint(max(alignment, size_of(rawptr))), uint(size))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		if mode == .Alloc {
			mem.zero(ptr, size)
		}
		return ([^]byte)(ptr)[:size], nil
	case .Free:
		free(old_memory)
		return nil, nil
	case .Resize, .Resize_Non_Zeroed:
		return mem.default_resize_bytes_align(([^]byte)(old_memory)[:old_size], size, alignment, {libc_allocator_proc, nil}, loc)
	case .Free_All:
		return nil, .Mode_Not_Implemented
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
		}
		return nil, nil
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, nil
}
