#+build freestanding
// core:os and the printing half of core:fmt do not build on freestanding
// wasm. The web host links emscripten's libc, whose file system holds the
// preloaded Packs, so this file gives the engine the same names on top of it.
package system

import "core:fmt"
import "core:io"
import "core:strings"

import "base:runtime"

// The "env.o" name makes the wasm import module "env". emcc resolves these
// against emscripten's libc.
foreign import env "env.o"

STDOUT :: 1
STDERR :: 2
SEEK_SET :: 0
SEEK_END :: 2
// emscripten's dirent.h.
DT_DIR :: 4

Web_Error :: enum u32 {
	None,
	Not_Exist,
	Read,
	Unsupported,
}

Error :: union #shared_nil {
	Web_Error,
	io.Error,
	runtime.Allocator_Error,
}

File :: struct {
	handle: rawptr,
}

File_Flag :: enum {
	Read,
	Write,
	Append,
	Create,
	Excl,
	Sync,
	Trunc,
}

File_Flags :: distinct bit_set[File_Flag; uint]

File_Type :: enum {
	Undetermined,
	Regular,
	Directory,
}

File_Info :: struct {
	name: string,
	type: File_Type,
}

// emscripten's struct dirent, with a 64-bit ino_t and off_t.
Dirent :: struct {
	ino:    u64,
	off:    i64,
	reclen: u16,
	type:   u8,
	name:   [256]u8,
}

// A page has no command line.
args: []string

@(default_calling_convention = "c")
foreign env {
	fopen :: proc(path, mode: cstring) -> rawptr ---
	fclose :: proc(file: rawptr) -> i32 ---
	fread :: proc(ptr: rawptr, size, count: uint, file: rawptr) -> uint ---
	fseek :: proc(file: rawptr, offset: int, whence: i32) -> i32 ---
	ftell :: proc(file: rawptr) -> int ---
	opendir :: proc(path: cstring) -> rawptr ---
	readdir :: proc(dir: rawptr) -> ^Dirent ---
	closedir :: proc(dir: rawptr) -> i32 ---
	getenv :: proc(name: cstring) -> cstring ---
	@(link_name = "write")
	libc_write :: proc(fd: i32, buf: rawptr, count: uint) -> int ---
	@(link_name = "exit")
	libc_exit :: proc(code: i32) -> ! ---
}

error_string :: proc(err: Error) -> string {
	switch e in err {
	case Web_Error:
		switch e {
		case .None:
			return ""
		case .Not_Exist:
			return "not found"
		case .Read:
			return "read failed"
		case .Unsupported:
			return "not supported on the web"
		}
	case io.Error:
		return fmt.tprint(e)
	case runtime.Allocator_Error:
		return "out of memory"
	}
	return ""
}

exit :: proc "contextless" (code: int) -> ! {
	libc_exit(i32(code))
}

is_absolute_path :: proc(path: string) -> bool {
	return strings.has_prefix(path, "/")
}

split_path :: proc(path: string) -> (dir, filename: string) {
	i := strings.last_index_byte(path, '/')
	if i < 0 {
		return "", path
	}
	return path[:max(i, 1)], path[i + 1:]
}

ext :: proc(path: string) -> string {
	for i := len(path) - 1; i >= 0 && path[i] != '/'; i -= 1 {
		if path[i] == '.' {
			return path[i:]
		}
	}
	return ""
}

stem :: proc(path: string) -> string {
	if path == "" || path[len(path) - 1] == '/' {
		return ""
	}
	_, name := split_path(path)
	if i := strings.last_index_byte(name, '.'); i != -1 {
		return name[:i]
	}
	return name
}

// Only reads reach the preloaded file system. The web host never writes.
open :: proc(path: string, flags := File_Flags{.Read}, perm := 0) -> (^File, Error) {
	if flags != {.Read} {
		return nil, Web_Error.Unsupported
	}
	handle := fopen(strings.clone_to_cstring(path, context.temp_allocator), "rb")
	if handle == nil {
		return nil, .Not_Exist
	}
	file := new(File)
	file.handle = handle
	return file, nil
}

