package engine

import "core:fmt"
import "core:mem"
import "system"

// The mix format of the engine, with a device or without one.
AUDIO_CHANNELS :: 2
AUDIO_SAMPLE_RATE :: 48000
// The frames that audio_advance mixes per read.
AUDIO_ADVANCE_FRAMES :: 1024

// The host always has an ma_engine, so no other code checks for one. A run
// with a device starts with an engine that has none and opens the device at
// the first voice, so a game that plays nothing opens no device. On the web
// a device is an AudioContext, and a browser warns about one that starts
// before the player clicks. If the device does not open, the engine has no
// device and the run is silent.
Audio :: struct {
	engine:        Ma_Engine,
	engine_ready:  bool,
	device:        bool,
	// The run may open a device and has not tried yet.
	device_wanted: bool,
	sounds:        Sound_Table,
	voices:        Voice_Pool,
	speakers:      Speaker_Pairing,
	// The part of a frame that audio_advance has not mixed yet.
	advance_left:  f64,
}

// device is false in a Headless run. audio must not move until
// audio_shutdown, because miniaudio keeps pointers into the engine.
audio_init :: proc(audio: ^Audio, device: bool) {
	// With no device, only a failed allocation fails.
	result := audio_engine_init(&audio.engine, device = false)
	fmt.assertf(result == MA_SUCCESS, "the audio engine did not start: %v", ma_result_description(result))
	audio.engine_ready = true
	audio.device_wanted = device
}

// Runs before each voice starts. The first time, no voice has started, so
// nothing holds the engine with no device, and it is swapped for one with a
// device. Both mix at AUDIO_SAMPLE_RATE, the rate each Sound decoded to.
audio_open_device :: proc(audio: ^Audio) {
	if !audio.device_wanted {
		return
	}
	audio.device_wanted = false
	ma_engine_uninit(&audio.engine)
	result := audio_engine_init(&audio.engine, device = true)
	if result == MA_SUCCESS {
		audio.device = true
		return
	}
	system.eprintfln("the audio device did not open: %v. The run has no sound.", ma_result_description(result))
	result = audio_engine_init(&audio.engine, device = false)
	fmt.assertf(result == MA_SUCCESS, "the audio engine did not start: %v", ma_result_description(result))
}

// Runs after launch, because the capacities come from the Launch. Each Sound
// decodes to the rate the engine mixes at.
audio_tables_init :: proc(audio: ^Audio, sounds, voices: int, perm, allocator: mem.Allocator) {
	sound_table_init(&audio.sounds, sounds, ma_engine_get_sample_rate(&audio.engine), perm, allocator)
	voice_pool_init(&audio.voices, voices, perm)
	speaker_pairing_init(&audio.speakers, voices, allocator)
}

// The voices stop before the engine, which each ma_sound_uninit reads, and
// before the Sounds whose samples they read.
audio_shutdown :: proc(audio: ^Audio) {
	if !audio.engine_ready {
		return
	}
	speaker_pairing_destroy(&audio.speakers)
	voice_pool_destroy(&audio.voices)
	ma_engine_uninit(&audio.engine)
	sound_table_destroy(&audio.sounds)
	audio.engine_ready = false
}

audio_play :: proc(audio: ^Audio, play: Play_Command) {
	sound, ok := sound_resolve(&audio.sounds, play.sound)
	if !ok {
		return
	}
	index, taken := voice_take(&audio.voices, .Play)
	if !taken {
		return
	}
	audio_open_device(audio)
	voice_start(&audio.voices, index, &audio.engine, sound, play.sound, play.gain, play.pitch, play.at, looping = false)
}

// The Listener is the Camera of the current Scene, not the interpolated one.
// A zero up, or one along the view, falls back to +y as the render does.
audio_listen :: proc(audio: ^Audio, camera: Scene_Camera) {
	eye := vec3_array(camera.eye)
	forward := vec3_array(camera.target) - eye
	up := vec3_array(camera.up)
	if v3_length(v3_cross(forward, up)) < UP_EPSILON {
		up = UP
	}
	ma_engine_listener_set_position(&audio.engine, 0, eye.x, eye.y, eye.z)
	ma_engine_listener_set_direction(&audio.engine, 0, forward.x, forward.y, forward.z)
	ma_engine_listener_set_world_up(&audio.engine, 0, up.x, up.y, up.z)
}

// An engine with no device mixes only when asked, so the host mixes it by dt
// once per fixed step and drops the frames. Then each Play still ends and
// frees its voice. An engine with a device mixes on its own thread.
audio_advance :: proc(audio: ^Audio, dt: f32) {
	if !audio.engine_ready || audio.device {
		return
	}
	audio.advance_left += f64(dt) * f64(ma_engine_get_sample_rate(&audio.engine))
	frames := u64(audio.advance_left)
	audio.advance_left -= f64(frames)
	dropped: [AUDIO_ADVANCE_FRAMES * AUDIO_CHANNELS]f32
	for frames > 0 {
		count := min(frames, AUDIO_ADVANCE_FRAMES)
		ma_engine_read_pcm_frames(&audio.engine, &dropped, count, nil)
		frames -= count
	}
}

// Unload calls this when the last pack that holds the Sound unloads.
audio_sound_remove :: proc(audio: ^Audio, slot: int) {
	voices_stop_sound(&audio.voices, sound_id(&audio.sounds, slot))
	sound_table_remove(&audio.sounds, slot)
}

// A device converts from the mix format to its own.
@(private = "file")
audio_engine_init :: proc(engine: ^Ma_Engine, device: bool) -> Ma_Result {
	config := ma_engine_config_init()
	config.no_device = b32(!device)
	config.channels = AUDIO_CHANNELS
	config.sample_rate = AUDIO_SAMPLE_RATE
	return ma_engine_init(&config, engine)
}
