package engine

import "core:fmt"
import "core:mem"

Voice_Use :: enum u8 {
	Free,
	Play,
	Loop,
}

// One ma_sound and its own data source over the samples of a Sound. A voice
// in use must not move, so the pool never grows.
Voice :: struct {
	sound:    Ma_Sound,
	source:   Ma_Audio_Buffer_Ref,
	use:      Voice_Use,
	// Unload stops the voices of a Sound by its id.
	sound_id: u32,
	// The take count when the voice was taken. The oldest Play has the least.
	taken:    u64,
}

// The voices from perm, sized by Capacity.voices. Each log is once per run.
Voice_Pool :: struct {
	voices:         []Voice,
	free:           []int,
	free_count:     int,
	takes:          u64,
	steal_logged:   bool,
	no_play_logged: bool,
	pitch_logged:   bool,
	failed_logged:  bool,
	perm:           mem.Allocator,
}

voice_pool_init :: proc(pool: ^Voice_Pool, capacity: int, perm: mem.Allocator) {
	fmt.assertf(capacity >= 1 && capacity <= SLOT_LIMIT, "a pool of %v voices cannot play a Sound", capacity)
	pool.perm = perm
	pool.voices = make([]Voice, capacity, perm)
	pool.free = make([]int, capacity, perm)
	// Pops voice 0 first, so the voices fill in order.
	for i in 0 ..< capacity {
		pool.free[i] = capacity - 1 - i
	}
	pool.free_count = capacity
}

// Runs before ma_engine_uninit, because each ma_sound_uninit reads the
// engine. A pool never made frees nothing.
voice_pool_destroy :: proc(pool: ^Voice_Pool) {
	for i in 0 ..< len(pool.voices) {
		if pool.voices[i].use != .Free {
			voice_release(pool, i)
		}
	}
	delete(pool.voices, pool.perm)
	delete(pool.free, pool.perm)
	pool^ = {}
}

// A free voice, or the voice of a finished sound. When none is left, a Play
// takes the voice of the oldest Play, and a Loop gets none.
voice_take :: proc(pool: ^Voice_Pool, use: Voice_Use) -> (index: int, ok: bool) {
	assert(use != .Free)
	if pool.free_count == 0 {
		voices_reap(pool)
	}
	if pool.free_count > 0 {
		pool.free_count -= 1
		index = pool.free[pool.free_count]
	} else if use == .Loop {
		return 0, false
	} else {
		index, ok = voice_oldest_play(pool)
		if !ok {
			if !pool.no_play_logged {
				pool.no_play_logged = true
				fmt.eprintfln("all %v voices hold Loops; a Play plays nothing", len(pool.voices))
			}
			return 0, false
		}
		if !pool.steal_logged {
			pool.steal_logged = true
			fmt.eprintfln("all %v voices are in use; a Play takes the voice of the oldest Play", len(pool.voices))
		}
		// voice_release pushes the index, so this pops it again.
		voice_release(pool, index)
		pool.free_count -= 1
	}
	pool.takes += 1
	pool.voices[index].use = use
	pool.voices[index].taken = pool.takes
	return index, true
}

// Starts a voice from voice_take on sound, which must outlive the voice. A
// Loop's voice repeats. If miniaudio fails, the voice frees and plays nothing.
voice_start :: proc(pool: ^Voice_Pool, index: int, engine: ^Ma_Engine, sound: ^Sound, sound_id: u32, gain, pitch: f32, at: Place) -> bool {
	v := &pool.voices[index]
	assert(v.use != .Free, "voice_take gives the voice")
	v.sound_id = sound_id
	result := ma_audio_buffer_ref_init(MA_FORMAT_F32, sound.channels, raw_data(sound.samples), sound.frames, &v.source)
	if result == MA_SUCCESS {
		result = ma_sound_init_from_data_source(engine, &v.source, 0, nil, &v.sound)
		if result != MA_SUCCESS {
			ma_audio_buffer_ref_uninit(&v.source)
		}
	}
	if result != MA_SUCCESS {
		if !pool.failed_logged {
			pool.failed_logged = true
			fmt.eprintfln("a voice did not start: %v; playing nothing", ma_result_description(result))
		}
		voice_free(pool, index)
		return false
	}
	ma_sound_set_looping(&v.sound, b32(v.use == .Loop))
	ma_sound_set_doppler_factor(&v.sound, 0)
	voice_set(pool, index, gain, pitch, at)
	ma_sound_start(&v.sound)
	return true
}

