package engine

import "core:slice"

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

// One line only: the caller splits lines and words.
font_measure :: proc(text: string, size: f32) -> [2]f32 {
	width: f32
	prev: rune
	for r, i in text {
		c := font_char(r)
		if i > 0 {
			width += font_kern(prev, c)
		}
		width += FONT_GLYPHS[c - FONT_FIRST].advance
		prev = c
	}
	scale := size / FONT_BAKE_SIZE
	return {width * scale, FONT_LINE_HEIGHT * scale}
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
