package engine

import "core:encoding/json"
import "core:strings"

// Writes Vocabulary values as JSON for the Bridge, with the Vocabulary's tag
// and field names. A tag with a payload is an object with one key, such as
// {"Unload":"pip"}. A tag with no payload is a string, such as "Quit".

json_write_string :: proc(b: ^strings.Builder, s: string) {
	_ = json.marshal_to_builder(b, s, &{})
}

json_write_roc_str :: proc(b: ^strings.Builder, s: ^Roc_Str) {
	json_write_string(b, roc_str_string(s))
}

json_write_command :: proc(b: ^strings.Builder, command: ^Command) {
	switch command.tag {
	case .Quit:
		strings.write_string(b, `"Quit"`)
	case .Load:
		load := &command.payload.load
		strings.write_string(b, `{"Load":{"pack":`)
		json_write_roc_str(b, &load.pack)
		strings.write_string(b, `,"assets":[`)
		for &asset, i in load.assets.elements[:load.assets.length] {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			json_write_roc_str(b, &asset)
		}
		strings.write_string(b, `]}}`)
	case .Unload:
		strings.write_string(b, `{"Unload":`)
		json_write_roc_str(b, &command.payload.unload)
		strings.write_byte(b, '}')
	}
}

// b holds the elements of a JSON array with no brackets, so the Commands of
// many steps join into one array.
json_write_commands :: proc(b: ^strings.Builder, commands: Roc_List(Command)) {
	for &command in commands.elements[:commands.length] {
		if strings.builder_len(b^) > 0 {
			strings.write_byte(b, ',')
		}
		json_write_command(b, &command)
	}
}
