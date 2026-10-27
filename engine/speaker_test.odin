#+test
package engine

import "core:math"
import "core:math/linalg"
import "core:os"
import "core:testing"

// SPEAKER_FADE_MS at the mix rate, with room for the resampler's delay.
FADE_FRAMES :: AUDIO_SAMPLE_RATE * SPEAKER_FADE_MS / 1000 + 64

fake_speaker :: proc(id: u64, sound: u32, gain: f32 = 1, pitch: f32 = 1, at := Place{tag = .Here}, repeat := Speaker_Repeat.Loop) -> Speaker {
	return {id = id, sound = sound, gain = gain, pitch = pitch, at = at, repeat = repeat}
}

// The voice that the Speaker of the last Scene holds.
fake_speaker_voice :: proc(id: u64) -> (voice: ^Voice, ok: bool) {
	pairing := &g_fake.audio.speakers
	index := pairing.prev_index[id] or_return
	entry := pairing.prev[index]
	if entry.voice < 0 {
		return nil, false
	}
	return &g_fake.audio.voices.voices[entry.voice], true
}

// The world Place that the host gave the Speaker of the last Scene.
expect_speaker_pos :: proc(t: ^testing.T, id: u64, want: [3]f32, loc := #caller_location) {
	pairing := &g_fake.audio.speakers
	at := pairing.prev[pairing.prev_index[id]].speaker.at
	testing.expect_value(t, at.tag, Place_Tag.At, loc = loc)
	got := vec3_array(at.payload.at.pos)
	testing.expectf(t, linalg.length(got - want) < 1e-4, "got %v, want %v", got, want, loc = loc)
}

// The peak of one channel of a stereo mix: 0 is the left, 1 the right.
channel_peak :: proc(mixed: []f32, channel: int) -> f32 {
	peak: f32
	for i := channel; i < len(mixed); i += AUDIO_CHANNELS {
		peak = max(peak, abs(mixed[i]))
	}
	return peak
}

@(test)
test_a_new_speaker_id_starts_a_voice_that_repeats :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id

	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)

	mix_skip(2 * TONE_FRAMES)
	fake_step_with(&s)
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_missing_speaker_id_fades_its_voice_to_silence :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	mix_read(MIX_FRAMES)

	g_fake.speakers = nil
	fake_step_with(&s)
	mixed := mix_read(MIX_FRAMES)

	// The fade starts at the Speaker's level, so the cut does not click.
	testing.expect(t, abs(mix_peak(mixed[:8 * AUDIO_CHANNELS]) - LOW_LEVEL) < LEVEL_EPSILON)
	testing.expect_value(t, mix_peak(mixed[FADE_FRAMES * AUDIO_CHANNELS:]), 0)
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)
	testing.expect(t, !fake_voice_playing(0))
	voices_reap(&g_fake.audio.voices)
	testing.expect_value(t, fake_voices_in_use(), 0)
}

@(test)
test_a_speaker_id_that_comes_back_during_its_fade_takes_a_new_voice :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	g_fake.speakers = nil
	fake_step_with(&s)

	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	voice, ok := fake_speaker_voice(1)
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
	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	voice, _ := fake_speaker_voice(1)
	taken := voice.taken

	g_fake.speakers = {fake_speaker(1, low, gain = 0.5, pitch = 2)}
	fake_step_with(&s)
	mix_read(MIX_FRAMES)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL * 0.5) < LEVEL_EPSILON)
	testing.expect_value(t, ma_sound_get_pitch(&voice.sound), 2)

	// Past its range. The gain glides to 0, and never quite reaches it.
	g_fake.speakers = {fake_speaker(1, low, gain = 0.5, pitch = 2, at = place_at({0, 0, -20}, 10))}
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
	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	voice, _ := fake_speaker_voice(1)
	taken := voice.taken
	mix_read(MIX_FRAMES)

	g_fake.speakers = {fake_speaker(1, high)}
	fake_step_with(&s)

	restarted, ok := fake_speaker_voice(1)
	testing.expect(t, ok)
	testing.expect(t, restarted.taken > taken)
	testing.expect_value(t, restarted.sound_id, high)
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - HIGH_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_two_speakers_with_one_id_keep_the_first_and_log_once :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id

	g_fake.speakers = {fake_speaker(1, low), fake_speaker(1, high)}
	fake_step_with(&s)
	fake_step_with(&s)

	testing.expect_value(t, len(g_fake.audio.speakers.logged), 1)
	testing.expect_value(t, fake_voices_in_use(), 1)
	voice, _ := fake_speaker_voice(1)
	testing.expect_value(t, voice.sound_id, low)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_new_speaker_waits_for_a_voice_and_starts_when_one_frees :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id

	g_fake.speakers = {fake_speaker(1, low), fake_speaker(2, low), fake_speaker(3, high)}
	fake_step_with(&s)
	testing.expect(t, g_fake.audio.speakers.wait_logged)
	_, waiting := fake_speaker_voice(3)
	testing.expect(t, !waiting)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - 2 * LOW_LEVEL) < LEVEL_EPSILON)

	// Speaker 1's voice frees once its fade ends.
	g_fake.speakers = {fake_speaker(2, low), fake_speaker(3, high)}
	fake_step_with(&s)
	_, waiting = fake_speaker_voice(3)
	testing.expect(t, !waiting)
	mix_skip(MIX_FRAMES)
	fake_step_with(&s)

	voice, started := fake_speaker_voice(3)
	testing.expect(t, started)
	testing.expect_value(t, voice.sound_id, high)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - (LOW_LEVEL + HIGH_LEVEL)) < LEVEL_EPSILON)
}

