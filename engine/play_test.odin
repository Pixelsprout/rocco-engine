#+test
package engine

import "core:os"
import "core:testing"

SMALL_VOICES :: 2
TONE_FRAMES :: WAV_RATE / 10
LOW :: i16(8192)
HIGH :: i16(16384)
LOW_LEVEL :: f32(0.25)
HIGH_LEVEL :: f32(0.5)
MIX_FRAMES :: 1024
// The linear resampler that pitch needs is not exact.
LEVEL_EPSILON :: f32(0.01)

// low, high and wide play TONE_FRAMES; blip plays 3 frames. wide is stereo,
// LOW on the left and -LOW on the right.
play_assets_dir :: proc(t: ^testing.T) -> string {
	files := make(map[string][]byte, context.temp_allocator)
	files["sound/low.wav"] = wav_make(1, tone_samples(TONE_FRAMES, {LOW}))
	files["sound/high.wav"] = wav_make(1, tone_samples(TONE_FRAMES, {HIGH}))
	files["sound/blip.wav"] = wav_make(1, {LOW, LOW, LOW})
	files["sound/wide.wav"] = wav_make(2, tone_samples(TONE_FRAMES, {LOW, -LOW}))
	return temp_assets_dir(t, files)
}

// frame repeated frames times: one value per channel.
tone_samples :: proc(frames: int, frame: []i16) -> []i16 {
	out := make([]i16, frames * len(frame), context.temp_allocator)
	for i in 0 ..< frames {
		copy(out[i * len(frame):], frame)
	}
	return out
}

// Only an engine with no device may be read, and the test owns g_fake.audio's.
mix_read :: proc(frames: int) -> []f32 {
	out := make([]f32, frames * AUDIO_CHANNELS, context.temp_allocator)
	ma_engine_read_pcm_frames(&g_fake.audio.engine, raw_data(out), u64(frames), nil)
	return out
}

// Mixes and drops frames in reads of MIX_FRAMES. A Play stops in the read
// after the one that reaches its end, so one long read would hide the stop.
mix_skip :: proc(frames: int) {
	for left := frames; left > 0; left -= MIX_FRAMES {
		mix_read(min(left, MIX_FRAMES))
	}
}

mix_peak :: proc(samples: []f32) -> f32 {
	peak: f32
	for sample in samples {
		peak = max(peak, abs(sample))
	}
	return peak
}

place_here :: proc() -> Place {
	return {tag = .Here}
}

place_at :: proc(pos: [3]f32, range: f32) -> Place {
	return {tag = .At, payload = {at = {pos = {pos.x, pos.y, pos.z}, range = range}}}
}

// The Listener at the origin, facing -z.
camera_facing_forward :: proc() -> Scene_Camera {
	return {eye = {0, 0, 0}, target = {0, 0, -1}, up = {0, 1, 0}, fov_y = 1}
}

fake_voice_playing :: proc(index: int) -> bool {
	return bool(ma_sound_is_playing(&g_fake.audio.voices.voices[index].sound))
}

fake_voices_in_use :: proc() -> int {
	return SMALL_VOICES - g_fake.audio.voices.free_count
}

@(test)
test_a_play_with_no_device_mixes_samples_that_are_not_zero :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)

	fake_step_with(&s, fake_play(low, 1, 1, place_here()))

	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_the_manifest_gives_a_sound_its_duration_and_other_names_0 :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/blip", "sound/missing", "cube")})
	defer fake_seam_shutdown(&s)

	testing.expect_value(t, g_fake.loaded_durations[0], f32(TONE_FRAMES) / WAV_RATE)
	testing.expect_value(t, g_fake.loaded_durations[1], f32(3) / WAV_RATE)
	testing.expect_value(t, g_fake.loaded_durations[2], 0)
	testing.expect_value(t, g_fake.loaded_durations[3], 0)
}

@(test)
test_a_play_mixes_at_its_gain_and_a_negative_gain_is_silent :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id

	fake_step_with(&s, fake_play(low, -1, 1, place_here()))
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)

	fake_step_with(&s, fake_play(low, 0.5, 1, place_here()))
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL * 0.5) < LEVEL_EPSILON)
}

