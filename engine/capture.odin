package engine

import "core:fmt"
import "core:io"
import "core:mem"
import "core:strings"
import "system"

CAPTURE_ENV :: "ROCCO_CAPTURE_CSV"
CAPTURE_LABELS_ENV :: "ROCCO_CAPTURE_LABELS"
CAPTURE_DEBUG_CAMERA_ENV :: "ROCCO_CAPTURE_DEBUG_CAMERA"
CAPTURE_PASSES :: 64
CAPTURE_LABEL_BYTES :: 128
CAPTURE_COMMANDS :: 256
CAPTURE_COMMAND_BYTES :: 4096
CAPTURE_MAX_FRAMES :: 30_000
CAPTURE_SOURCE_BEGIN :: u64(100)
CAPTURE_SOURCE_END :: u64(11_436)
CAPTURE_FIELD_BEGIN :: u64(100_000)
CAPTURE_FIELD_END :: u64(122_000)
CAPTURE_SUPPLEMENT_BEGIN :: u64(200_000)
CAPTURE_SUPPLEMENT_END :: u64(200_160)

Capture_Draw_Kind :: enum { Source, Field, Supplement, Other }
Capture_Contents :: struct { source_draws, field_draws, supplement_draws, other_draws: int, selected: [dynamic]u64 }
Capture_Frame :: struct {
	frame: int,
	before, after, prev: u64,
	steps: int,
	alpha: f32,
	window: Ui_Window,
	camera: Camera_Pose,
	start, commit_start, commit_end: i64,
	begin_pass, drawable: i64,
	delta: f64,
	pass_count: int,
}
Capture_Command :: struct {
	frame: int,
	step: u64,
	length: int,
	bytes: [CAPTURE_COMMAND_BYTES]u8,
}
Capture_Sink :: struct {
	on: bool,
	path: string,
	frequency: i64,
	seed: u64,
	rows: [dynamic]Capture_Frame,
	commands: []Capture_Command,
	command_count: int,
	buffer: [CAPTURE_COMMAND_BYTES]u8,
	builder: strings.Builder,
	failed: string,
	row: Capture_Frame,
	label_passes: bool,
	labels: [CAPTURE_PASSES][CAPTURE_LABEL_BYTES]u8,
}

capture_problem :: proc(path: string, frames: int, mode: Run_Mode, bridge, debug_camera, debug_diagnostic: bool) -> string {
	if path == "" { return "debug-camera capture requires a capture path" if debug_diagnostic else "" }
	if !system.is_absolute_path(path) { return "capture path must be absolute" }
	if frames <= 0 || frames > CAPTURE_MAX_FRAMES { return "capture requires a frame limit from 1 through 30000" }
	if mode != .Real_Clock || bridge { return "capture requires Real_Clock without Bridge" }
	if debug_camera && !debug_diagnostic { return "debug camera capture requires ROCCO_CAPTURE_DEBUG_CAMERA=1" }
	if debug_diagnostic && !debug_camera { return "ROCCO_CAPTURE_DEBUG_CAMERA=1 requires ROCCO_DEBUG_CAMERA=1" }
	for suffix in ([]string{"", ".commands.jsonl", ".meta.json"}) {
		file, err := system.open(fmt.tprintf("%s%s", path, suffix), {.Read})
		if err == nil {
			_ = system.close(file)
			return "capture output already exists"
		}
		if err != .Not_Exist { return "capture output path is unavailable" }
	}
	return ""
}

capture_sink_init :: proc(c: ^Capture_Sink, path: string, frames: int, allocator: mem.Allocator) {
	if path == "" { return }
	c.on = true
	c.path = strings.clone(path, allocator)
	c.frequency = capture_frequency()
	c.rows = make([dynamic]Capture_Frame, 0, frames, allocator)
	c.commands = make([]Capture_Command, CAPTURE_COMMANDS, allocator)
	c.builder = strings.builder_from_bytes(c.buffer[:])
	c.builder.buf.allocator = {procedure = capture_overflow_allocator, data = c}
}

