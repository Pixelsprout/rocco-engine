package web_host

import "base:runtime"

// The "env.o" name makes the wasm import module "env". The final link
// resolves these against the emscripten libc that the prebuilt host carries.
foreign import env "env.o"

STEP_COUNT :: 5

// Roc lays out a Str as three 32-bit words on wasm32. A negative length
// marks a small string, stored inside the struct itself.
Roc_Str :: struct {
	bytes:    [^]u8,
	capacity: int,
	length:   int,
}

// Roc sorts record fields by alignment, then by name.
Roc_Step :: struct {
	line:  Roc_Str,
	model: rawptr,
}

#assert(size_of(Roc_Str) == 12)
#assert(size_of(Roc_Step) == 16)

C_File :: struct {}

Main_Loop_Proc :: #type proc "c" ()

g_model: rawptr
g_step: u64

@(default_calling_convention = "c")
foreign env {
	puts :: proc(s: cstring) -> i32 ---
	fopen :: proc(path, mode: cstring) -> ^C_File ---
	fread :: proc(buffer: rawptr, size, count: uint, file: ^C_File) -> uint ---
	fclose :: proc(file: ^C_File) -> i32 ---
	malloc :: proc(size: uint) -> rawptr ---
	memalign :: proc(alignment, size: uint) -> rawptr ---
	realloc :: proc(ptr: rawptr, size: uint) -> rawptr ---
	free :: proc(ptr: rawptr) ---
	abort :: proc() -> ! ---
	emscripten_set_main_loop :: proc(loop: Main_Loop_Proc, fps: i32, simulate_infinite_loop: b32) ---
	emscripten_cancel_main_loop :: proc() ---
}

// The Roc app defines these symbols at the final link.
@(default_calling_convention = "c")
foreign {
	roc_init :: proc(text: Roc_Str) -> rawptr ---
	roc_step :: proc(model: rawptr, step: u64) -> Roc_Step ---
}

@(export, link_name = "rocco_web_main")
web_main :: proc "c" () -> i32 {
	context = runtime.default_context()
	#force_no_inline runtime._startup_runtime()

	text, ok := read_file("/hello.txt")
	if !ok {
		puts("host: could not read /hello.txt")
		return 1
	}
	puts("host: read /hello.txt through the emscripten file system")
	g_model = roc_init(text)
	emscripten_set_main_loop(step_frame, 0, false)
	return 0
}

step_frame :: proc "c" () {
	g_step += 1
	stepped := roc_step(g_model, g_step)
	g_model = stepped.model
	line := stepped.line
	print_roc_str(&line)
	if g_step >= STEP_COUNT {
		emscripten_cancel_main_loop()
	}
}

// Reads the file into a refcounted Roc allocation, so the Roc_Str owns it and
// Roc frees it through roc_dealloc.
read_file :: proc "contextless" (path: cstring) -> (Roc_Str, bool) {
	file := fopen(path, "rb")
	if file == nil {
		return {}, false
	}
	defer fclose(file)
	capacity :: 4096
	base := ([^]u8)(roc_alloc(size_of(int) + capacity, size_of(int)))
	(^int)(base)^ = 1
	bytes := base[size_of(int):]
	length := int(fread(bytes, 1, capacity, file))
	return {bytes = bytes, length = length, capacity = capacity}, true
}

print_roc_str :: proc "contextless" (s: ^Roc_Str) {
	text: []u8
	if s.length < 0 {
		raw := ([^]u8)(s)
		text = raw[:raw[size_of(Roc_Str) - 1] & 0x7f]
	} else {
		text = s.bytes[:s.length]
	}
	line := ([^]u8)(malloc(uint(len(text) + 1)))
	copy(line[:len(text)], text)
	line[len(text)] = 0
	puts(cstring(line))
	free(line)
}

@(export, link_name = "roc_alloc")
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
	// emscripten's aligned_alloc returned nil for some Roc allocations. memalign has no length rule.
	ptr := memalign(max(alignment, size_of(rawptr)), length)
	if ptr == nil {
		puts("roc_alloc: out of memory")
		abort()
	}
	return ptr
}

@(export, link_name = "roc_dealloc")
roc_dealloc :: proc "c" (ptr: rawptr, alignment: uint) {
	free(ptr)
}

// realloc keeps malloc's 8-byte alignment. The spike app allocates nothing
// with a larger alignment.
@(export, link_name = "roc_realloc")
roc_realloc :: proc "c" (ptr: rawptr, new_length: uint, alignment: uint) -> rawptr {
	return realloc(ptr, new_length)
}

@(export, link_name = "roc_dbg")
roc_dbg :: proc "c" (bytes: [^]u8, length: uint) {
	puts("roc_dbg")
}

@(export, link_name = "roc_expect_failed")
roc_expect_failed :: proc "c" (bytes: [^]u8, length: uint) {
	puts("roc_expect_failed")
}

@(export, link_name = "roc_crashed")
roc_crashed :: proc "c" (bytes: [^]u8, length: uint) {
	puts("roc_crashed")
	abort()
}