@(test)
test_a_stereo_sound_keeps_its_channels :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/wide")})
	defer fake_seam_shutdown(&s)

	fake_step_with(&s, fake_play(g_fake.loaded_manifest[0].id, 1, 1, place_here()))

	mixed := mix_read(MIX_FRAMES)
	// Past the first frames, which the resampler delays.
	frame := mixed[16 * AUDIO_CHANNELS:][:AUDIO_CHANNELS]
	testing.expect(t, abs(frame[0] - LOW_LEVEL) < LEVEL_EPSILON)
	testing.expect(t, abs(frame[1] + LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_pitch_is_a_rate :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id

	fake_step_with(&s, fake_play(low, 1, 2, place_here()), fake_play(low, 1, 1, place_here()))
	mix_skip(TONE_FRAMES / 2 + MIX_FRAMES)

	testing.expect(t, !fake_voice_playing(0))
	testing.expect(t, fake_voice_playing(1))
}

@(test)
test_a_pitch_of_zero_or_less_plays_at_1_and_logs_once :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id

	fake_step_with(&s, fake_play(low, 1, 0, place_here()), fake_play(low, 1, -2, place_here()))
	testing.expect(t, g_fake.audio.voices.pitch_logged)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - 2 * LOW_LEVEL) < LEVEL_EPSILON)

	// At 1, each Play still sounds just before its last frame.
	mix_skip(TONE_FRAMES - MIX_FRAMES - 16)
	testing.expect(t, fake_voice_playing(0))
	testing.expect(t, fake_voice_playing(1))
	mix_read(32)
	testing.expect(t, !fake_voice_playing(0))
	testing.expect(t, !fake_voice_playing(1))
}

@(test)
test_a_full_pool_gives_a_play_the_voice_of_the_oldest_play :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id
	voices := g_fake.audio.voices.voices

	fake_step_with(&s, fake_play(low, 1, 1, place_here()), fake_play(high, 1, 1, place_here()))
	testing.expect(t, !g_fake.audio.voices.steal_logged)

	fake_step_with(&s, fake_play(high, 1, 1, place_here()))
	testing.expect(t, g_fake.audio.voices.steal_logged)
	testing.expect_value(t, voices[0].sound_id, high)
	testing.expect_value(t, voices[1].sound_id, high)

	fake_step_with(&s, fake_play(low, 1, 1, place_here()))
	testing.expect_value(t, voices[0].sound_id, high)
	testing.expect_value(t, voices[1].sound_id, low)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - (HIGH_LEVEL + LOW_LEVEL)) < LEVEL_EPSILON)
}

@(test)
test_a_finished_play_frees_its_voice :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/blip", "sound/low")})
	defer fake_seam_shutdown(&s)
	blip, low := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id

	fake_step_with(&s, fake_play(blip, 1, 1, place_here()), fake_play(low, 1, 1, place_here()))
	mix_read(MIX_FRAMES)
	fake_step_with(&s, fake_play(low, 1, 1, place_here()))

	testing.expect(t, !g_fake.audio.voices.steal_logged)
	testing.expect_value(t, g_fake.audio.voices.voices[0].sound_id, low)
	testing.expect_value(t, g_fake.audio.voices.voices[1].sound_id, low)
}

@(test)
test_a_bad_or_stale_sound_id_plays_nothing_and_logs_once :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	stale := g_fake.loaded_manifest[0].id
	fake_step_with(&s, fake_unload("A"))

	fake_step_with(&s, fake_play(0, 1, 1, place_here()), fake_play(stale, 1, 1, place_here()))
	fake_step_with(&s, fake_play(0, 1, 1, place_here()), fake_play(stale, 1, 1, place_here()))

	testing.expect_value(t, len(g_fake.audio.sounds.logged), 2)
	testing.expect_value(t, fake_voices_in_use(), 0)
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)
}

@(test)
test_unload_stops_the_voices_of_each_sound_it_frees :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low"), fake_load("B", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, _ := sound_table_find(&g_fake.audio.sounds, "sound/low")
	high, _ := sound_table_find(&g_fake.audio.sounds, "sound/high")

	fake_step_with(&s, fake_play(low, 1, 1, place_here()), fake_play(high, 1, 1, place_here()))
	fake_step_with(&s, fake_unload("A"))

	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect_value(t, g_fake.audio.voices.voices[1].sound_id, high)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - HIGH_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_an_at_play_at_or_past_its_range_is_silent :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.camera = camera_facing_forward()

	fake_step_with(&s, fake_play(low, 1, 1, place_at({0, 0, -20}, 10)), fake_play(low, 1, 1, place_at({10, 0, 0}, 10)))
	testing.expect_value(t, fake_voices_in_use(), 2)
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)

	mix_skip(TONE_FRAMES)
	fake_step_with(&s, fake_play(low, 1, 1, place_at({0, 0, 0}, 0)))
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)
}

