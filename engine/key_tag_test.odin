#+test
package engine

import sapp "../sokol-odin/sokol/app"
import "core:testing"

@(test)
test_key_from_tag_finds_the_keys_of_key_roc :: proc(t: ^testing.T) {
	cases := []struct {
		tag: string,
		key: sapp.Keycode,
	}{{"W", .W}, {"Space", .SPACE}, {"LeftShift", .LEFT_SHIFT}, {"Num0", ._0}, {"Kp0", .KP_0}, {"World1", .WORLD_1}, {"F1", .F1}, {"Escape", .ESCAPE}}
	for c in cases {
		key, ok := key_from_tag(c.tag)
		testing.expectf(t, ok, "no Keycode has the tag %q", c.tag)
		testing.expect_value(t, key, c.key)
	}
}

// INVALID has no tag, as in platform/Key.roc.
@(test)
test_key_tags_has_every_keycode_but_invalid :: proc(t: ^testing.T) {
	testing.expect_value(t, len(KEY_TAGS), len(sapp.Keycode) - 1)
}

@(test)
test_key_from_tag_rejects_an_unknown_name :: proc(t: ^testing.T) {
	for tag in ([]string{"Jump", "w", "SPACE", "Invalid", ""}) {
		_, ok := key_from_tag(tag)
		testing.expectf(t, !ok, "expected %q to be unknown", tag)
	}
}
