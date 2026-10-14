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

Asset_Kind :: enum {
	Mesh,
	Sky,
}

Held_Asset :: struct {
	kind: Asset_Kind,
	id:   u32,
}

// An asset unloads when the refs of its slot reach 0. Each logged set keeps a
// nonsense Command or a bad asset to one log line per run.
Packs :: struct {
	meshes:         ^Mesh_Table,
	skies:          ^Sky_Table,
	mesh_dir:       string,
	sky_dir:        string,
	on_disk:        []string,
	loaded:         map[string][]Held_Asset,
	mesh_refs:      [MESH_CAPACITY]int,
	sky_refs:       [SKY_CAPACITY]int,
	logged_packs:   map[string]struct {},
	logged_unloads: map[string]struct {},
	logged_assets:  map[string]struct {},
	logged_full:    map[string]struct {},
	allocator:      mem.Allocator,
}

// Names the meshes and skies under assets_dir and loads none of them. The
// allocator must free, because packs unload in any order.
packs_init :: proc(p: ^Packs, meshes: ^Mesh_Table, skies: ^Sky_Table, assets_dir: string, allocator: mem.Allocator) {
	mesh_dir := fmt.aprintf("%v/meshes", assets_dir, allocator = allocator)
	sky_dir := fmt.aprintf("%v/sky", assets_dir, allocator = allocator)
	mesh_names := mesh_names_on_disk(mesh_dir, allocator)
	defer delete(mesh_names, allocator)
	sky_names := sky_names_on_disk(sky_dir, allocator)
	defer delete(sky_names, allocator)
	p^ = {
		meshes         = meshes,
		skies          = skies,
		mesh_dir       = mesh_dir,
		sky_dir        = sky_dir,
		on_disk        = slice.concatenate([][]string{mesh_names, sky_names}, allocator),
		loaded         = make(map[string][]Held_Asset, allocator),
		logged_packs   = make(map[string]struct {}, allocator),
		logged_unloads = make(map[string]struct {}, allocator),
		logged_assets  = make(map[string]struct {}, allocator),
		logged_full    = make(map[string]struct {}, allocator),
		allocator      = allocator,
	}
}

// Frees what the packs own. The assets stay in their tables.
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
	delete(p.sky_dir, p.allocator)
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

	held := make([dynamic]Held_Asset, 0, len(assets), p.allocator)
	manifest = make([]Manifest_Line, len(assets), allocator)
	for name, i in assets {
		asset := pack_asset_id(p, pack, name)
		manifest[i] = {name = name, id = asset.id}
		if pack_refcounted(asset) && !slice.contains(held[:], asset) {
			append(&held, asset)
			pack_refs(p, asset)^ += 1
		}
	}
	p.loaded[strings.clone(pack, p.allocator)] = held[:]
	return manifest, true
}

// Unloads each asset no other loaded pack holds. An unknown pack gives
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
	for asset in held {
		refs := pack_refs(p, asset)
		refs^ -= 1
		if refs^ > 0 {
			continue
		}
		switch asset.kind {
		case .Mesh:
			mesh_table_remove(p.meshes, mesh_slot(asset.id))
		case .Sky:
			sky_table_remove(p.skies, sky_slot(asset.id))
		}
	}
	delete(name, p.allocator)
	delete(held, p.allocator)
	return true
}

@(private = "file")
pack_take :: proc(p: ^Packs, pack: string) -> (name: string, held: []Held_Asset, found: bool) {
	if pack not_in p.loaded {
		return
	}
	name, held = delete_key(&p.loaded, pack)
	return name, held, true
}

// Id 0 is the fallback mesh or no sky, and a primitive never unloads.
@(private = "file")
pack_refcounted :: proc(asset: Held_Asset) -> bool {
	switch asset.kind {
	case .Mesh:
		return mesh_slot(asset.id) >= len(Primitive)
	case .Sky:
		return asset.id != 0
	}
	unreachable()
}

@(private = "file")
pack_refs :: proc(p: ^Packs, asset: Held_Asset) -> ^int {
	switch asset.kind {
	case .Mesh:
		return &p.mesh_refs[mesh_slot(asset.id)]
	case .Sky:
		return &p.sky_refs[sky_slot(asset.id)]
	}
	unreachable()
}

// A primitive or an asset another pack loaded keeps its id. A name that
// failed once is not read again, but a full table can empty, so a name that
// found it full tries again.
@(private = "file")
pack_asset_id :: proc(p: ^Packs, pack, name: string) -> Held_Asset {
	kind := Asset_Kind.Sky if strings.has_prefix(name, SKY_PREFIX) else .Mesh
	found_id: u32
	found: bool
	switch kind {
	case .Mesh:
		found_id, found = mesh_table_find(p.meshes, name)
	case .Sky:
		found_id, found = sky_table_find(p.skies, name)
	}
	if found {
		return {kind, found_id}
	}
	if name in p.logged_assets {
		return {kind, 0}
	}
	dir := p.sky_dir if kind == .Sky else p.mesh_dir
	if !slice.contains(p.on_disk, name) {
		pack_log_asset(p, name, fmt.tprintf("pack %q names %q, which is not in %v", pack, name, dir))
		return {kind, 0}
	}
	full := sky_table_full(p.skies) if kind == .Sky else mesh_table_full(p.meshes)
	if full {
		if name not_in p.logged_full {
			p.logged_full[strings.clone(name, p.allocator)] = {}
			table := fmt.tprintf("the sky table is full at %v skies", SKY_CAPACITY - 1) if kind == .Sky else fmt.tprintf("the mesh table is full at %v meshes", MESH_CAPACITY)
			fmt.eprintfln("pack %q names %q, but %v; its id is 0", pack, name, table)
		}
		return {kind, 0}
	}
	id: u32
	reason: string
	ok: bool
	switch kind {
	case .Mesh:
		id, reason, ok = mesh_load_file(p.meshes, p.mesh_dir, name)
	case .Sky:
		id, reason, ok = sky_load_dir(p.skies, p.sky_dir, name)
	}
	if !ok {
		pack_log_asset(p, name, fmt.tprintf("pack %q names %q, which did not load: %v", pack, name, reason))
		return {kind, 0}
	}
	return {kind, id}
}

@(private = "file")
pack_log_asset :: proc(p: ^Packs, name, message: string) {
	p.logged_assets[strings.clone(name, p.allocator)] = {}
	fmt.eprintfln("%v; its id is 0", message)
}