@(test)
test_an_at_play_falls_off_linearly_with_distance :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.camera = camera_facing_forward()

	fake_step_with(&s, fake_play(low, 1, 1, place_at({0, 0, -2.5}, 10)))
	near := mix_peak(mix_read(MIX_FRAMES))
	mix_skip(TONE_FRAMES)
	fake_step_with(&s, fake_play(low, 1, 1, place_at({0, 0, -7.5}, 10)))
	far := mix_peak(mix_read(MIX_FRAMES))

	testing.expect(t, far > 0)
	// Tight enough to catch an approximate normalize in the spatializer.
	testing.expect(t, abs(near / far - 3) < 1e-4)
}

@(test)
test_the_listener_is_the_camera_of_the_current_scene :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.camera = {eye = {0, 0, 30}, target = {0, 0, 29}, up = {0, 1, 0}, fov_y = 1}
	fake_step_with(&s)

	fake_step_with(&s, fake_play(low, 1, 1, place_at({0, 0, 25}, 10)))
	testing.expect(t, mix_peak(mix_read(MIX_FRAMES)) > 0)

	// The gain glides to 0, and never quite reaches it, so check that it is
	// near 0 a while after.
	g_fake.camera = {eye = {0, 0, 100}, target = {0, 0, 99}, up = {0, 1, 0}, fov_y = 1}
	fake_step_with(&s)
	mix_skip(TONE_FRAMES / 2)
	testing.expect(t, mix_peak(mix_read(MIX_FRAMES)) < 1e-4)
}

// A device can mix a voice as soon as it starts, so a Play must start after
// view, once audio_listen has moved the Listener to the new Camera.
@(test)
test_the_plays_of_init_and_step_start_after_view_sets_the_listener :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low"), fake_play(1, 1, 1, place_here())})
	defer fake_seam_shutdown(&s)
	testing.expect_value(t, g_fake.loaded_manifest[0].id, 1)
	testing.expect_value(t, g_fake.view_voices, 0)
	testing.expect_value(t, fake_voices_in_use(), 1)

	fake_step_with(&s, fake_play(1, 1, 1, place_here()))
	testing.expect_value(t, g_fake.view_voices, 1)
	testing.expect_value(t, fake_voices_in_use(), 2)
}

@(test)
test_audio_advance_mixes_an_engine_with_no_device_in_step_time :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	fake_step_with(&s, fake_play(g_fake.loaded_manifest[0].id, 1, 1, place_here()))

	audio_advance(&g_fake.audio, 0.05)
	testing.expect(t, fake_voice_playing(0))
	audio_advance(&g_fake.audio, 0.06)
	testing.expect(t, !fake_voice_playing(0))
	voices_reap(&g_fake.audio.voices)
	testing.expect_value(t, fake_voices_in_use(), 0)
}

@(test)
test_a_play_gets_no_voice_when_speakers_hold_every_voice :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	sound, _ := sound_resolve(&g_fake.audio.sounds, low)
	pool := &g_fake.audio.voices
	for _ in 0 ..< SMALL_VOICES {
		index, ok := voice_take(pool, .Speaker)
		testing.expect(t, ok)
		testing.expect(t, voice_start(pool, index, &g_fake.audio.engine, sound, low, 1, 1, place_here()))
	}
	_, ok := voice_take(pool, .Speaker)
	testing.expect(t, !ok)
	testing.expect(t, !pool.steal_logged && !pool.no_play_logged)

	fake_step_with(&s, fake_play(low, 1, 1, place_here()))
	testing.expect(t, pool.no_play_logged)

	// A Speaker's voice repeats past the end of its Sound.
	mix_skip(TONE_FRAMES + MIX_FRAMES)
	testing.expect(t, fake_voice_playing(0))
	testing.expect(t, fake_voice_playing(1))
}
