package engine

import "core:c"

when ODIN_OS == .Darwin {
	when ODIN_DEBUG {
		foreign import miniaudio "../build/miniaudio/miniaudio_macos_arm64_debug.a"
	} else {
		foreign import miniaudio "../build/miniaudio/miniaudio_macos_arm64_release.a"
	}
} else when ODIN_OS == .Linux {
	when ODIN_DEBUG {
		foreign import miniaudio "../build/miniaudio/miniaudio_linux_x64_debug.a"
	} else {
		foreign import miniaudio "../build/miniaudio/miniaudio_linux_x64_release.a"
	}
} else when ODIN_OS == .Windows {
	when ODIN_DEBUG {
		foreign import miniaudio "../build/miniaudio/miniaudio_windows_x64_debug.lib"
	} else {
		foreign import miniaudio "../build/miniaudio/miniaudio_windows_x64_release.lib"
	}
}

MA_SUCCESS :: Ma_Result(0)
MA_FORMAT_F32 :: 5
// scripts/miniaudio/rocco_miniaudio.c sets the defines that these layouts
// depend on, such as MA_NO_RESOURCE_MANAGER, and asserts the same sizes.
MA_ENGINE_SIZE :: 1352

Ma_Result :: distinct c.int

// The host never reads inside an ma_engine. It must not move after
// ma_engine_init, because miniaudio keeps pointers into it.
Ma_Engine :: struct #align (8) {
	_: [MA_ENGINE_SIZE]u8,
}

Ma_Allocation_Callbacks :: struct {
	user_data:  rawptr,
	on_malloc:  rawptr,
	on_realloc: rawptr,
	on_free:    rawptr,
}

Ma_Resampler_Config :: struct {
	format:            c.int,
	channels:          u32,
	sample_rate_in:    u32,
	sample_rate_out:   u32,
	algorithm:         c.int,
	backend_vtable:    rawptr,
	backend_user_data: rawptr,
	linear_lpf_order:  u32,
}

Ma_Engine_Config :: struct {
	ma_context:                               rawptr,
	device:                                   rawptr,
	playback_device_id:                       rawptr,
	data_callback:                            rawptr,
	notification_callback:                    rawptr,
	log:                                      rawptr,
	listener_count:                           u32,
	channels:                                 u32,
	sample_rate:                              u32,
	period_size_in_frames:                    u32,
	period_size_in_milliseconds:              u32,
	gain_smooth_time_in_frames:               u32,
	gain_smooth_time_in_milliseconds:         u32,
	default_volume_smooth_time_in_pcm_frames: u32,
	pre_mix_stack_size_in_bytes:              u32,
	allocation_callbacks:                     Ma_Allocation_Callbacks,
	no_auto_start:                            b32,
	no_device:                                b32,
	mono_expansion_mode:                      c.int,
	resource_manager_vfs:                     rawptr,
	on_process:                               rawptr,
	process_user_data:                        rawptr,
	resource_manager_resampling:              Ma_Resampler_Config,
	pitch_resampling:                         Ma_Resampler_Config,
}

#assert(size_of(Ma_Resampler_Config) == 48)
#assert(size_of(Ma_Engine_Config) == 256)

@(default_calling_convention = "c")
foreign miniaudio {
	ma_engine_config_init :: proc() -> Ma_Engine_Config ---
	ma_engine_init :: proc(config: ^Ma_Engine_Config, engine: ^Ma_Engine) -> Ma_Result ---
	ma_engine_uninit :: proc(engine: ^Ma_Engine) ---
	ma_engine_get_device :: proc(engine: ^Ma_Engine) -> rawptr ---
	ma_result_description :: proc(result: Ma_Result) -> cstring ---
}
