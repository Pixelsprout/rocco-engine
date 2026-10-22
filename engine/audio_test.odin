#+test
package engine

import "core:testing"

@(test)
test_audio_without_a_device_opens_none :: proc(t: ^testing.T) {
	audio: Audio
	audio_init(&audio, device = false)
	defer audio_shutdown(&audio)
	testing.expect(t, audio.engine_ready)
	testing.expect(t, ma_engine_get_device(&audio.engine) == nil)
}

@(test)
test_audio_shutdown_uninits_once :: proc(t: ^testing.T) {
	audio: Audio
	audio_init(&audio, device = false)
	audio_shutdown(&audio)
	testing.expect(t, !audio.engine_ready)
	audio_shutdown(&audio)
}

// A wrong offset in Ma_Engine_Config shows here as a wrong default.
@(test)
test_ma_engine_config_matches_miniaudio_defaults :: proc(t: ^testing.T) {
	config := ma_engine_config_init()
	testing.expect_value(t, config.listener_count, 1)
	testing.expect_value(t, config.no_device, false)
	testing.expect_value(t, config.resource_manager_resampling.format, 0)
	testing.expect_value(t, config.pitch_resampling.format, MA_FORMAT_F32)
	testing.expect_value(t, config.pitch_resampling.linear_lpf_order, 0)
}
