#+test
package engine

import "core:os"
import "core:testing"

// LOOP_FADE_MS at the mix rate, with room for the resampler's delay.
FADE_FRAMES :: AUDIO_SAMPLE_RATE * LOOP_FADE_MS / 1000 + 64

fake_loop :: proc(id: u64, sound: u32, gain: f32 = 1, pitch: f32 = 1, at := Place{tag = .Here}) -> Loop {
	return {id = id, sound = sound, gain = gain, pitch = pitch, at = at}
}

// The voice that the Loop of the last Scene holds.
fake_loop_voice :: proc(id: u64) -> (voice: ^Voice, ok: bool) {
	pairing := &g_fake.audio.loops
	index := pairing.prev_index[id] or_return
	entry := pairing.prev[index]
	if entry.voice < 0 {
		return nil, false
	}
	return &g_fake.audio.voices.voices[entry.voice], true
}

@(test)
test_a_new_loop_id_starts_a_voice_that_repeats :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id

	g_fake.loops = {fake_loop(1, low)}
	fake_step_with(&s)
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)

	mix_skip(2 * TONE_FRAMES)
	fake_step_with(&s)
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_missing_loop_id_fades_its_voice_to_silence :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.loops = {fake_loop(1, low)}
	fake_step_with(&s)
	mix_read(MIX_FRAMES)

	g_fake.loops = nil
	fake_step_with(&s)
	mixed := mix_read(MIX_FRAMES)

	// The fade starts at the Loop's level, so the cut does not click.
	testing.expect(t, abs(mix_peak(mixed[:8 * AUDIO_CHANNELS]) - LOW_LEVEL) < LEVEL_EPSILON)
	testing.expect_value(t, mix_peak(mixed[FADE_FRAMES * AUDIO_CHANNELS:]), 0)
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)
	testing.expect(t, !fake_voice_playing(0))
	voices_reap(&g_fake.audio.voices)
	testing.expect_value(t, fake_voices_in_use(), 0)
}

@(test)
test_a_loop_id_that_comes_back_during_its_fade_takes_a_new_voice :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.loops = {fake_loop(1, low)}
	fake_step_with(&s)
	g_fake.loops = nil
	fake_step_with(&s)

	g_fake.loops = {fake_loop(1, low)}
	fake_step_with(&s)
	voice, ok := fake_loop_voice(1)
	testing.expect(t, ok)
	testing.expect(t, voice == &g_fake.audio.voices.voices[1])

	mix_skip(MIX_FRAMES)
	testing.expect(t, !fake_voice_playing(0))
	testing.expect(t, fake_voice_playing(1))
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_changed_gain_pitch_or_place_applies_to_the_same_voice :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.camera = camera_facing_forward()
	g_fake.loops = {fake_loop(1, low)}
	fake_step_with(&s)
	voice, _ := fake_loop_voice(1)
	taken := voice.taken

	g_fake.loops = {fake_loop(1, low, gain = 0.5, pitch = 2)}
	fake_step_with(&s)
	mix_read(MIX_FRAMES)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL * 0.5) < LEVEL_EPSILON)
	testing.expect_value(t, ma_sound_get_pitch(&voice.sound), 2)

	// Past its range. The gain glides to 0, and never quite reaches it.
	g_fake.loops = {fake_loop(1, low, gain = 0.5, pitch = 2, at = place_at({0, 0, -20}, 10))}
	fake_step_with(&s)
	mix_skip(TONE_FRAMES / 2)
	testing.expect(t, mix_peak(mix_read(MIX_FRAMES)) < 1e-4)

	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect_value(t, voice.taken, taken)
}

@(test)
test_a_changed_sound_id_restarts_the_voice :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id
	g_fake.loops = {fake_loop(1, low)}
	fake_step_with(&s)
	voice, _ := fake_loop_voice(1)
	taken := voice.taken
	mix_read(MIX_FRAMES)

	g_fake.loops = {fake_loop(1, high)}
	fake_step_with(&s)

	restarted, ok := fake_loop_voice(1)
	testing.expect(t, ok)
	testing.expect(t, restarted.taken > taken)
	testing.expect_value(t, restarted.sound_id, high)
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - HIGH_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_two_loops_with_one_id_keep_the_first_and_log_once :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id

	g_fake.loops = {fake_loop(1, low), fake_loop(1, high)}
	fake_step_with(&s)
	fake_step_with(&s)

	testing.expect_value(t, len(g_fake.audio.loops.logged), 1)
	testing.expect_value(t, fake_voices_in_use(), 1)
	voice, _ := fake_loop_voice(1)
	testing.expect_value(t, voice.sound_id, low)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_new_loop_waits_for_a_voice_and_starts_when_one_frees :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id

	g_fake.loops = {fake_loop(1, low), fake_loop(2, low), fake_loop(3, high)}
	fake_step_with(&s)
	testing.expect(t, g_fake.audio.loops.wait_logged)
	_, waiting := fake_loop_voice(3)
	testing.expect(t, !waiting)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - 2 * LOW_LEVEL) < LEVEL_EPSILON)

	// Loop 1's voice frees once its fade ends.
	g_fake.loops = {fake_loop(2, low), fake_loop(3, high)}
	fake_step_with(&s)
	_, waiting = fake_loop_voice(3)
	testing.expect(t, !waiting)
	mix_skip(MIX_FRAMES)
	fake_step_with(&s)

	voice, started := fake_loop_voice(3)
	testing.expect(t, started)
	testing.expect_value(t, voice.sound_id, high)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - (LOW_LEVEL + HIGH_LEVEL)) < LEVEL_EPSILON)
}

@(test)
test_unload_stops_a_loop_and_its_stale_id_plays_nothing :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low"), fake_load("B", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, _ := sound_table_find(&g_fake.audio.sounds, "sound/low")
	high, _ := sound_table_find(&g_fake.audio.sounds, "sound/high")
	g_fake.loops = {fake_loop(1, low)}
	fake_step_with(&s)

	// The Play takes the voice that the Unload freed.
	fake_step_with(&s, fake_unload("A"), fake_play(high, 1, 1, place_here()))
	fake_step_with(&s)

	_, ok := fake_loop_voice(1)
	testing.expect(t, !ok)
	testing.expect_value(t, len(g_fake.audio.sounds.logged), 1)
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect_value(t, g_fake.audio.voices.voices[0].use, Voice_Use.Play)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - HIGH_LEVEL) < LEVEL_EPSILON)
}
