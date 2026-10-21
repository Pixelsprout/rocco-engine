package engine

import sapp "../sokol-odin/sokol/app"

// One row of KEY_TAGS, which the keys build step writes from the same
// Keycode table as platform/Key.roc.
Key_Tag :: struct {
	tag:  string,
	code: u16,
}

key_from_tag :: proc(tag: string) -> (key: sapp.Keycode, ok: bool) {
	for row in KEY_TAGS {
		if row.tag == tag {
			return sapp.Keycode(row.code), true
		}
	}
	return .INVALID, false
}
