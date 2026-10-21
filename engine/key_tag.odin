package engine

import sapp "../sokol-odin/sokol/app"
import "core:reflect"
import "core:strings"

// The tag that scripts/Keys.roc gives a sokol Keycode name in
// platform/Key.roc. Both read the same enum, so the names cannot drift.
// LEFT_SHIFT becomes LeftShift, and _0 becomes Num0.
key_tag :: proc(name: string, allocator := context.temp_allocator) -> string {
	if strings.has_prefix(name, "_") {
		return strings.concatenate({"Num", name[1:]}, allocator)
	}
	b := strings.builder_make(allocator)
	rest := name
	for word in strings.split_iterator(&rest, "_") {
		if word == "" {
			continue
		}
		strings.write_byte(&b, word[0])
		strings.write_string(&b, strings.to_lower(word[1:], context.temp_allocator))
	}
	return strings.to_string(b)
}

// INVALID has no tag, as in platform/Key.roc.
key_from_tag :: proc(tag: string) -> (key: sapp.Keycode, ok: bool) {
	for field in reflect.enum_fields_zipped(sapp.Keycode) {
		if field.name != "INVALID" && key_tag(field.name) == tag {
			return sapp.Keycode(field.value), true
		}
	}
	return .INVALID, false
}
