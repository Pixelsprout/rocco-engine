#+test
package engine

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_json_write_commands_uses_the_vocabulary_tags :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	commands := []Command{{tag = .Quit}, fake_load("room", "a", "b\"c"), fake_unload("room")}
	list := roc_list_from_slice(commands)
	defer roc_list_decref(list)
	b := strings.builder_make(context.temp_allocator)

	json_write_commands(&b, list)

	got := strings.to_string(b)
	testing.expect_value(t, got, `"Quit",{"Load":{"pack":"room","assets":["a","b\"c"]}},{"Unload":"room"}`)
	_, err := json.parse_string(strings.concatenate({"[", got, "]"}, context.temp_allocator), allocator = context.temp_allocator)
	testing.expect_value(t, err, nil)
}

// The second call goes on with a comma, so the steps of a request join.
@(test)
test_json_write_commands_joins_a_second_list :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	first := roc_list_from_slice([]Command{{tag = .Quit}})
	defer roc_list_decref(first)
	empty := roc_list_from_slice([]Command{})
	defer roc_list_decref(empty)

	json_write_commands(&b, first)
	json_write_commands(&b, empty)
	json_write_commands(&b, first)

	testing.expect_value(t, strings.to_string(b), `"Quit","Quit"`)
}
