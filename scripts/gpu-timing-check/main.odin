#+build windows
package main

import engine "../../engine"
import sapp "../../sokol-odin/sokol/app"
import sg "../../sokol-odin/sokol/gfx"
import sglue "../../sokol-odin/sokol/glue"
import slog "../../sokol-odin/sokol/log"
import "base:runtime"
import "core:fmt"
import "core:os"
import d3d11 "vendor:directx/d3d11"

FRAMES :: 120

saved_context: runtime.Context
frames, errors: int

main :: proc() {
	saved_context = context
	assert(len(os.args) == 2)
	sapp.run({init_cb = init, frame_cb = frame, cleanup_cb = cleanup, width = 64, height = 64, window_title = "GPU timestamp check", sample_count = 1, logger = {func = log_item}})
	assert(errors == 0)
}

log_item :: proc "c" (tag: cstring, level, item: u32, message: cstring, line: u32, file: cstring, user: rawptr) {
	context = saved_context
	slog.func(tag, level, item, message, line, file, user)
	if level <= 1 { errors += 1 }
}

init :: proc "c" () {
	context = saved_context
	sg.setup({environment = sglue.environment(), logger = {func = log_item}})
	assert(sg.query_backend() == .D3D11)
	assert(engine.gpu_timing_native_open(&engine.g_gpu_timing, os.args[1], FRAMES, (^d3d11.IDevice)(sg.d3d11_device()), (^d3d11.IDeviceContext)(sg.d3d11_device_context()), context.allocator))
	assert(engine.g_gpu_timing.created == engine.GPU_TIMING_SLOTS * (1 + engine.GPU_TIMING_STAMPS))
}

frame :: proc "c" () {
	context = saved_context
	if frames == FRAMES { return }
	frames += 1
	engine.gpu_timing_native_begin(&engine.g_gpu_timing, frames)
	count := engine.GPU_TIMING_PASSES + 1 if frames == 1 else 1
	for _ in 0 ..< count {
		engine.gfx_begin_pass({swapchain = sglue.swapchain(), action = {colors = {0 = {load_action = .CLEAR, clear_value = {0.2, 0.4, 0.6, 1}}}}, label = "main"})
		engine.gfx_end_pass()
	}
	engine.gpu_timing_native_end(&engine.g_gpu_timing)
	sg.commit()
	if frames == FRAMES { sapp.request_quit() }
}

cleanup :: proc "c" () {
	context = saved_context
	assert(engine.gpu_timing_native_close(&engine.g_gpu_timing) == nil)
	assert(engine.g_gpu_timing.created == engine.g_gpu_timing.released)
	for slot in engine.g_gpu_timing.queries {
		assert(slot.disjoint == nil)
		for stamp in slot.stamps { assert(stamp == nil) }
	}
	assert(engine.g_gpu_timing.protocol.rows == nil)
	assert(engine.g_gpu_timing.device_context == nil && !engine.g_gpu_timing.active)
	assert(engine.gpu_timing_native_close(&engine.g_gpu_timing) == nil)
	fmt.printfln("PASS: D3D11 timestamp queries; created=%v released=%v frames=%v", engine.g_gpu_timing.created, engine.g_gpu_timing.released, frames)
	sg.shutdown()
}
