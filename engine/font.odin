package engine

import "core:slice"
import "core:unicode/utf8"

// Metrics are in pixels at FONT_BAKE_SIZE. bearing is the offset from the pen on the
// baseline to the top left of the glyph's atlas rect, which includes the SDF padding.
// rect is x, y, width, height in atlas pixels.
Font_Glyph :: struct {
	advance: f32,
	bearing: [2]i16,
	rect:    [4]u16,
}

// pair holds the first character in the high byte and the second in the low byte.
Font_Kern :: struct {
	pair:    u16,
	advance: f32,
}

// Walks one line of text glyph by glyph with font_pen_next.
Font_Pen :: struct {
	text:   string,
	offset: int,
	x:      f32,
	prev:   rune,
}

// One line only: the caller splits lines and words.
font_measure :: proc(text: string, size: f32) -> [2]f32 {
	pen := Font_Pen{text = text}
	for _ in font_pen_next(&pen) {
	}
	scale := size / FONT_BAKE_SIZE
	return {pen.x * scale, FONT_LINE_HEIGHT * scale}
}

// Clay measures with font_measure and the host draws with the same walk, so text fills its box exactly.
// x is the pen before the glyph, in pixels at FONT_BAKE_SIZE. replaced is true when the glyph stands in as '?'.
font_pen_next :: proc(pen: ^Font_Pen) -> (glyph: Font_Glyph, x: f32, replaced: bool, ok: bool) {
	if pen.offset >= len(pen.text) {
		return
	}
	r, n := utf8.decode_rune_in_string(pen.text[pen.offset:])
	c := font_char(r)
	if pen.offset > 0 {
		pen.x += font_kern(pen.prev, c)
	}
	pen.offset += n
	glyph = FONT_GLYPHS[c - FONT_FIRST]
	x = pen.x
	pen.x += glyph.advance
	pen.prev = c
	return glyph, x, c != r, true
}

font_char :: proc(r: rune) -> rune {
	return r if FONT_FIRST <= r && r <= FONT_LAST else '?'
}

font_kern :: proc(first, second: rune) -> f32 {
	key := u16(first) << 8 | u16(second)
	i, found := slice.binary_search_by(FONT_KERNING[:], key, proc(k: Font_Kern, key: u16) -> slice.Ordering {
		return slice.cmp(k.pair, key)
	})
	return FONT_KERNING[i].advance if found else 0
}
