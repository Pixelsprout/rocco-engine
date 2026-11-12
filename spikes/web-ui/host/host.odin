package web_ui

import "base:runtime"
import "core:fmt"
import "core:mem"
import sapp "rocco:sokol-odin/sokol/app"
import sg "rocco:sokol-odin/sokol/gfx"
import sglue "rocco:sokol-odin/sokol/glue"
import slog "rocco:sokol-odin/sokol/log"
import "rocco:engine/arenas"
import engine "slice:engine"

// The "env.o" name makes the wasm import module "env". emcc resolves these
// against emscripten's libc.
foreign import env "env.o"

QUAD_CAPACITY :: 1024
LABEL :: "Hello from WebGPU"
CLEAR_COLOR :: sg.Color{0.08, 0.1, 0.14, 1}

g_context: runtime.Context
// Freestanding Odin has no default temp allocator, and ui_gpu_init builds its
// index data in temp memory.
g_temp: arenas.Arena
g_ui: engine.Ui
g_renderer: engine.Renderer
g_reported: bool

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
	// On emscripten sapp.run starts the requestAnimationFrame loop and returns.
	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			cleanup_cb = cleanup,
			width = 800,
			height = 600,
			high_dpi = true,
			// The Post pass that the UI draws in has no depth image.
			depth_format = .NONE,
			window_title = "rocco web UI spike",
			logger = {func = slog.func},
		},
	)
	return 0
}

init :: proc "c" () {
	context = g_context
	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})
	puts(sg.query_backend() == .WGPU ? "init: sokol_gfx backend WGPU" : "init: sokol_gfx backend is not WGPU")
	if err := engine.ui_init(&g_ui, {sapp.widthf(), sapp.heightf()}, QUAD_CAPACITY, context.allocator); err != nil {
		puts("init: ui_init failed")
		return
	}
	if err := engine.ui_gpu_init(&g_renderer.ui, QUAD_CAPACITY, 1, context.allocator); err != nil {
		puts("init: ui_gpu_init failed")
		return
	}
	g_renderer.images.linear = sg.make_sampler({min_filter = .LINEAR, mag_filter = .LINEAR})
	g_renderer.images.nearest = sg.make_sampler({min_filter = .NEAREST, mag_filter = .NEAREST})
	puts("init: UI pipeline ready")
}

frame :: proc "c" () {
	context = g_context
	window := engine.Ui_Window{size = {sapp.widthf(), sapp.heightf()}, dpi = sapp.dpi_scale()}
	text := engine.Element{tag = .Text}
	text.payload.text = {str = static_str(LABEL), color = {r = 1, g = 1, b = 1, a = 1}, size = 32, wrap = .None}
	// The zero value of each tag union is its first tag in alphabetical
	// order, such as Float at CenterBottom, so a Panel names every tag.
	panel := engine.Element{tag = .Panel}
	panel.payload.panel = {
		_0 = {
			background = {r = 0.2, g = 0.35, b = 0.8, a = 1},
			floating = {tag = .NoFloat},
			overflow = {tag = .Visible},
			pad = {left = 24, right = 24, top = 16, bottom = 16},
			radius = 12,
			child_align = {x = .Start, y = .Start},
			direction = .Col,
		},
		_1 = {elements = &text, length = 1},
	}
	roots := []engine.Element{panel}
	quads := engine.ui_frame(&g_ui, roots, window)

	sg.begin_pass({action = {colors = {0 = {load_action = .CLEAR, clear_value = CLEAR_COLOR}}}, swapchain = sglue.swapchain()})
	engine.renderer_ui(&g_renderer, quads, window.size)
	sg.end_pass()
	sg.commit()

	if !g_reported {
		report_quads(quads, window)
		g_reported = true
	}
	arenas.free_all(&g_temp)
}

cleanup :: proc "c" () {
	context = g_context
	engine.ui_destroy(&g_ui)
	sg.shutdown()
	arenas.destroy(&g_temp)
}

// The label lives in the data section, so the Roc_Str points at it and
// never frees it.
static_str :: proc(s: string) -> engine.Roc_Str {
	return {bytes = raw_data(s), capacity_or_alloc_ptr = uint(len(s)), length = uint(len(s))}
}

report_quads :: proc(quads: []engine.Ui_Quad, window: engine.Ui_Window) {
	rects, glyphs := 0, 0
	for q in quads {
		switch q.kind {
		case .Rect:
			rects += 1
		case .Glyph:
			glyphs += 1
		case .Image:
		}
	}
	puts(fmt.ctprintf("frame: window %v dpi %v, rect quads %v, glyph quads %v", window.size, window.dpi, rects, glyphs))
	if len(quads) > 0 {
		puts(fmt.ctprintf("frame: first quad rect %v", quads[0].rect))
	}
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