close :: proc(file: ^File) -> Error {
	if file == nil {
		return nil
	}
	fclose(file.handle)
	free(file)
	return nil
}

file_size :: proc(file: ^File) -> (i64, Error) {
	at := ftell(file.handle)
	if fseek(file.handle, 0, SEEK_END) != 0 {
		return 0, .Read
	}
	size := ftell(file.handle)
	fseek(file.handle, at, SEEK_SET)
	return i64(size), nil
}

read :: proc(file: ^File, bytes: []byte) -> (int, Error) {
	if len(bytes) == 0 {
		return 0, nil
	}
	return int(fread(raw_data(bytes), 1, uint(len(bytes)), file.handle)), nil
}

write :: proc(file: ^File, bytes: []byte) -> (int, Error) {
	return 0, Web_Error.Unsupported
}

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> (bytes: []byte, err: Error) {
	file := open(path) or_return
	defer close(file)
	size := file_size(file) or_return
	bytes = make([]byte, int(size), allocator) or_return
	if n, _ := read(file, bytes); n != len(bytes) {
		delete(bytes, allocator)
		return nil, .Read
	}
	return bytes, nil
}

write_entire_file :: proc(path: string, data: []byte) -> Error {
	return Web_Error.Unsupported
}

read_all_directory_by_path :: proc(path: string, allocator: runtime.Allocator) -> ([]File_Info, Error) {
	dir := opendir(strings.clone_to_cstring(path, context.temp_allocator))
	if dir == nil {
		return nil, .Not_Exist
	}
	defer closedir(dir)
	entries := make([dynamic]File_Info, allocator)
	for entry := readdir(dir); entry != nil; entry = readdir(dir) {
		name := string(cstring(&entry.name[0]))
		if name == "." || name == ".." {
			continue
		}
		type := File_Type.Directory if entry.type == DT_DIR else .Regular
		append(&entries, File_Info{name = strings.clone(name, allocator), type = type})
	}
	return entries[:], nil
}

get_env :: proc(name: string, allocator: runtime.Allocator) -> string {
	value, _ := lookup_env(name, allocator)
	return value
}

lookup_env :: proc(name: string, allocator: runtime.Allocator) -> (string, bool) {
	value := getenv(strings.clone_to_cstring(name, context.temp_allocator))
	if value == nil {
		return "", false
	}
	return strings.clone(string(value), allocator), true
}

// emscripten sends fd 1 to Module.print and fd 2 to Module.printErr, and it
// writes a line when it sees the newline.


eprintfln :: proc(format: string, args: ..any) -> int {
	return fmt.wprintf(fd_writer(STDERR), format, ..args, newline = true)
}

eprintln :: proc(args: ..any, sep := " ") -> int {
	return fmt.wprintln(fd_writer(STDERR), ..args, sep = sep)
}


printfln :: proc(format: string, args: ..any) -> int {
	return fmt.wprintf(fd_writer(STDOUT), format, ..args, newline = true)
}

println :: proc(args: ..any, sep := " ") -> int {
	return fmt.wprintln(fd_writer(STDOUT), ..args, sep = sep)
}

fd_writer :: proc(fd: uintptr) -> io.Writer {
	return {procedure = fd_stream_proc, data = rawptr(fd)}
}

fd_stream_proc :: proc(data: rawptr, mode: io.Stream_Mode, p: []byte, offset: i64, whence: io.Seek_From) -> (i64, io.Error) {
	#partial switch mode {
	case .Write:
		n := libc_write(i32(uintptr(data)), raw_data(p), uint(len(p)))
		if n < 0 {
			return 0, .Unknown
		}
		return i64(n), nil
	case .Query:
		return io.query_utility({.Write, .Query})
	}
	return 0, .Unsupported
}
