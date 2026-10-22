package engine

import "core:fmt"

// The mix format when no device chooses one.
AUDIO_CHANNELS :: 2
AUDIO_SAMPLE_RATE :: 48000

// The host always has an ma_engine, so no other code checks for one. If the
// device does not open, the engine has no device and the run is silent.
Audio :: struct {
	engine:       Ma_Engine,
	engine_ready: bool,
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

audio_shutdown :: proc(audio: ^Audio) {
	if !audio.engine_ready {
		return
	}
	ma_engine_uninit(&audio.engine)
	audio.engine_ready = false
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
