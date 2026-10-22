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
MA_SOUND_SIZE :: 1016
MA_AUDIO_BUFFER_REF_SIZE :: 112
MA_ATTENUATION_MODEL_LINEAR :: 2
MA_POSITIONING_ABSOLUTE :: 0

Ma_Result :: distinct c.int

// The host never reads inside an ma_engine. It must not move after
// ma_engine_init, because miniaudio keeps pointers into it.
Ma_Engine :: struct #align (8) {
	_: [MA_ENGINE_SIZE]u8,
}

// A Sound that plays from a data source. It must not move after
// ma_sound_init_from_data_source, because the engine links it by pointer.
Ma_Sound :: struct #align (8) {
	_: [MA_SOUND_SIZE]u8,
}

// A data source over PCM it does not own. It holds the play cursor, so each
// ma_sound needs its own.
Ma_Audio_Buffer_Ref :: struct #align (8) {
	_: [MA_AUDIO_BUFFER_REF_SIZE]u8,
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

// A format, channels or sample_rate of 0 keeps the file's own.
// ma_decode_memory writes back the ones it chose.
Ma_Decoder_Config :: struct {
	format:                   c.int,
	channels:                 u32,
	sample_rate:              u32,
	channel_map:              rawptr,
	channel_mix_mode:         c.int,
	dither_mode:              c.int,
	resampling:               Ma_Resampler_Config,
	allocation_callbacks:     Ma_Allocation_Callbacks,
	encoding_format:          c.int,
	seek_point_count:         u32,
	custom_backend_vtables:   rawptr,
	custom_backend_count:     u32,
	custom_backend_user_data: rawptr,
}

#assert(size_of(Ma_Resampler_Config) == 48)
#assert(size_of(Ma_Engine_Config) == 256)
#assert(size_of(Ma_Decoder_Config) == 144)

@(default_calling_convention = "c")
foreign miniaudio {
	ma_engine_config_init :: proc() -> Ma_Engine_Config ---
	ma_engine_init :: proc(config: ^Ma_Engine_Config, engine: ^Ma_Engine) -> Ma_Result ---
	ma_engine_uninit :: proc(engine: ^Ma_Engine) ---
	ma_engine_get_device :: proc(engine: ^Ma_Engine) -> rawptr ---
	ma_engine_get_sample_rate :: proc(engine: ^Ma_Engine) -> u32 ---
	ma_result_description :: proc(result: Ma_Result) -> cstring ---
	ma_decoder_config_init :: proc(format: c.int, channels, sample_rate: u32) -> Ma_Decoder_Config ---
	// frames comes from ma_malloc even when frame_count is 0. Free it with ma_free.
	ma_decode_memory :: proc(data: rawptr, size: c.size_t, config: ^Ma_Decoder_Config, frame_count: ^u64, frames: ^rawptr) -> Ma_Result ---
	ma_free :: proc(p: rawptr, callbacks: ^Ma_Allocation_Callbacks) ---
	// Mixes frame_count frames of f32, interleaved by the engine's channels.
	// Only for an engine with no device: nothing locks out the audio thread.
	ma_engine_read_pcm_frames :: proc(engine: ^Ma_Engine, frames: rawptr, frame_count: u64, frames_read: ^u64) -> Ma_Result ---
	ma_engine_get_channels :: proc(engine: ^Ma_Engine) -> u32 ---
	ma_engine_listener_set_position :: proc(engine: ^Ma_Engine, listener: u32, x, y, z: f32) ---
	ma_engine_listener_set_direction :: proc(engine: ^Ma_Engine, listener: u32, x, y, z: f32) ---
	ma_engine_listener_set_world_up :: proc(engine: ^Ma_Engine, listener: u32, x, y, z: f32) ---
	ma_audio_buffer_ref_init :: proc(format: c.int, channels: u32, data: rawptr, size_in_frames: u64, ref: ^Ma_Audio_Buffer_Ref) -> Ma_Result ---
	ma_audio_buffer_ref_uninit :: proc(ref: ^Ma_Audio_Buffer_Ref) ---
	// The sound does not own the data source, which must outlive it.
	ma_sound_init_from_data_source :: proc(engine: ^Ma_Engine, data_source: rawptr, flags: u32, group: rawptr, sound: ^Ma_Sound) -> Ma_Result ---
	// Waits until the audio thread lets go of the sound. Never call it on the
	// audio thread.
	ma_sound_uninit :: proc(sound: ^Ma_Sound) ---
	ma_sound_start :: proc(sound: ^Ma_Sound) -> Ma_Result ---
	// Fades from the current volume to 0, then stops. A plain ma_sound_start
	// does not restart the sound after it.
	ma_sound_stop_with_fade_in_milliseconds :: proc(sound: ^Ma_Sound, milliseconds: u64) -> Ma_Result ---
	ma_sound_is_playing :: proc(sound: ^Ma_Sound) -> b32 ---
	ma_sound_set_looping :: proc(sound: ^Ma_Sound, looping: b32) ---
	ma_sound_set_volume :: proc(sound: ^Ma_Sound, volume: f32) ---
	// Ignores a pitch of 0 or less.
	ma_sound_set_pitch :: proc(sound: ^Ma_Sound, pitch: f32) ---
	ma_sound_get_pitch :: proc(sound: ^Ma_Sound) -> f32 ---
	ma_sound_set_spatialization_enabled :: proc(sound: ^Ma_Sound, enabled: b32) ---
	ma_sound_set_position :: proc(sound: ^Ma_Sound, x, y, z: f32) ---
	ma_sound_set_attenuation_model :: proc(sound: ^Ma_Sound, model: c.int) ---
	ma_sound_set_positioning :: proc(sound: ^Ma_Sound, positioning: c.int) ---
	ma_sound_set_rolloff :: proc(sound: ^Ma_Sound, rolloff: f32) ---
	ma_sound_set_min_gain :: proc(sound: ^Ma_Sound, gain: f32) ---
	ma_sound_set_max_gain :: proc(sound: ^Ma_Sound, gain: f32) ---
	ma_sound_set_min_distance :: proc(sound: ^Ma_Sound, distance: f32) ---
	ma_sound_set_max_distance :: proc(sound: ^Ma_Sound, distance: f32) ---
	ma_sound_set_doppler_factor :: proc(sound: ^Ma_Sound, factor: f32) ---
}
