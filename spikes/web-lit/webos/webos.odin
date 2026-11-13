// core:os does not build on freestanding wasm. The slice imports this
// package as os. It holds the part of core:os that the copied engine files
// call, on top of emscripten's libc, which reads the preloaded file system.
package webos

import "core:mem"
import "core:strings"

foreign import env "env.o"

FILE_SEEK_END :: 2
// emscripten's dirent.h.
DT_DIR :: 4

Error :: enum i32 {
	None,
	Not_Exist,
	Read,
	Unsupported,
}

File :: struct {
	handle: rawptr,
}

File_Type :: enum {
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

@(default_calling_convention = "c")
foreign env {
	fopen :: proc(path, mode: cstring) -> rawptr ---
	fclose :: proc(file: rawptr) -> i32 ---
	fread :: proc(ptr: rawptr, size, count: uint, file: rawptr) -> uint ---
	fseek :: proc(file: rawptr, offset: int, whence: i32) -> i32 ---
	ftell :: proc(file: rawptr) -> int ---
	rewind :: proc(file: rawptr) ---
	opendir :: proc(path: cstring) -> rawptr ---
	readdir :: proc(dir: rawptr) -> ^Dirent ---
	closedir :: proc(dir: rawptr) -> i32 ---
	getenv :: proc(name: cstring) -> cstring ---
	@(link_name = "exit")
	libc_exit :: proc(code: i32) -> ! ---
}

error_string :: proc(err: Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Not_Exist:
		return "not found"
	case .Read:
		return "read failed"
	case .Unsupported:
		return "not supported on the web"
	}
	return "unknown error"
}

exit :: proc "contextless" (code: int) -> ! {
	libc_exit(i32(code))
}

ext :: proc(path: string) -> string {
	name := path[strings.last_index_byte(path, '/') + 1:]
	dot := strings.last_index_byte(name, '.')
	return name[dot:] if dot > 0 else ""
}

stem :: proc(path: string) -> string {
	name := path[strings.last_index_byte(path, '/') + 1:]
	dot := strings.last_index_byte(name, '.')
	return name[:dot] if dot > 0 else name
}

open :: proc(path: string) -> (^File, Error) {
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
	if fseek(file.handle, 0, FILE_SEEK_END) != 0 {
		return 0, .Read
	}
	size := ftell(file.handle)
	fseek(file.handle, at, 0)
	return i64(size), nil
}

read :: proc(file: ^File, bytes: []byte) -> (int, Error) {
	if len(bytes) == 0 {
		return 0, nil
	}
	return int(fread(raw_data(bytes), 1, uint(len(bytes)), file.handle)), nil
}

read_entire_file :: proc(path: string, allocator: mem.Allocator) -> ([]byte, Error) {
	file, err := open(path)
	if err != nil {
		return nil, err
	}
	defer close(file)
	size, _ := file_size(file)
	bytes := make([]byte, int(size), allocator)
	n, _ := read(file, bytes)
	if n != len(bytes) {
		delete(bytes, allocator)
		return nil, .Read
	}
	return bytes, nil
}

read_all_directory_by_path :: proc(path: string, allocator: mem.Allocator) -> ([]File_Info, Error) {
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
		append(&entries, File_Info{name = strings.clone(name, allocator), type = .Directory if entry.type == DT_DIR else .Regular})
	}
	return entries[:], nil
}

write_entire_file :: proc(path: string, data: []byte) -> Error {
	return .Unsupported
}

get_env :: proc(name: string, allocator: mem.Allocator) -> string {
	value, _ := lookup_env(name, allocator)
	return value
}

lookup_env :: proc(name: string, allocator: mem.Allocator) -> (string, bool) {
	value := getenv(strings.clone_to_cstring(name, context.temp_allocator))
	if value == nil {
		return "", false
	}
	return strings.clone(string(value), allocator), true
}
