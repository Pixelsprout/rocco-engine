package engine

import "core:fmt"
import "core:mem"

// The mix format when no device chooses one.
AUDIO_CHANNELS :: 2
AUDIO_SAMPLE_RATE :: 48000

// The host always has an ma_engine, so no other code checks for one. If the
// device does not open, the engine has no device and the run is silent.
Audio :: struct {
	engine:       Ma_Engine,
	engine_ready: bool,
	sounds:       Sound_Table,
}

// device is false in a Headless run. audio must not move until
// audio_shutdown, because miniaudio keeps pointers into the engine.
audio_init :: proc(audio: ^Audio, device: bool) {
	if device {
		result := audio_engine_init(&audio.engine, device = true)
		if result == MA_SUCCESS {
			audio.engine_ready = true
			return
		}
		fmt.eprintfln("the audio device did not open: %v. The run has no sound.", ma_result_description(result))
	}
	// With no device, only a failed allocation fails.
	result := audio_engine_init(&audio.engine, device = false)
	fmt.assertf(result == MA_SUCCESS, "the audio engine did not start: %v", ma_result_description(result))
	audio.engine_ready = true
}

// Runs after launch, because capacity.sounds comes from the Launch. Each Sound
// decodes to the rate the engine mixes at.
audio_sounds_init :: proc(audio: ^Audio, capacity: int, perm, allocator: mem.Allocator) {
	sound_table_init(&audio.sounds, capacity, ma_engine_get_sample_rate(&audio.engine), perm, allocator)
}

audio_shutdown :: proc(audio: ^Audio) {
	if !audio.engine_ready {
		return
	}
	ma_engine_uninit(&audio.engine)
	sound_table_destroy(&audio.sounds)
	audio.engine_ready = false
}

// Unload calls this when the last pack that holds the Sound unloads.
audio_sound_remove :: proc(audio: ^Audio, slot: int) {
	audio_stop_voices(audio, sound_id(&audio.sounds, slot))
	sound_table_remove(&audio.sounds, slot)
}

// A voice reads the samples of its Sound in place, so it must stop before the
// Sound is freed. No voice exists yet.
audio_stop_voices :: proc(audio: ^Audio, sound: u32) {
}

@(private = "file")
audio_engine_init :: proc(engine: ^Ma_Engine, device: bool) -> Ma_Result {
	config := ma_engine_config_init()
	config.no_device = b32(!device)
	if !device {
		config.channels = AUDIO_CHANNELS
		config.sample_rate = AUDIO_SAMPLE_RATE
	}
	return ma_engine_init(&config, engine)
}