@(test)
test_unload_stops_a_speaker_and_its_stale_id_plays_nothing :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low"), fake_load("B", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, _ := sound_table_find(&g_fake.audio.sounds, "sound/low")
	high, _ := sound_table_find(&g_fake.audio.sounds, "sound/high")
	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)

	// The Play takes the voice that the Unload freed.
	fake_step_with(&s, fake_unload("A"), fake_play(high, 1, 1, place_here()))
	fake_step_with(&s)

	_, ok := fake_speaker_voice(1)
	testing.expect(t, !ok)
	testing.expect_value(t, len(g_fake.audio.sounds.logged), 1)
	testing.expect_value(t, fake_voices_in_use(), 1)
	testing.expect_value(t, g_fake.audio.voices.voices[0].use, Voice_Use.Play)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - HIGH_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_speaker_in_a_group_sounds_at_its_composed_world_place :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.camera = camera_facing_forward()
	hum := []Node{node_speaker(fake_speaker(1, low, at = place_at({0, 0, -2}, 10)))}
	inner := []Node{node_group(6, {x = 1}, {w = 1}, hum)}
	g_fake.nodes = {node_group(5, {0, 0, -20}, quat_yaw(math.PI / 2), inner)}
	fake_step_with(&s)

	// The yaw turns the inner Group's +x to -z, and the hum's -z to -x.
	expect_speaker_pos(t, 1, {-2, 0, -21})
	mix_skip(TONE_FRAMES / 2)
	testing.expect(t, mix_peak(mix_read(MIX_FRAMES)) < 1e-4)

	g_fake.nodes = {node_group(5, {0, 0, -4}, {w = 1}, hum)}
	fake_step_with(&s)
	expect_speaker_pos(t, 1, {0, 0, -6})
	mix_skip(TONE_FRAMES / 2)
	testing.expect(t, mix_peak(mix_read(MIX_FRAMES)) > 0.1 * LOW_LEVEL)
}

@(test)
test_a_here_speaker_in_a_group_ignores_the_group :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.camera = camera_facing_forward()
	music := []Node{node_speaker(fake_speaker(1, low))}
	g_fake.nodes = {node_group(5, {0, 0, -100}, {w = 1}, music)}
	fake_step_with(&s)

	pairing := &g_fake.audio.speakers
	testing.expect_value(t, pairing.prev[pairing.prev_index[1]].speaker.at.tag, Place_Tag.Here)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_speaker_that_moves_to_another_group_keeps_its_voice :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	hum := []Node{node_speaker(fake_speaker(1, low, at = place_at({0, 0, 0}, 10)))}
	g_fake.nodes = {node_group(5, {x = 1}, {w = 1}, hum), node_group(6, {x = 3}, {w = 1}, nil)}
	fake_step_with(&s)
	voice, _ := fake_speaker_voice(1)
	taken := voice.taken

	g_fake.nodes = {node_group(5, {x = 1}, {w = 1}, nil), node_group(6, {x = 3}, {w = 1}, hum)}
	fake_step_with(&s)

	moved, ok := fake_speaker_voice(1)
	testing.expect(t, ok)
	testing.expect(t, moved == voice)
	testing.expect_value(t, moved.taken, taken)
	testing.expect_value(t, fake_voices_in_use(), 1)
	expect_speaker_pos(t, 1, {3, 0, 0})
}

@(test)
test_two_speakers_with_one_id_keep_the_first_in_walk_order :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id
	grouped := []Node{node_speaker(fake_speaker(1, low))}
	g_fake.nodes = {node_group(5, {}, {w = 1}, grouped), node_speaker(fake_speaker(1, high))}
	fake_step_with(&s)

	testing.expect_value(t, len(g_fake.audio.speakers.logged), 1)
	voice, _ := fake_speaker_voice(1)
	testing.expect_value(t, voice.sound_id, low)
}