capture_overflow_allocator :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, location := #caller_location) -> ([]byte, mem.Allocator_Error) {
	if mode == .Alloc || mode == .Resize || mode == .Alloc_Non_Zeroed || mode == .Resize_Non_Zeroed {
		(^Capture_Sink)(data).failed = "command buffer overflow"
	}
	return nil, .Out_Of_Memory
}

capture_frame_begin :: proc(c: ^Capture_Sink, frame: int, before: u64, delta: f64, window: Ui_Window, started: i64 = 0) {
	c.row = {frame = frame, before = before, delta = delta, window = window, start = started if started != 0 else capture_tick()}
}

capture_step_end :: proc(c: ^Capture_Sink, step: u64) {
	text := strings.to_string(c.builder)
	if len(text) == 0 { return }
	if c.command_count == len(c.commands) { c.failed = "command record overflow" } else {
		row := &c.commands[c.command_count]
		row.frame, row.step, row.length = c.row.frame, step, len(text)
		copy(row.bytes[:], text)
		c.command_count += 1
	}
	strings.builder_reset(&c.builder)
}

capture_frame_end :: proc(c: ^Capture_Sink, after: u64, steps: int, alpha: f32, camera: Camera_Pose, has_prev: bool) {
	c.row.after, c.row.steps, c.row.alpha, c.row.camera = after, steps, alpha, camera
	c.row.prev = after - 1 if has_prev && after > 0 else after
	if len(c.rows) == cap(c.rows) { c.failed = "frame overflow"; return }
	append(&c.rows, c.row)
}

capture_write_new :: proc(path, data: string) -> system.Error {
	file, err := system.open(path, {.Write, .Create, .Excl})
	if err != nil { return err }
	n, write_err := system.write(file, transmute([]u8)data)
	close_err := system.close(file)
	if write_err != nil { return write_err }
	if n != len(data) { return system.Error(io.Error.Short_Write) }
	return close_err
}

capture_sink_write :: proc(c: ^Capture_Sink, s: ^State) -> system.Error {
	if !c.on { return nil }
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "frame,steps,step_before,step_after,prev_step,alpha,width,height,dpi,start_tick,commit_start_tick,commit_end_tick,delta_seconds,applied_seconds,clamped_seconds,eye_x,eye_y,eye_z,target_x,target_y,target_z,fov_y,pass_count,begin_pass_ticks,drawable_ticks\n")
	for r in c.rows {
		e, target := r.camera.eye, r.camera.target
		fmt.sbprintf(&b, "%v,%v,%v,%v,%v,%.9f,%v,%v,%v,%v,%v,%v,%.9f,%.9f,%.9f,%v,%v,%v,%v,%v,%v,%v,%v,%v,%v\n", r.frame, r.steps, r.before, r.after, r.prev, r.alpha, r.window.size.x, r.window.size.y, r.window.dpi, r.start, r.commit_start, r.commit_end, r.delta, min(r.delta, MAX_FRAME_TIME), max(0, r.delta-MAX_FRAME_TIME), e.x, e.y, e.z, target.x, target.y, target.z, r.camera.fov_y, r.pass_count, r.begin_pass, r.drawable)
	}
	if err := capture_write_new(c.path, strings.to_string(b)); err != nil { return err }
	strings.builder_reset(&b)
	for &r in c.commands[:c.command_count] {
		strings.write_byte(&b, '{')
		fmt.sbprintf(&b, `"frame":%v,"step":%v,"commands":[%v]`, r.frame, r.step, string(r.bytes[:r.length]))
		strings.write_string(&b, "}\n")
	}
	if err := capture_write_new(fmt.tprintf("%s.commands.jsonl", c.path), strings.to_string(b)); err != nil { return err }
	strings.builder_reset(&b)
	strings.write_byte(&b, '{')
	fmt.sbprintf(&b, `"version":1,"frequency_hz":%v,"clock":"%v","mode":"%v","spans":%v,"d3d_timestamps":%v,"debug_camera":%v,"step_hz":%v,"frame_limit":%v,"frames":%v,"command_records":%v,"msaa":%v,"shadow_map":%v,"shadow_cascades":%v,"pass_labels":%v,"seed":%v,"error":`, c.frequency, capture_clock_name(), s.mode, SPANS, GPU_TIMING, s.use_debug_camera, s.launch.step_hz, s.exit_after_frames, len(c.rows), c.command_count, msaa_sample_count(s.launch.window.samples), s.launch.shadow_map, s.launch.shadow_cascades, c.label_passes, c.seed)
	json_write_string(&b, c.failed)
	strings.write_string(&b, `,"shadow":`)
	json_write_shadow(&b, &s.seam.curr.shadow)
	strings.write_string(&b, `,"environment":`)
	json_write_environment(&b, &s.seam.curr.environment)
	contents: Capture_Contents
	contents.selected = make([dynamic]u64, context.temp_allocator)
	capture_contents(&contents, s.seam.curr.nodes)
	fmt.sbprintf(&b, `,"source_draws":%v,"field_draws":%v,"supplement_draws":%v,"other_draws":%v,"post_count":%v,"emitter_count":%v,"selected_groups":[`, contents.source_draws, contents.field_draws, contents.supplement_draws, contents.other_draws, s.seam.curr.post.length, s.seam.curr.emitters.length)
	for id, i in contents.selected {
		if i > 0 { strings.write_byte(&b, ',') }
		strings.write_u64(&b, id)
	}
	strings.write_string(&b, "]}\n")
	return capture_write_new(fmt.tprintf("%s.meta.json", c.path), strings.to_string(b))
}

