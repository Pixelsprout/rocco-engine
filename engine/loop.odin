package engine

import "base:runtime"
import "core:fmt"
import "core:mem"

// Long enough that a stopped Loop does not click.
LOOP_FADE_MS :: 5

// A Loop of the last Scene and the voice it holds.
Loop_Voice :: struct {
	loop:  Loop,
	// -1 while the Loop has no voice: it waits for one, or its Sound id
	// resolves to nothing.
	voice: int,
	// Unload can free the voice and another sound can take it, so the Loop
	// holds the voice only while the voice keeps this take count.
	taken: u64,
}

// Pairs the Loops of each Scene with the Loops of the one before by Loop id.
// prev and curr swap after each pairing and keep their capacity, so they stop
// allocating once they have held the most Loops a Scene had.
Loop_Pairing :: struct {
	prev, curr:             [dynamic]Loop_Voice,
	prev_index, curr_index: map[u64]int,
	// Each duplicate Loop id logs once per run.
	logged:                 map[u64]struct {},
	wait_logged:            bool,
}

loop_pairing_init :: proc(p: ^Loop_Pairing, capacity: int, allocator: mem.Allocator) {
	p.prev = make([dynamic]Loop_Voice, 0, capacity, allocator)
	p.curr = make([dynamic]Loop_Voice, 0, capacity, allocator)
	p.prev_index = make(map[u64]int, allocator)
	p.curr_index = make(map[u64]int, allocator)
	// A map grows once it is MAP_LOAD_FACTOR percent full, not when it is full.
	reserve(&p.prev_index, capacity * 100 / runtime.MAP_LOAD_FACTOR + 1)
	reserve(&p.curr_index, capacity * 100 / runtime.MAP_LOAD_FACTOR + 1)
	p.logged = make(map[u64]struct {}, allocator)
}

// The voices stay with the pool, which frees them.
loop_pairing_destroy :: proc(p: ^Loop_Pairing) {
	delete(p.prev)
	delete(p.curr)
	delete(p.prev_index)
	delete(p.curr_index)
	delete(p.logged)
	p^ = {}
}

// Runs after each view. A missing Loop id fades out, and voices_reap frees its
// voice when the fade ends. A changed Sound id restarts at once with no fade.
// A Loop with no voice tries again on each call while it stays in the Scene.
audio_loops :: proc(audio: ^Audio, loops: []Loop) {
	p := &audio.loops
	pool := &audio.voices
	clear(&p.curr)
	clear(&p.curr_index)
	for loop in loops {
		if loop.id in p.curr_index {
			if loop.id not_in p.logged {
				p.logged[loop.id] = {}
				fmt.eprintfln("two Loops share id %v; the first one plays", loop.id)
			}
			continue
		}
		p.curr_index[loop.id] = len(p.curr)
		entry := Loop_Voice {
			loop  = loop,
			voice = -1,
		}
		if i, had := p.prev_index[loop.id]; had {
			entry.voice, entry.taken = p.prev[i].voice, p.prev[i].taken
		}
		append(&p.curr, entry)
	}

	for old in p.prev {
		if old.loop.id not_in p.curr_index && loop_holds_voice(pool, old) {
			ma_sound_stop_with_fade_in_milliseconds(&pool.voices[old.voice].sound, LOOP_FADE_MS)
		}
	}

	for &entry in p.curr {
		if loop_holds_voice(pool, entry) {
			old := p.prev[p.prev_index[entry.loop.id]].loop
			if old.sound != entry.loop.sound {
				voice_release(pool, entry.voice)
			} else {
				if old.gain != entry.loop.gain || old.pitch != entry.loop.pitch || !place_equal(old.at, entry.loop.at) {
					voice_set(pool, entry.voice, entry.loop.gain, entry.loop.pitch, entry.loop.at)
				}
				continue
			}
		}
		entry.voice = -1
		loop_start(audio, &entry)
	}

	p.prev, p.curr = p.curr, p.prev
	p.prev_index, p.curr_index = p.curr_index, p.prev_index
}

place_equal :: proc(a, b: Place) -> bool {
	if a.tag != b.tag {
		return false
	}
	switch a.tag {
	case .Here:
		return true
	case .At:
		return a.payload.at.pos == b.payload.at.pos && a.payload.at.range == b.payload.at.range
	}
	return false
}

@(private = "file")
loop_holds_voice :: proc(pool: ^Voice_Pool, entry: Loop_Voice) -> bool {
	if entry.voice < 0 {
		return false
	}
	v := &pool.voices[entry.voice]
	return v.use == .Loop && v.taken == entry.taken
}

// Sound id 0 or a stale id plays nothing and logs once.
@(private = "file")
loop_start :: proc(audio: ^Audio, entry: ^Loop_Voice) {
	sound, ok := sound_resolve(&audio.sounds, entry.loop.sound)
	if !ok {
		return
	}
	index, taken := voice_take(&audio.voices, .Loop)
	if !taken {
		if !audio.loops.wait_logged {
			audio.loops.wait_logged = true
			fmt.eprintfln("all %v voices are in use; a new Loop waits silent for a free voice", len(audio.voices.voices))
		}
		return
	}
	loop := entry.loop
	if voice_start(&audio.voices, index, &audio.engine, sound, loop.sound, loop.gain, loop.pitch, loop.at) {
		entry.voice = index
		entry.taken = audio.voices.voices[index].taken
	}
}
