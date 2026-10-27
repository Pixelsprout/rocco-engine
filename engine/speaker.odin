package engine

import "base:runtime"
import "core:fmt"
import "core:mem"

// Long enough that a stopped Speaker does not click.
SPEAKER_FADE_MS :: 5

// A Speaker of the last Scene, with its Place in the world, and the voice it
// holds.
Speaker_Voice :: struct {
	speaker: Speaker,
	// -1 while the Speaker has no voice: it waits for one, its Sound id
	// resolves to nothing, or it is a Once that ended.
	voice:   int,
	// Unload can free the voice and another sound can take it, so the
	// Speaker holds the voice only while the voice keeps this take count.
	taken:   u64,
	// A Once that played to its end stays silent until its Sound id changes
	// or its id leaves the Scene.
	ended:   bool,
}

// Pairs the Speakers of each Scene with the Speakers of the one before by
// Speaker id. prev and curr swap after each pairing and keep their capacity,
// so they stop allocating once they have held the most Speakers a Scene had.
Speaker_Pairing :: struct {
	prev, curr:             [dynamic]Speaker_Voice,
	prev_index, curr_index: map[u64]int,
	// Each duplicate Speaker id logs once per run.
	logged:                 map[u64]struct {},
	wait_logged:            bool,
}

speaker_pairing_init :: proc(p: ^Speaker_Pairing, capacity: int, allocator: mem.Allocator) {
	p.prev = make([dynamic]Speaker_Voice, 0, capacity, allocator)
	p.curr = make([dynamic]Speaker_Voice, 0, capacity, allocator)
	p.prev_index = make(map[u64]int, allocator)
	p.curr_index = make(map[u64]int, allocator)
	// A map grows once it is MAP_LOAD_FACTOR percent full, not when it is full.
	reserve(&p.prev_index, capacity * 100 / runtime.MAP_LOAD_FACTOR + 1)
	reserve(&p.curr_index, capacity * 100 / runtime.MAP_LOAD_FACTOR + 1)
	p.logged = make(map[u64]struct {}, allocator)
}

// The voices stay with the pool, which frees them.
speaker_pairing_destroy :: proc(p: ^Speaker_Pairing) {
	delete(p.prev)
	delete(p.curr)
	delete(p.prev_index)
	delete(p.curr_index)
	delete(p.logged)
	p^ = {}
}

