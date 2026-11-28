package engine

import "core:fmt"
import "core:mem"
import "system"

// The mix format when no device chooses one.
AUDIO_CHANNELS :: 2
AUDIO_SAMPLE_RATE :: 48000
// On the web a device is an AudioContext, and a browser warns about one that
// starts before the player's first input.
AUDIO_DEVICE_LATER :: ODIN_OS == .Freestanding
// The frames that audio_advance mixes per read.
AUDIO_ADVANCE_FRAMES :: 1024

// The host always has an ma_engine, so no other code checks for one. If the
// device does not open, the engine has no device and the run is silent.
Audio :: struct {
	engine:        Ma_Engine,
	engine_ready:  bool,
	device:        bool,
	// audio_open_device has a device to open.
	device_wanted: bool,
	sounds:        Sound_Table,
	voices:        Voice_Pool,
	speakers:      Speaker_Pairing,
	// The last Camera audio_listen set, for an engine that replaces the first.
	listener:      Scene_Camera,
	listening:     bool,
	// The part of a frame that audio_advance has not mixed yet.
	advance_left:  f64,
}

// device is false in a Headless run. With later, the run starts with no
// device and audio_open_device opens it. audio must not move until
// audio_shutdown, because miniaudio keeps pointers into the engine.
audio_init :: proc(audio: ^Audio, device: bool, later := AUDIO_DEVICE_LATER) {
	audio_engine_start(audio, device = device && !later, fixed_format = false)
	audio.engine_ready = true
	audio.device_wanted = device && later
}

// Runs before each voice starts and, on the web, at the player's first input.
// No voice may hold the engine when it is replaced. The new engine keeps the
// mix format, because each Sound decoded to it.
audio_open_device :: proc(audio: ^Audio) {
	if !audio.device_wanted {
		return
	}
	audio.device_wanted = false
	ma_engine_uninit(&audio.engine)
	audio_engine_start(audio, device = true, fixed_format = true)
	if audio.listening {
		audio_listen(audio, audio.listener)
	}
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
	audio.listener = camera
	audio.listening = true
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

// With no device, only a failed allocation fails.
@(private = "file")
audio_engine_start :: proc(audio: ^Audio, device, fixed_format: bool) {
	if device {
		result := audio_engine_init(&audio.engine, device = true, fixed_format = fixed_format)
		if result == MA_SUCCESS {
			audio.device = true
			return
		}
		system.eprintfln("the audio device did not open: %v. The run has no sound.", ma_result_description(result))
	}
	result := audio_engine_init(&audio.engine, device = false, fixed_format = true)
	fmt.assertf(result == MA_SUCCESS, "the audio engine did not start: %v", ma_result_description(result))
}

// A device with a fixed format converts from it to its own.
@(private = "file")
audio_engine_init :: proc(engine: ^Ma_Engine, device, fixed_format: bool) -> Ma_Result {
	config := ma_engine_config_init()
	config.no_device = b32(!device)
	if fixed_format {
		config.channels = AUDIO_CHANNELS
		config.sample_rate = AUDIO_SAMPLE_RATE
	}
	return ma_engine_init(&config, engine)
}