// A negative gain plays as 0, a pitch of 0 or less plays at 1, and an At with
// a range of 0 or less is silent. It applies at once to a playing voice.
voice_set :: proc(pool: ^Voice_Pool, index: int, gain, pitch: f32, at: Place) {
	v := &pool.voices[index]
	volume := max(gain, 0)
	rate := pitch
	if !(pitch > 0) {
		if !pool.pitch_logged {
			pool.pitch_logged = true
			fmt.eprintfln("a pitch of %v is not above 0; playing at 1", pitch)
		}
		rate = 1
	}
	ma_sound_set_pitch(&v.sound, rate)

	switch at.tag {
	case .Here:
		ma_sound_set_spatialization_enabled(&v.sound, false)
	case .At:
		place := at.payload.at
		if !(place.range > 0) {
			volume = 0
		}
		// The linear model falls from 1 at the Listener to 0 at max distance.
		ma_sound_set_spatialization_enabled(&v.sound, true)
		ma_sound_set_positioning(&v.sound, MA_POSITIONING_ABSOLUTE)
		ma_sound_set_attenuation_model(&v.sound, MA_ATTENUATION_MODEL_LINEAR)
		ma_sound_set_min_distance(&v.sound, 0)
		ma_sound_set_max_distance(&v.sound, max(place.range, 0))
		ma_sound_set_rolloff(&v.sound, 1)
		ma_sound_set_min_gain(&v.sound, 0)
		ma_sound_set_max_gain(&v.sound, 1)
		ma_sound_set_position(&v.sound, place.pos.x, place.pos.y, place.pos.z)
	}
	ma_sound_set_volume(&v.sound, volume)
}

// Stops the voice at once and frees it.
voice_release :: proc(pool: ^Voice_Pool, index: int) {
	v := &pool.voices[index]
	assert(v.use != .Free, "a free voice holds no sound")
	ma_sound_uninit(&v.sound)
	ma_audio_buffer_ref_uninit(&v.source)
	voice_free(pool, index)
}

// Frees each voice whose sound has stopped: a Play at its end, or a Loop
// after its fade.
voices_reap :: proc(pool: ^Voice_Pool) {
	for i in 0 ..< len(pool.voices) {
		if pool.voices[i].use != .Free && !ma_sound_is_playing(&pool.voices[i].sound) {
			voice_release(pool, i)
		}
	}
}

// A voice reads the samples of its Sound in place, so Unload stops each
// voice of a Sound before it frees the Sound.
voices_stop_sound :: proc(pool: ^Voice_Pool, sound_id: u32) {
	for i in 0 ..< len(pool.voices) {
		if pool.voices[i].use != .Free && pool.voices[i].sound_id == sound_id {
			voice_release(pool, i)
		}
	}
}

// Uninit the miniaudio objects of the voice before this.
@(private = "file")
voice_free :: proc(pool: ^Voice_Pool, index: int) {
	pool.voices[index] = {}
	pool.free[pool.free_count] = index
	pool.free_count += 1
}

@(private = "file")
voice_oldest_play :: proc(pool: ^Voice_Pool) -> (index: int, ok: bool) {
	oldest := max(u64)
	for v, i in pool.voices {
		if v.use == .Play && v.taken < oldest {
			oldest = v.taken
			index, ok = i, true
		}
	}
	return
}