// Runs after each view on the current Scene's Nodes. A missing Speaker id
// fades out, and voices_reap frees its voice when the fade ends. A changed
// Sound id restarts at once with no fade. A Once that ended frees its voice
// at once. Any other Speaker with no voice tries again on each call while it
// stays in the Scene.
audio_speakers :: proc(audio: ^Audio, nodes: []Node) {
	p := &audio.speakers
	pool := &audio.voices
	clear(&p.curr)
	clear(&p.curr_index)
	speakers_gather(p, nodes)

	for old in p.prev {
		if old.speaker.id not_in p.curr_index && speaker_holds_voice(pool, old) {
			ma_sound_stop_with_fade_in_milliseconds(&pool.voices[old.voice].sound, SPEAKER_FADE_MS)
		}
	}

	for &entry in p.curr {
		i, paired := p.prev_index[entry.speaker.id]
		if !paired {
			speaker_start(audio, &entry)
			continue
		}
		old := p.prev[i].speaker
		holds := speaker_holds_voice(pool, entry)
		if old.sound != entry.speaker.sound {
			if holds {
				voice_release(pool, entry.voice)
			}
			entry.voice = -1
			entry.ended = false
			speaker_start(audio, &entry)
			continue
		}
		if speaker_once_ended(pool, entry, old.repeat) {
			if holds {
				voice_release(pool, entry.voice)
			}
			entry.voice = -1
			entry.ended = true
		}
		if entry.ended {
			continue
		}
		if !holds {
			entry.voice = -1
			speaker_start(audio, &entry)
			continue
		}
		v := &pool.voices[entry.voice]
		if old.repeat != entry.speaker.repeat {
			ma_sound_set_looping(&v.sound, b32(entry.speaker.repeat == .Loop))
		}
		if old.gain != entry.speaker.gain || old.pitch != entry.speaker.pitch || !place_equal(old.at, entry.speaker.at) {
			voice_set(pool, entry.voice, entry.speaker.gain, entry.speaker.pitch, entry.speaker.at)
		}
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

// Fills p.curr in walk order.
@(private = "file")
speakers_gather :: proc(p: ^Speaker_Pairing, nodes: []Node) {
	walk := Tree_Walk {
		visit = speaker_visit,
		data  = p,
	}
	root := WALK_ROOT
	for &node, i in nodes {
		#partial switch node.tag {
		case .Speaker:
			speaker_pair(p, node.payload.speaker)
		case .Group:
			tree_walk(&walk, nodes[i:i + 1], &root)
		}
	}
}

// The Speaker's Place comes from the walked Scene, with no interpolation, as
// the Listener does. A Here Speaker ignores its Group.
@(private = "file")
speaker_visit :: proc(walk: ^Tree_Walk, node: ^Node, parent: ^Walk_Parent) {
	if node.tag != .Speaker {
		return
	}
	speaker := node.payload.speaker
	if parent.id.grouped && speaker.at.tag == .At {
		at := &speaker.at.payload.at
		at.pos = to_vec3(pose_compose(parent.scene_world, {pos = vec3_array(at.pos), rot = 1}).pos)
	}
	speaker_pair((^Speaker_Pairing)(walk.data), speaker)
}

// The first Speaker of an id in the walk plays.
@(private = "file")
speaker_pair :: proc(p: ^Speaker_Pairing, speaker: Speaker) {
	if speaker.id in p.curr_index {
		if speaker.id not_in p.logged {
			p.logged[speaker.id] = {}
			fmt.eprintfln("two Speakers share id %v; the first one plays", speaker.id)
		}
		return
	}
	p.curr_index[speaker.id] = len(p.curr)
	entry := Speaker_Voice {
		speaker = speaker,
		voice   = -1,
	}
	if i, had := p.prev_index[speaker.id]; had {
		entry.voice, entry.taken, entry.ended = p.prev[i].voice, p.prev[i].taken, p.prev[i].ended
	}
	append(&p.curr, entry)
}

@(private = "file")
speaker_holds_voice :: proc(pool: ^Voice_Pool, entry: Speaker_Voice) -> bool {
	if entry.voice < 0 {
		return false
	}
	v := &pool.voices[entry.voice]
	return v.use == .Speaker && v.taken == entry.taken
}

// A held voice stops only at the end of a Once, even one that became a Loop
// as it ended. voices_reap can free that voice first, so a lost Once also
// ended. A lost Loop went to Unload. A Once that Unload took counts as ended,
// which sounds the same, because its stale Sound id plays nothing.
@(private = "file")
speaker_once_ended :: proc(pool: ^Voice_Pool, entry: Speaker_Voice, prev_repeat: Speaker_Repeat) -> bool {
	if entry.voice < 0 {
		return false
	}
	if speaker_holds_voice(pool, entry) {
		return !ma_sound_is_playing(&pool.voices[entry.voice].sound)
	}
	return prev_repeat == .Once
}

@(private = "file")
speaker_start :: proc(audio: ^Audio, entry: ^Speaker_Voice) {
	sound, ok := sound_resolve(&audio.sounds, entry.speaker.sound)
	if !ok {
		return
	}
	index, taken := voice_take(&audio.voices, .Speaker)
	if !taken {
		if !audio.speakers.wait_logged {
			audio.speakers.wait_logged = true
			fmt.eprintfln("all %v voices are in use; a new Speaker waits silent for a free voice", len(audio.voices.voices))
		}
		return
	}
	speaker := entry.speaker
	if voice_start(&audio.voices, index, &audio.engine, sound, speaker.sound, speaker.gain, speaker.pitch, speaker.at, looping = speaker.repeat == .Loop) {
		entry.voice = index
		entry.taken = audio.voices.voices[index].taken
	}
}
