package web_pong

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"

STEP_COUNT :: 600
DT :: f32(1.0 / 60.0)
SEED :: u64(7)
KEY_SPACE :: u16(32)
KEY_S :: u16(83)
KEY_W :: u16(87)
KEY_DOWN :: u16(264)
KEY_UP :: u16(265)
DUMP_BYTES :: 1 << 20

// Held keys move both paddles. Each Space press pauses or resumes the game.
SCRIPT := []Script_Row {
	{from = 1, to = 90, held = {KEY_W, KEY_DOWN}},
	{from = 91, to = 180, held = {KEY_S, KEY_UP}},
	{from = 200, to = 200, pressed = {KEY_SPACE}},
	{from = 230, to = 230, pressed = {KEY_SPACE}},
	{from = 300, to = 420, held = {KEY_W}},
	{from = 560, to = 560, pressed = {KEY_SPACE}},
}

Script_Row :: struct {
	from, to: int,
	held:     []u16,
	pressed:  []u16,
}

Emit :: #type proc(line: string)

g_dump_buffer: [DUMP_BYTES]u8

// Runs pong for STEP_COUNT steps. Each step emits a digest line for its
// commands and one for its Scene, so a line differs when any value that Roc
// returned differs.
run_pong :: proc(emit: Emit) {
	emit(fmt.tprintf("pointer bytes %d", size_of(uintptr)))
	config := Roc_Init_Arg0 {
		seed = SEED,
	}
	launch := roc_launch(config)
	emit_dump(emit, "launch", launch)

	started := roc_init(config)
	emit_dump(emit, "init", started.commands)
	roc_list_decref(started.commands)
	model := started.model

	for step in 1 ..= STEP_COUNT {
		stepped := roc_step(model, script_input(step), {}, DT)
		model = stepped.model
		emit_dump(emit, fmt.tprintf("step %d commands", step), stepped.commands)
		roc_list_decref(stepped.commands)

		// view consumes one reference, so give it one and keep ours.
		roc_incref_box(model)
		scene := roc_view(model)
		emit_dump(emit, fmt.tprintf("step %d scene", step), scene)
		if step == STEP_COUNT {
			emit(fmt.tprintf("final scene %s", dump_text(scene)))
		}
		roc_decref(scene)
		free_all(context.temp_allocator)
	}
	roc_drop_model(model)
	emit("done")
}

script_input :: proc(step: int) -> Roc_Step_Arg1 {
	input := Roc_Step_Arg1 {
		window = {width = 1280, height = 720},
	}
	for row in SCRIPT {
		if step >= row.from && step <= row.to {
			input.held = roc_list_from_slice(row.held)
			input.pressed = roc_list_from_slice(row.pressed)
		}
	}
	return input
}

emit_dump :: proc(emit: Emit, label: string, value: any) {
	text := dump_text(value)
	emit(fmt.tprintf("%s bytes=%d fnv=%016x", label, len(text), fnv1a(text)))
}

dump_text :: proc(value: any) -> string {
	b := strings.builder_from_bytes(g_dump_buffer[:])
	dump(&b, value)
	if strings.builder_len(b) == DUMP_BYTES {
		panic("the dump buffer is full")
	}
	return strings.to_string(b)
}

fnv1a :: proc(text: string) -> u64 {
	hash := u64(0xcbf29ce484222325)
	for c in transmute([]u8)text {
		hash = (hash ~ u64(c)) * 0x100000001b3
	}
	return hash
}

