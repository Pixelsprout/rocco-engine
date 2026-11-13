// Stand-ins for the names that the copied engine files take from the files
// that the slice leaves out.
package engine

import "core:encoding/json"
import "core:fmt"
import os "spike:webos"

foreign import env "env.o"

EXIT_AFTER_FRAMES_ENV :: "ROCCO_EXIT_AFTER_FRAMES"
MA_SUCCESS :: Ma_Result(0)
MA_FORMAT_F32 :: Ma_Format(5)

Ma_Result :: i32
Ma_Format :: i32

Ma_Decoder_Config :: struct {
	channels:             u32,
	allocation_callbacks: struct {},
}

// The slice has no audio. Packs keep a Sound table, and no Sound decodes.
Audio :: struct {
	sounds: Sound_Table,
}

// The renderer adds pass times to a capture row. The slice never captures.
Slice_State :: struct {
	capture: struct {
		on:  bool,
		row: struct {
			begin_pass, drawable: i64,
		},
	},
}

g_state: Slice_State

@(default_calling_convention = "c")
foreign env {
	puts :: proc(s: cstring) -> i32 ---
}

// The engine's log lines reach the browser console through puts.
slice_eprintfln :: proc(format: string, args: ..any) {
	puts(fmt.ctprintf(format, ..args))
}

slice_eprintf :: proc(format: string, args: ..any) {
	puts(fmt.ctprintf(format, ..args))
}

slice_eprintln :: proc(args: ..any) {
	puts(fmt.ctprint(..args))
}

slice_eprint :: proc(args: ..any) {
	puts(fmt.ctprint(..args))
}

slice_printfln :: slice_eprintfln
slice_println :: slice_eprintln

shader_open_file :: proc(path: string) -> (^os.File, os.Error) {
	return os.open(path)
}

// The page has no shader files to watch, so nothing reloads.
packs_shader_reload_poll :: proc(p: ^Packs) {
}

// A copy of engine/shader_reload.odin's, which the slice leaves out.
shader_candidate_destroy :: proc(t: ^Shader_Table, slot: int) {
	s := &t.assets[slot]
	shader_gpu_destroy(s)
	delete(s.pipelines)
	json.destroy_value(s.package_data.manifest, t.allocator)
	delete(s.package_data.bytes, t.allocator)
	delete(s.name, t.allocator)
	s^ = {generation = s.generation}
}

// No screenshot reads the target back on the web.
platform_readable_color_texture :: proc(width, height: i32) -> rawptr {
	return nil
}

capture_tick :: proc() -> i64 {
	return 0
}

capture_pass_label :: proc(c: rawptr, original: cstring) -> cstring {
	return original
}

audio_sound_remove :: proc(audio: ^Audio, slot: int) {
	sound_table_remove(&audio.sounds, slot)
}

ma_decoder_config_init :: proc(format: Ma_Format, channels, sample_rate: u32) -> Ma_Decoder_Config {
	return {}
}

ma_decode_memory :: proc(data: rawptr, size: uint, config: ^Ma_Decoder_Config, frames: ^u64, out: ^rawptr) -> Ma_Result {
	return -1
}

ma_free :: proc(ptr: rawptr, callbacks: ^struct {}) {
}