@(test)
test_a_once_speaker_gives_its_voice_back_at_its_end_and_does_not_play_again :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id
	g_fake.speakers = {fake_speaker(1, low, repeat = .Once), fake_speaker(2, low), fake_speaker(3, high)}
	fake_step_with(&s)
	_, waiting := fake_speaker_voice(3)
	testing.expect(t, !waiting)

	// With no device, the host mixes in step time, so the Once still ends.
	audio_advance(&g_fake.audio, 2 * f32(TONE_FRAMES) / WAV_RATE)
	fake_step_with(&s)
	_, ok := fake_speaker_voice(1)
	testing.expect(t, !ok)
	voice, started := fake_speaker_voice(3)
	testing.expect(t, started)
	testing.expect_value(t, voice.sound_id, high)

	// It stays silent while its id stays, also as a Loop.
	g_fake.speakers = {fake_speaker(1, low, repeat = .Once)}
	fake_step_with(&s)
	mix_skip(MIX_FRAMES)
	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	_, ok = fake_speaker_voice(1)
	testing.expect(t, !ok)
	voices_reap(&g_fake.audio.voices)
	testing.expect_value(t, fake_voices_in_use(), 0)
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)

	// One step out of the Scene, and it plays again.
	g_fake.speakers = nil
	fake_step_with(&s)
	g_fake.speakers = {fake_speaker(1, low, repeat = .Once)}
	fake_step_with(&s)
	_, ok = fake_speaker_voice(1)
	testing.expect(t, ok)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_loop_changed_to_once_stops_at_the_end_of_the_current_pass :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	mix_skip(TONE_FRAMES / 2)

	g_fake.speakers = {fake_speaker(1, low, repeat = .Once)}
	fake_step_with(&s)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
	mix_skip(TONE_FRAMES / 2 + MIX_FRAMES)
	testing.expect_value(t, mix_peak(mix_read(MIX_FRAMES)), 0)

	fake_step_with(&s)
	_, ok := fake_speaker_voice(1)
	testing.expect(t, !ok)
	testing.expect_value(t, fake_voices_in_use(), 0)
}

@(test)
test_a_once_changed_to_loop_keeps_repeating :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.speakers = {fake_speaker(1, low, repeat = .Once)}
	fake_step_with(&s)
	voice, _ := fake_speaker_voice(1)
	taken := voice.taken
	mix_skip(TONE_FRAMES / 2)

	g_fake.speakers = {fake_speaker(1, low)}
	fake_step_with(&s)
	mix_skip(2 * TONE_FRAMES)
	fake_step_with(&s)

	looping, ok := fake_speaker_voice(1)
	testing.expect(t, ok)
	testing.expect_value(t, looping.taken, taken)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - LOW_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_changed_sound_id_plays_a_once_that_ended_again :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/high")})
	defer fake_seam_shutdown(&s)
	low, high := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id
	g_fake.speakers = {fake_speaker(1, low, repeat = .Once)}
	fake_step_with(&s)
	mix_skip(TONE_FRAMES + MIX_FRAMES)
	fake_step_with(&s)
	_, ok := fake_speaker_voice(1)
	testing.expect(t, !ok)

	g_fake.speakers = {fake_speaker(1, high, repeat = .Once)}
	fake_step_with(&s)
	voice, started := fake_speaker_voice(1)
	testing.expect(t, started)
	testing.expect_value(t, voice.sound_id, high)
	testing.expect(t, abs(mix_peak(mix_read(MIX_FRAMES)) - HIGH_LEVEL) < LEVEL_EPSILON)
}

@(test)
test_a_speaker_in_a_group_that_moves_across_the_listener_pans_with_it :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low")})
	defer fake_seam_shutdown(&s)
	low := g_fake.loaded_manifest[0].id
	g_fake.camera = camera_facing_forward()
	hum := []Node{node_speaker(fake_speaker(1, low, at = place_at({0, 0, -1}, 20)))}

	g_fake.nodes = {node_group(5, {-3, 0, 0}, {w = 1}, hum)}
	fake_step_with(&s)
	mix_skip(MIX_FRAMES)
	mixed := mix_read(MIX_FRAMES)
	testing.expect(t, channel_peak(mixed, 0) > 2 * channel_peak(mixed, 1))

	g_fake.nodes = {node_group(5, {3, 0, 0}, {w = 1}, hum)}
	fake_step_with(&s)
	mix_skip(MIX_FRAMES)
	mixed = mix_read(MIX_FRAMES)
	testing.expect(t, channel_peak(mixed, 1) > 2 * channel_peak(mixed, 0))
}

@(test)
test_a_once_whose_ended_voice_a_play_took_does_not_play_again :: proc(t: ^testing.T) {
	dir := play_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/low", "sound/blip")})
	defer fake_seam_shutdown(&s)
	low, blip := g_fake.loaded_manifest[0].id, g_fake.loaded_manifest[1].id
	g_fake.speakers = {fake_speaker(1, low, repeat = .Once), fake_speaker(2, low)}
	fake_step_with(&s)
	mix_skip(TONE_FRAMES + MIX_FRAMES)

	// The Play runs before the pairing and reaps the Once's voice.
	fake_step_with(&s, fake_play(blip, 1, 1, place_here()))
	testing.expect_value(t, g_fake.audio.voices.voices[0].use, Voice_Use.Play)
	mix_skip(MIX_FRAMES)
	fake_step_with(&s)
	_, ok := fake_speaker_voice(1)
	testing.expect(t, !ok)
}