// Writes a value from its type info. A Roc_Str becomes its text, a Roc_List
// its elements, and a tag union struct the live tag with its payload. The
// output has no addresses, so it is the same at each pointer width.
dump :: proc(b: ^strings.Builder, value: any) {
	base := reflect.type_info_base(type_info_of(value.id))
	#partial switch info in base.variant {
	case runtime.Type_Info_Struct:
		if value.id == Roc_Str {
			fmt.sbprintf(b, "%q", roc_str_text((^Roc_Str)(value.data)))
		} else if field_names_are(value.id, {"elements", "length", "capacity_or_alloc_ptr"}) {
			dump_list(b, value)
		} else if first_field_is(value.id, "payload") {
			dump_union(b, value)
		} else {
			dump_struct(b, value)
		}
	case runtime.Type_Info_Float:
		switch v in value {
		case f32:
			fmt.sbprintf(b, "%v(%08x)", v, transmute(u32)v)
		case f64:
			fmt.sbprintf(b, "%v(%016x)", v, transmute(u64)v)
		}
	case runtime.Type_Info_Enum:
		name, _ := reflect.enum_name_from_value_any(value)
		strings.write_string(b, name)
	case runtime.Type_Info_Pointer:
		strings.write_string(b, "box")
	case runtime.Type_Info_Integer, runtime.Type_Info_Boolean:
		fmt.sbprintf(b, "%v", value)
	case runtime.Type_Info_Array:
		strings.write_byte(b, '[')
		for i in 0 ..< info.count {
			data := rawptr(uintptr(value.data) + uintptr(i * info.elem_size))
			dump(b, any{data, info.elem.id})
			strings.write_byte(b, ' ')
		}
		strings.write_byte(b, ']')
	case:
		fmt.sbprintf(b, "<%v>", value.id)
	}
}

dump_struct :: proc(b: ^strings.Builder, value: any) {
	strings.write_byte(b, '{')
	for i in 0 ..< reflect.struct_field_count(value.id) {
		field := reflect.struct_field_at(value.id, i)
		fmt.sbprintf(b, "%s=", field.name)
		dump(b, any{rawptr(uintptr(value.data) + field.offset), field.type.id})
		strings.write_byte(b, ' ')
	}
	strings.write_byte(b, '}')
}

dump_list :: proc(b: ^strings.Builder, value: any) {
	elements_field := reflect.struct_field_by_name(value.id, "elements")
	elem := elements_field.type.variant.(runtime.Type_Info_Multi_Pointer).elem
	elements := (^[^]u8)(value.data)^
	length := reflect.struct_field_value_by_name(value, "length").(uint)
	strings.write_byte(b, '[')
	for i in 0 ..< int(length) {
		dump(b, any{&elements[i * elem.size], elem.id})
		strings.write_string(b, ", ")
	}
	strings.write_byte(b, ']')
}

// The payload field of a tag is the tag name in snake case, with an
// underscore after an Odin keyword. A tag with no payload has no field.
dump_union :: proc(b: ^strings.Builder, value: any) {
	tag := reflect.struct_field_value_by_name(value, "tag", true)
	tag_name, _ := reflect.enum_name_from_value_any(tag)
	strings.write_string(b, tag_name)
	payload := reflect.struct_field_value_by_name(value, "payload", true)
	for i in 0 ..< reflect.struct_field_count(payload.id) {
		field := reflect.struct_field_at(payload.id, i)
		if same_ident(field.name, tag_name) {
			strings.write_byte(b, '(')
			dump(b, any{payload.data, field.type.id})
			strings.write_byte(b, ')')
		}
	}
}

// Compares two names with case and underscores ignored, so "end_game" and
// "EndGame" match.
same_ident :: proc(a, b: string) -> bool {
	i, j := 0, 0
	for {
		for i < len(a) && a[i] == '_' {
			i += 1
		}
		for j < len(b) && b[j] == '_' {
			j += 1
		}
		if i == len(a) || j == len(b) {
			return i == len(a) && j == len(b)
		}
		if ascii_lower(a[i]) != ascii_lower(b[j]) {
			return false
		}
		i += 1
		j += 1
	}
}

ascii_lower :: proc(c: u8) -> u8 {
	return c + 32 if c >= 'A' && c <= 'Z' else c
}

field_names_are :: proc(id: typeid, want: []string) -> bool {
	names := reflect.struct_field_names(id)
	if len(names) != len(want) {
		return false
	}
	for name, i in names {
		if name != want[i] {
			return false
		}
	}
	return true
}

first_field_is :: proc(id: typeid, name: string) -> bool {
	names := reflect.struct_field_names(id)
	return len(names) > 0 && names[0] == name
}

roc_str_text :: proc(s: ^Roc_Str) -> string {
	if int(s.length) < 0 {
		raw := ([^]u8)(s)
		return string(raw[:raw[size_of(Roc_Str) - 1] & 0x7f])
	}
	return string(s.bytes[:s.length])
}
