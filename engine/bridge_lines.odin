package engine

import "core:bytes"
import "core:encoding/json"
import "core:mem"
import "core:strings"

// A longer request gets an error reply, so a Driver bug cannot fill memory.
BRIDGE_MAX_LINE :: 1 * mem.Megabyte
BRIDGE_READ_SIZE :: 16 * mem.Kilobyte

// What the transport does after a handler returns. Hold sends no reply and
// reads no request until bridge_transport_send_held sends the reply.
Bridge_Next :: enum {
	Read,
	Stop,
	Hold,
}

Json_Line_Status :: enum {
	None,
	Line,
	Too_Long,
}

// Splits the bytes from the socket into lines. A line is valid until the
// next push.
Json_Lines :: struct {
	buf:      [dynamic]u8,
	start:    int,
	too_long: bool,
}

// Answers one request line. The transport knows no op. It frees the
// context.temp_allocator after each request, and sends reply with a newline.
Bridge_Handler :: #type proc(ctx: rawptr, line: string, reply: ^strings.Builder) -> Bridge_Next

json_lines_init :: proc(f: ^Json_Lines, allocator: mem.Allocator) {
	f.buf = make([dynamic]u8, allocator)
}

json_lines_destroy :: proc(f: ^Json_Lines) {
	delete(f.buf)
}

json_lines_push :: proc(f: ^Json_Lines, data: []u8) {
	remove_range(&f.buf, 0, f.start)
	f.start = 0
	append(&f.buf, ..data)
}

// A blank line is skipped. A trailing carriage return is dropped, so a
// Driver on Windows can send CRLF.
json_lines_next :: proc(f: ^Json_Lines) -> (line: string, status: Json_Line_Status) {
	for {
		end := bytes.index_byte(f.buf[f.start:], '\n')
		if end < 0 {
			if len(f.buf) - f.start > BRIDGE_MAX_LINE {
				f.too_long = true
				clear(&f.buf)
				f.start = 0
			}
			return "", .None
		}
		line = string(f.buf[f.start:][:end])
		f.start += end + 1
		if f.too_long {
			f.too_long = false
			return "", .Too_Long
		}
		line = strings.trim_suffix(line, "\r")
		if strings.trim_space(line) != "" {
			return line, .Line
		}
	}
}

// Every reply is one object with ok. A failed one also has error.
bridge_reply_error :: proc(reply: ^strings.Builder, message: string) {
	strings.builder_reset(reply)
	strings.write_string(reply, `{"ok":false`)
	bridge_reply_field(reply, "error", message)
	strings.write_byte(reply, '}')
}

// Writes ,"key":value. value is any type that json.marshal takes.
bridge_reply_field :: proc(reply: ^strings.Builder, key: string, value: any) {
	strings.write_byte(reply, ',')
	_ = json.marshal_to_builder(reply, key, {})
	strings.write_byte(reply, ':')
	_ = json.marshal_to_builder(reply, value, {})
}

