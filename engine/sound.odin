package engine

import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

// The reserved slot and one Sound.
SOUND_CAPACITY_MIN :: 2
SOUND_PREFIX :: "sound/"

// samples holds frames * channels f32 values, interleaved, at the sample
// rate of the table. A voice reads them in place, so they must not move or be
// freed while a voice plays the Sound.
Sound :: struct {
	name:       string,
	samples:    []f32,
	channels:   u32,
	frames:     u64,
	live:       bool,
	generation: u16,
}

// Slot 0 is no Sound and is never filled. The table owns each Sound's name
// and samples. The slots never grow.
Sound_Table :: struct {
	sounds:      []Sound,
	count:       int,
	free:        []int,
	free_count:  int,
	logged:      map[u32]struct {},
	sample_rate: u32,
	allocator:   mem.Allocator,
	perm:        mem.Allocator,
}

// The slots come from perm; the names, samples and log from allocator, which
// must free. Each Sound decodes to sample_rate, the rate of the ma_engine.
sound_table_init :: proc(t: ^Sound_Table, capacity: int, sample_rate: u32, perm, allocator: mem.Allocator) {
	fmt.assertf(capacity >= SOUND_CAPACITY_MIN && capacity <= SLOT_LIMIT, "a Sound table of %v slots cannot hold a Sound or give each slot an id", capacity)
	t.allocator = allocator
	t.perm = perm
	t.sample_rate = sample_rate
	t.sounds = make([]Sound, capacity, perm)
	t.free = make([]int, capacity, perm)
	t.logged = make(map[u32]struct {}, allocator)
	t.count = 1
}

// No voice may play a Sound of the table any more. A table never made frees
// nothing.
sound_table_destroy :: proc(t: ^Sound_Table) {
	for &sound in t.sounds {
		if sound.live {
			delete(sound.name, t.allocator)
			delete(sound.samples, t.allocator)
		}
	}
	delete(t.logged)
	delete(t.sounds, t.perm)
	delete(t.free, t.perm)
}

// A Sound id packs the slot and generation as a mesh id does.
sound_id :: proc(t: ^Sound_Table, slot: int) -> u32 {
	return u32(t.sounds[slot].generation) << MESH_SLOT_BITS | u32(slot)
}

sound_slot :: proc(id: u32) -> int {
	return mesh_slot(id)
}

sound_table_full :: proc(t: ^Sound_Table) -> bool {
	return t.free_count == 0 && t.count == len(t.sounds)
}

// Slot 0 holds no Sound, so the table holds one Sound fewer than its slots.
sound_table_full_reason :: proc(t: ^Sound_Table) -> string {
	return fmt.tprintf("the Sound table is full at %v Sounds", len(t.sounds) - 1)
}

sound_table_find :: proc(t: ^Sound_Table, name: string) -> (id: u32, found: bool) {
	for sound, slot in t.sounds[1:t.count] {
		if sound.live && sound.name == name {
			return sound_id(t, slot + 1), true
		}
	}
	return 0, false
}

// Keeps the slot's generation, so a Sound in a reused slot gets a new id.
// sound.name and sound.samples must come from t.allocator.
sound_table_add :: proc(t: ^Sound_Table, sound: Sound) -> (slot: int, ok: bool) {
	if sound_table_full(t) {
		return 0, false
	}
	if t.free_count > 0 {
		t.free_count -= 1
		slot = t.free[t.free_count]
	} else {
		slot = t.count
		t.count += 1
	}
	generation := t.sounds[slot].generation
	t.sounds[slot] = sound
	t.sounds[slot].live = true
	t.sounds[slot].generation = generation
	return slot, true
}

// Empties the slot and adds 1 to its generation, so an id kept from it plays
// nothing. Call audio_sound_remove instead, which stops the voices first.
sound_table_remove :: proc(t: ^Sound_Table, slot: int) {
	fmt.assertf(slot >= 1 && slot < t.count && t.sounds[slot].live, "Sound slot %v holds no Sound", slot)
	sound := &t.sounds[slot]
	delete(sound.name, t.allocator)
	delete(sound.samples, t.allocator)
	sound^ = {generation = sound.generation + 1}
	t.free[t.free_count] = slot
	t.free_count += 1
}

