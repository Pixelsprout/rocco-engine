#+test
package engine

import sapp "../sokol-odin/sokol/app"
import "core:strconv"
import "core:strings"
import "core:testing"

KEY_MODULE :: #load("../platform/Key.roc", string)

@(test)
test_key_tag_matches_the_keys_roc_rule :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := [][2]string{{"W", "W"}, {"SPACE", "Space"}, {"LEFT_SHIFT", "LeftShift"}, {"_0", "Num0"}, {"KP_0", "Kp0"}, {"WORLD_1", "World1"}, {"F1", "F1"}}
	for c in cases {
		testing.expect_value(t, key_tag(c[0]), c[1])
	}
}

// Reads each "Tag => code" line of the generated platform/Key.roc, so a
// change to the rule on either side fails here.
@(test)
test_key_from_tag_finds_every_key_in_key_roc :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	found := 0
	rest := KEY_MODULE
	for line in strings.split_lines_iterator(&rest) {
		tag, _, code_text := strings.partition(strings.trim_space(line), " => ")
		code, is_code := strconv.parse_int(code_text, 10)
		if !is_code {
			continue
		}
		key, ok := key_from_tag(tag)
		testing.expectf(t, ok, "no Keycode has the tag %q", tag)
		testing.expect_value(t, int(key), code)
		found += 1
	}
	testing.expect_value(t, found, len(sapp.Keycode) - 1)
}

@(test)
test_key_from_tag_rejects_an_unknown_name :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for tag in ([]string{"Jump", "w", "SPACE", "Invalid", ""}) {
		_, ok := key_from_tag(tag)
		testing.expectf(t, !ok, "expected %q to be unknown", tag)
	}
}
