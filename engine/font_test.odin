package engine

import "core:testing"

@(test)
test_font_measure_one_glyph_at_the_bake_size :: proc(t: ^testing.T) {
	testing.expect_value(t, font_measure("A", FONT_BAKE_SIZE), [2]f32{16.154839, 32})
}

@(test)
test_font_measure_scales_with_size :: proc(t: ^testing.T) {
	testing.expect_value(t, font_measure("A", 16), [2]f32{16.154839 / 2, 16})
}

@(test)
test_font_measure_applies_kerning :: proc(t: ^testing.T) {
	a, b, v, kern: f32 = 16.154839, 15.974194, 15.2, -1.7290323
	testing.expect_value(t, font_measure("AV", FONT_BAKE_SIZE).x, a + kern + v)
	testing.expect_value(t, font_measure("AB", FONT_BAKE_SIZE).x, a + b)
}

@(test)
test_font_measure_empty_string_is_one_line_high :: proc(t: ^testing.T) {
	testing.expect_value(t, font_measure("", FONT_BAKE_SIZE), [2]f32{0, 32})
}

@(test)
test_font_measure_outside_ascii_reads_as_question_mark :: proc(t: ^testing.T) {
	question := font_measure("?", FONT_BAKE_SIZE)
	testing.expect_value(t, font_measure("é", FONT_BAKE_SIZE), question)
	testing.expect_value(t, font_measure("\t", FONT_BAKE_SIZE), question)
	testing.expect_value(t, font_measure("\x7f", FONT_BAKE_SIZE), question)
	testing.expect_value(t, font_measure("A€", FONT_BAKE_SIZE), font_measure("A?", FONT_BAKE_SIZE))
}
