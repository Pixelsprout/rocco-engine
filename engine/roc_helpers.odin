package engine

// Roc runtime helpers for the host.
//
// These complement the generated roc_platform_abi.odin with allocation,
// refcount, and conversion utilities. Keep this file in sync with the
// platform ABI: if the provided functions change, regenerate the ABI and
// review this file.

import "core:mem"

// ---------------------------------------------------------------- refcount

// Every Roc heap allocation stores a refcount int immediately before its
// data pointer. A refcount of 0 means static (never freed). Positive values
// are the live reference count.

@(private = "file")
roc_rc_ptr :: proc(data: rawptr) -> ^int {
	return (^int)(uintptr(data) - size_of(int))
}

// Increment the refcount of a live heap pointer. Safe to call on nil
// (Box holding a unit value), which we treat as static.
roc_incref_box :: proc(data: rawptr) {
	if data == nil {
		return
	}
	rc := roc_rc_ptr(data)
	if rc^ != 0 { // 0 == static, do not touch
		rc^ += 1
	}
}

// Decrement the refcount and free when it reaches zero.
// Returns true when the allocation was freed.
@(private = "file")
roc_release_box :: proc(data: rawptr) -> bool {
	if data == nil {
		return false
	}
	rc := roc_rc_ptr(data)
	if rc^ == 0 {
		return false // static
	}
	rc^ -= 1
	if rc^ == 0 {
		roc_dealloc(rawptr(uintptr(data) - size_of(int)), uint(align_of(uintptr)))
		return true
	}
	return false
}

// -------------------------------------------------------------------- lists

// Roc always allocates lists with `allocateWithRefcount`, which reserves two
// words before the data pointer: [element_count][refcount]. This is true even
// for flat element types. The "flat" vs "rc" distinction only affects whether
// Roc iterates elements during drop, not the header layout.
//
// header = max(2 * size_of(uint), align_of(T)).
// On 64-bit with align <= 16, header is always 16.
@(private = "file")
LIST_HEADER :: 2 * size_of(uint)

// Allocate a new Roc_List by copying elems. The list starts at refcount 1.
// Use for flat element types (scalars, plain structs without owned pointers).
roc_list_from_slice :: proc {
	roc_list_from_slice_u16,
	roc_list_from_slice_mesh_entry,
}

@(private = "file")
roc_list_alloc :: proc($T: typeid, n: uint) -> Roc_List(T) {
	if n == 0 {
		return {}
	}
	alignment := uint(align_of(T))
	raw_header := uint(LIST_HEADER)
	header := max(raw_header, alignment)
	base := roc_alloc(header + n * size_of(T), alignment)
	if base == nil {
		panic("roc_alloc returned nil")
	}
	data := rawptr(uintptr(base) + uintptr(header))
	// Two-word header: [element_count][refcount] immediately before data.
	(^uint)(uintptr(data) - 2 * size_of(uint))^ = n  // element count
	(^int)(uintptr(data) - size_of(int))^ = 1        // refcount = 1
	return Roc_List(T){
		elements              = ([^]T)(data),
		length                = n,
		capacity_or_alloc_ptr = n << 1, // even capacity = owned allocation
	}
}

roc_list_from_slice_u16 :: proc(elems: []u16) -> Roc_List(u16) {
	list := roc_list_alloc(u16, uint(len(elems)))
	if list.length > 0 {
		mem.copy(list.elements, raw_data(elems), len(elems) * size_of(u16))
	}
	return list
}

roc_list_from_slice_mesh_entry :: proc(elems: []Mesh_Entry) -> Roc_List(Mesh_Entry) {
	list := roc_list_alloc(Mesh_Entry, uint(len(elems)))
	if list.length > 0 {
		mem.copy(list.elements, raw_data(elems), len(elems) * size_of(Mesh_Entry))
	}
	return list
}

// Release a flat list (no nested refcounted values).
@(private = "file")
roc_list_decref_flat :: proc($T: typeid, list: Roc_List(T)) {
	if list.elements == nil {
		return
	}
	// Resolve the data pointer: seamless slice tags the low bit of capacity.
	data: rawptr
	if list.capacity_or_alloc_ptr & 1 != 0 {
		data = rawptr(uintptr(list.capacity_or_alloc_ptr &~ 1))
	} else {
		data = list.elements
	}
	rc := roc_rc_ptr(data)
	if rc^ == 0 {
		return // static
	}
	rc^ -= 1
	if rc^ == 0 {
		alignment := uint(align_of(T))
		header := max(uint(LIST_HEADER), alignment)
		roc_dealloc(rawptr(uintptr(data) - uintptr(header)), alignment)
	}
}

// -------------------------------------------------------------- Scene decref

// Release a Scene returned by roc_view. The Scene owns its draws list.
// The nested Roc_View_Draws structs are flat (no owned pointers), so a
// simple flat list decref is correct.
roc_decref :: proc {
	roc_decref_scene,
}

@(private = "file")
roc_decref_scene :: proc(scene: Scene) {
	roc_list_decref_flat(Roc_View_Draws, scene.draws)
}

// --------------------------------------------------------------- Roc_Str

// Build a Roc_Str from an Odin string literal. The bytes are copied into a
// fresh roc_alloc at refcount 1. roc_init consumes the reference.
roc_str_from_slice :: proc(s: string) -> Roc_Str {
	n := uint(len(s))
	if n == 0 {
		return {}
	}
	alignment := uint(align_of(u8))
	header := max(uint(LIST_HEADER), alignment)
	base := roc_alloc(header + n, alignment)
	if base == nil {
		panic("roc_alloc returned nil")
	}
	data := rawptr(uintptr(base) + uintptr(header))
	(^int)(uintptr(data) - size_of(int))^ = 1 // refcount = 1
	mem.copy(data, raw_data(s), int(n))
	return Roc_Str{bytes = ([^]u8)(data), length = n, capacity = n << 1}
}
