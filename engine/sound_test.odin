#+test
package engine

import "core:mem"
import "core:os"
import "core:slice"
import "core:testing"

SMALL_SOUNDS :: 3
WAV_RATE :: 48000

Wav_Header :: struct #packed {
	riff:        [4]u8,
	riff_size:   u32le,
	wave:        [4]u8,
	fmt_id:      [4]u8,
	fmt_size:    u32le,
	format:      u16le,
	channels:    u16le,
	sample_rate: u32le,
	byte_rate:   u32le,
	block_align: u16le,
	bits:        u16le,
	data_id:     [4]u8,
	data_size:   u32le,
}

// A PCM16 wav in frame memory. samples holds the frames, interleaved.
wav_make :: proc(channels: int, samples: []i16, sample_rate := WAV_RATE) -> []byte {
	data := slice.to_bytes(samples)
	header := Wav_Header {
		riff        = {'R', 'I', 'F', 'F'},
		riff_size   = u32le(size_of(Wav_Header) - 8 + len(data)),
		wave        = {'W', 'A', 'V', 'E'},
		fmt_id      = {'f', 'm', 't', ' '},
		fmt_size    = 16,
		format      = 1,
		channels    = u16le(channels),
		sample_rate = u32le(sample_rate),
		byte_rate   = u32le(sample_rate * channels * 2),
		block_align = u16le(channels * 2),
		bits        = 16,
		data_id     = {'d', 'a', 't', 'a'},
		data_size   = u32le(len(data)),
	}
	return slice.concatenate([][]byte{mem.ptr_to_bytes(&header), data}, context.temp_allocator)
}

@(test)
test_sound_names_on_disk_are_each_wav_and_ogg_stem_in_sorted_order :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["b.wav"] = wav_make(1, {0})
	files["a.ogg"] = wav_make(1, {0})
	files["notes.txt"] = transmute([]byte)string("not a sound")
	files["c.mp3"] = wav_make(1, {0})
	files["sub/d.wav"] = wav_make(1, {0})
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)

	sound_files := make(map[string]string, context.temp_allocator)
	logged := make(map[string]struct {}, context.temp_allocator)
	names := sound_names_on_disk(dir, &sound_files, &logged, context.temp_allocator)

	testing.expect(t, slice.equal(names, []string{"sound/a", "sound/b"}))
	testing.expect_value(t, len(sound_files), 2)
	testing.expect_value(t, sound_files["sound/a"], "a.ogg")
	testing.expect_value(t, sound_files["sound/b"], "b.wav")
	testing.expect_value(t, len(logged), 0)
}

// The full name sorts, not the stem, so "a-b.wav" comes before "a.wav" on
// disk while "sound/a" comes before "sound/a-b" in the names.
@(test)
test_sound_names_sort_by_name_not_by_file :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["a.wav"] = wav_make(1, {0})
	files["a-b.wav"] = wav_make(1, {0})
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)

	sound_files := make(map[string]string, context.temp_allocator)
	logged := make(map[string]struct {}, context.temp_allocator)
	names := sound_names_on_disk(dir, &sound_files, &logged, context.temp_allocator)

	testing.expect(t, slice.equal(names, []string{"sound/a", "sound/a-b"}))
}

@(test)
test_sound_names_on_disk_of_a_missing_dir_are_none :: proc(t: ^testing.T) {
	sound_files := make(map[string]string, context.temp_allocator)
	logged := make(map[string]struct {}, context.temp_allocator)
	names := sound_names_on_disk(NO_ASSETS_DIR, &sound_files, &logged, context.temp_allocator)
	testing.expect_value(t, len(names), 0)
	testing.expect_value(t, len(sound_files), 0)
}

@(test)
test_sound_load_file_decodes_to_interleaved_f32 :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["pair.wav"] = wav_make(2, {16384, -16384, 0, 32767})
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)

	table: Sound_Table
	sound_table_init(&table, SMALL_SOUNDS, WAV_RATE, context.allocator, context.allocator)
	defer sound_table_destroy(&table)

	id, reason, ok := sound_load_file(&table, dir, "sound/pair", "pair.wav")
	testing.expect(t, ok)
	testing.expect_value(t, reason, "")
	sound, found := sound_resolve(&table, id)
	testing.expect(t, found)
	testing.expect_value(t, sound.name, "sound/pair")
	testing.expect_value(t, sound.channels, 2)
	testing.expect_value(t, sound.frames, 2)
	want := []f32{0.5, -0.5, 0, 32767.0 / 32768}
	testing.expect_value(t, len(sound.samples), len(want))
	for sample, i in sound.samples {
		testing.expect_value(t, sample, want[i])
	}
}

@(test)
test_sound_load_file_resamples_to_the_table_rate :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["low.wav"] = wav_make(1, make([]i16, 100, context.temp_allocator), sample_rate = WAV_RATE / 2)
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)

	table: Sound_Table
	sound_table_init(&table, SMALL_SOUNDS, WAV_RATE, context.allocator, context.allocator)
	defer sound_table_destroy(&table)

	id, _, ok := sound_load_file(&table, dir, "sound/low", "low.wav")
	testing.expect(t, ok)
	sound, _ := sound_resolve(&table, id)
	testing.expect_value(t, sound.channels, 1)
	testing.expect(t, sound.frames >= 198 && sound.frames <= 200)
}

@(test)
test_sound_load_file_of_a_file_it_cannot_decode_leaves_the_table :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["noise.wav"] = transmute([]byte)string("not a sound")
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)

	table: Sound_Table
	sound_table_init(&table, SMALL_SOUNDS, WAV_RATE, context.allocator, context.allocator)
	defer sound_table_destroy(&table)

	id, reason, ok := sound_load_file(&table, dir, "sound/noise", "noise.wav")
	testing.expect(t, !ok)
	testing.expect_value(t, id, 0)
	testing.expect(t, reason != "")
	testing.expect_value(t, table.count, 1)
}

@(test)
test_sound_resolve_of_id_0_plays_nothing_and_logs_once :: proc(t: ^testing.T) {
	table: Sound_Table
	sound_table_init(&table, SMALL_SOUNDS, WAV_RATE, context.allocator, context.allocator)
	defer sound_table_destroy(&table)

	_, first := sound_resolve(&table, 0)
	_, second := sound_resolve(&table, 0)
	testing.expect(t, !first && !second)
	testing.expect_value(t, len(table.logged), 1)
}

@(test)
test_sound_table_destroy_of_a_table_never_made_frees_nothing :: proc(t: ^testing.T) {
	table: Sound_Table
	sound_table_destroy(&table)
}
