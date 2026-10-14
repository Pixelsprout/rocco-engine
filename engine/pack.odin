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

// The loaded pack names and the mesh names on disk a Load can ask for.
// Each logged set keeps a nonsense Load or a bad asset to one log line per run.
Packs :: struct {
	meshes:        ^Mesh_Table,
	mesh_dir:      string,
	on_disk:       []string,
	loaded:        map[string]struct {},
	logged_packs:  map[string]struct {},
	logged_assets: map[string]struct {},
	allocator:     mem.Allocator,
}

// Names the meshes on disk and loads none of them.
packs_init :: proc(p: ^Packs, meshes: ^Mesh_Table, mesh_dir: string, allocator: mem.Allocator) {
	p^ = {
		meshes        = meshes,
		mesh_dir      = strings.clone(mesh_dir, allocator),
		on_disk       = mesh_names_on_disk(mesh_dir, allocator),
		loaded        = make(map[string]struct {}, allocator),
		logged_packs  = make(map[string]struct {}, allocator),
		logged_assets = make(map[string]struct {}, allocator),
		allocator     = allocator,
	}
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
	p.loaded[strings.clone(pack, p.allocator)] = {}

	manifest = make([]Manifest_Line, len(assets), allocator)
	for name, i in assets {
		manifest[i] = {name = name, id = pack_asset_id(p, pack, name)}
	}
	return manifest, true
}

// A primitive or an asset another pack loaded keeps its id. A name that
// failed once is not read again.
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
	id, reason, ok := mesh_load_file(p.meshes, p.mesh_dir, name, p.allocator)
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
