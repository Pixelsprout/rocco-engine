package engine

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"

// One name and id of a Manifest, before it crosses the seam.
Manifest_Line :: struct {
	name: string,
	id:   u32,
}

// A mesh unloads when the refs of its slot reach 0. Each logged set keeps a
// nonsense Command or a bad asset to one log line per run.
Packs :: struct {
	meshes:         ^Mesh_Table,
	mesh_dir:       string,
	on_disk:        []string,
	loaded:         map[string][]u32,
	refs:           [MESH_CAPACITY]int,
	logged_packs:   map[string]struct {},
	logged_unloads: map[string]struct {},
	logged_assets:  map[string]struct {},
	logged_full:    map[string]struct {},
	allocator:      mem.Allocator,
}

// Names the meshes on disk and loads none of them. The allocator must free,
// because packs unload in any order.
packs_init :: proc(p: ^Packs, meshes: ^Mesh_Table, mesh_dir: string, allocator: mem.Allocator) {
	p^ = {
		meshes         = meshes,
		mesh_dir       = strings.clone(mesh_dir, allocator),
		on_disk        = mesh_names_on_disk(mesh_dir, allocator),
		loaded         = make(map[string][]u32, allocator),
		logged_packs   = make(map[string]struct {}, allocator),
		logged_unloads = make(map[string]struct {}, allocator),
		logged_assets  = make(map[string]struct {}, allocator),
		logged_full    = make(map[string]struct {}, allocator),
		allocator      = allocator,
	}
}

// Frees what the packs own. The meshes stay in the mesh table.
packs_destroy :: proc(p: ^Packs) {
	for name, ids in p.loaded {
		delete(name, p.allocator)
		delete(ids, p.allocator)
	}
	delete(p.loaded)
	for set in ([]^map[string]struct {}{&p.logged_packs, &p.logged_unloads, &p.logged_assets, &p.logged_full}) {
		for name in set {
			delete(name, p.allocator)
		}
		delete(set^)
	}
	for name in p.on_disk {
		delete(name, p.allocator)
	}
	delete(p.on_disk, p.allocator)
	delete(p.mesh_dir, p.allocator)
}

// Loads each named asset that is not loaded yet. The Manifest has one line
// per name, in order; a name that did not load has id 0. A pack that is
// already loaded gives ok = false.
pack_load :: proc(p: ^Packs, pack: string, assets: []string, allocator: mem.Allocator) -> (manifest: []Manifest_Line, ok: bool) {
	if pack in p.loaded {
		if pack not_in p.logged_packs {
			p.logged_packs[strings.clone(pack, p.allocator)] = {}
			fmt.eprintfln("pack %q is already loaded; ignoring the Load", pack)
		}
		return nil, false
	}

	held := make([dynamic]u32, 0, len(assets), p.allocator)
	manifest = make([]Manifest_Line, len(assets), allocator)
	for name, i in assets {
		id := pack_asset_id(p, pack, name)
		manifest[i] = {name = name, id = id}
		slot := mesh_slot(id)
		if slot >= len(Primitive) && !slice.contains(held[:], id) {
			append(&held, id)
			p.refs[slot] += 1
		}
	}
	p.loaded[strings.clone(pack, p.allocator)] = held[:]
	return manifest, true
}

// Unloads each mesh no other loaded pack holds. An unknown pack gives
// ok = false.
pack_unload :: proc(p: ^Packs, pack: string) -> (ok: bool) {
	name, held, found := pack_take(p, pack)
	if !found {
		if pack not_in p.logged_unloads {
			p.logged_unloads[strings.clone(pack, p.allocator)] = {}
			fmt.eprintfln("pack %q is not loaded; ignoring the Unload", pack)
		}
		return false
	}
	for id in held {
		slot := mesh_slot(id)
		p.refs[slot] -= 1
		if p.refs[slot] == 0 {
			mesh_table_remove(p.meshes, slot)
		}
	}
	delete(name, p.allocator)
	delete(held, p.allocator)
	return true
}

@(private = "file")
pack_take :: proc(p: ^Packs, pack: string) -> (name: string, held: []u32, found: bool) {
	if pack not_in p.loaded {
		return
	}
	name, held = delete_key(&p.loaded, pack)
	return name, held, true
}

// A primitive or an asset another pack loaded keeps its id. A name that
// failed once is not read again, but a full table can empty, so a name that
// found it full tries again.
@(private = "file")
pack_asset_id :: proc(p: ^Packs, pack, name: string) -> u32 {
	if id, found := mesh_table_find(p.meshes, name); found {
		return id
	}
	if name in p.logged_assets {
		return 0
	}
	if !slice.contains(p.on_disk, name) {
		pack_log_asset(p, name, fmt.tprintf("pack %q names %q, which is not in %v", pack, name, p.mesh_dir))
		return 0
	}
	if mesh_table_full(p.meshes) {
		if name not_in p.logged_full {
			p.logged_full[strings.clone(name, p.allocator)] = {}
			fmt.eprintfln("pack %q names %q, but the mesh table is full at %v meshes; its id is 0, the fallback", pack, name, MESH_CAPACITY)
		}
		return 0
	}
	id, reason, ok := mesh_load_file(p.meshes, p.mesh_dir, name)
	if !ok {
		pack_log_asset(p, name, fmt.tprintf("pack %q names %q, which did not load: %v", pack, name, reason))
		return 0
	}
	return id
}

@(private = "file")
pack_log_asset :: proc(p: ^Packs, name, message: string) {
	p.logged_assets[strings.clone(name, p.allocator)] = {}
	fmt.eprintfln("%v; its id is 0, the fallback", message)
}