// Id 0, a stale id and an unknown id play nothing. Each is logged once per
// run.
sound_resolve :: proc(t: ^Sound_Table, id: u32) -> (sound: ^Sound, ok: bool) {
	slot := sound_slot(id)
	if id != 0 && slot < t.count && t.sounds[slot].live && sound_id(t, slot) == id {
		return &t.sounds[slot], true
	}
	if id not_in t.logged {
		t.logged[id] = {}
		stale := slot >= 1 && slot < len(t.sounds) && id >> MESH_SLOT_BITS != u32(t.sounds[slot].generation)
		if id == 0 {
			fmt.eprintln("Sound id 0 is no Sound; playing nothing")
		} else if stale {
			fmt.eprintfln("Sound id %v is from an unloaded pack; playing nothing", id)
		} else {
			fmt.eprintfln("Sound id %v is not in the table; playing nothing", id)
		}
	}
	return nil, false
}

// sound/<stem> for each .wav and .ogg file in dir, sorted. files maps each
// name to the file it loads. The files sort by full name and the first of a
// stem wins, so a.ogg loads before a.wav. Each shared stem logs once and goes
// in logged.
sound_names_on_disk :: proc(dir: string, files: ^map[string]string, logged: ^map[string]struct {}, allocator: mem.Allocator) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		if err != .Not_Exist {
			fmt.eprintfln("cannot read %v: %v; no Sound can load from it", dir, os.error_string(err))
		}
		return nil
	}

	file_names := make([dynamic]string, 0, len(entries), context.temp_allocator)
	for e in entries {
		ext := os.ext(e.name)
		if e.type != .Directory && (ext == ".wav" || ext == ".ogg") && os.stem(e.name) != "" {
			append(&file_names, e.name)
		}
	}
	slice.sort(file_names[:])

	names := make([dynamic]string, 0, len(file_names), allocator)
	for file in file_names {
		name := strings.concatenate({SOUND_PREFIX, os.stem(file)}, context.temp_allocator)
		if kept, shared := files^[name]; shared {
			if name not_in logged^ {
				logged^[strings.clone(name, allocator)] = {}
				fmt.eprintfln("%v holds %v and %v; %q loads %v", dir, kept, file, name, kept)
			}
			continue
		}
		files^[strings.clone(name, allocator)] = strings.clone(file, allocator)
		append(&names, strings.clone(name, allocator))
	}
	slice.sort(names[:])
	return names[:]
}

// Decodes dir/file whole into the next free slot, as f32 at the table's
// sample rate with the file's own channels. On failure the table does not
// change and reason says why.
sound_load_file :: proc(t: ^Sound_Table, dir, name, file: string) -> (id: u32, reason: string, ok: bool) {
	if sound_table_full(t) {
		return 0, sound_table_full_reason(t), false
	}
	path := fmt.tprintf("%v/%v", dir, file)
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return 0, fmt.tprintf("%v: %v", path, os.error_string(read_err)), false
	}
	if len(bytes) == 0 {
		return 0, fmt.tprintf("%v is empty", path), false
	}

	config := ma_decoder_config_init(MA_FORMAT_F32, 0, t.sample_rate)
	frame_count: u64
	decoded: rawptr
	result := ma_decode_memory(raw_data(bytes), c.size_t(len(bytes)), &config, &frame_count, &decoded)
	defer ma_free(decoded, &config.allocation_callbacks)
	if result != MA_SUCCESS {
		return 0, fmt.tprintf("%v is not a wav or ogg it can read", path), false
	}
	if frame_count == 0 {
		return 0, fmt.tprintf("%v holds no audio", path), false
	}

	sample_count := int(frame_count) * int(config.channels)
	samples := make([]f32, sample_count, t.allocator)
	copy(samples, ([^]f32)(decoded)[:sample_count])
	sound := Sound {
		name     = strings.clone(name, t.allocator),
		samples  = samples,
		channels = config.channels,
		frames   = frame_count,
	}
	slot, _ := sound_table_add(t, sound)
	return sound_id(t, slot), "", true
}