capture_sink_destroy :: proc(c: ^Capture_Sink) {
	if !c.on { return }
	allocator := c.rows.allocator
	delete(c.path, allocator)
	delete(c.commands, allocator)
	delete(c.rows)
	c^ = {}
}

capture_contents :: proc(contents: ^Capture_Contents, nodes: Roc_List(Node)) {
	for &node in nodes.elements[:nodes.length] {
		if node.tag == .Group {
			group := &node.payload.group
			if group._0.selected { append(&contents.selected, group._0.id) }
			capture_contents(contents, group._1)
		} else if node.tag == .Attach {
			capture_contents(contents, node.payload.attach._1)
		} else if node.tag == .Draw {
			capture_count_draw(contents, node.payload.draw.id)
		}
	}
}

capture_draw_kind :: proc(id: u64) -> Capture_Draw_Kind {
	if id >= CAPTURE_SOURCE_BEGIN && id < CAPTURE_SOURCE_END { return .Source }
	if id >= CAPTURE_FIELD_BEGIN && id < CAPTURE_FIELD_END { return .Field }
	if id >= CAPTURE_SUPPLEMENT_BEGIN && id < CAPTURE_SUPPLEMENT_END { return .Supplement }
	return .Other
}

capture_count_draw :: proc(contents: ^Capture_Contents, id: u64) {
	switch capture_draw_kind(id) {
	case .Source: contents.source_draws += 1
	case .Field: contents.field_draws += 1
	case .Supplement: contents.supplement_draws += 1
	case .Other: contents.other_draws += 1
	}
}

capture_pass_label :: proc(c: ^Capture_Sink, original: cstring) -> cstring {
	index := c.row.pass_count
	c.row.pass_count += 1
	if !c.label_passes { return original }
	if index >= CAPTURE_PASSES { c.failed = "pass label overflow"; return original }
	label := fmt.bprintf(c.labels[index][:CAPTURE_LABEL_BYTES-1], "rocco.frame=%v.pass=%v.kind=%v", c.row.frame, index, string(original))
	c.labels[index][len(label)] = 0
	return cstring(&c.labels[index][0])
}
