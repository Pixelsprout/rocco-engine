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
	Sound,
}

Held_Asset :: struct {
	kind: Asset_Kind,
	id:   u32,
}

// An asset unloads when the refs of its slot reach 0. Each logged set keeps a
// nonsense Command or a bad asset to one log line per run.
// on_disk lists the meshes, then the skies, then the Sounds; it is also
// Config.assets. sound_files maps each Sound name to its file in sound_dir.
Packs :: struct {
	meshes:         ^Mesh_Table,
	skies:          ^Sky_Table,
	audio:          ^Audio,
	mesh_dir:       string,
	sky_dir:        string,
	sound_dir:      string,
	on_disk:        []string,
	sound_files:    map[string]string,
	loaded:         map[string][]Held_Asset,
	mesh_refs:      []int,
	sky_refs:       []int,
	sound_refs:     []int,
	logged_packs:   map[string]struct {},
	logged_unloads: map[string]struct {},
	logged_assets:  map[string]struct {},
	logged_full:    map[string]struct {},
	logged_stems:   map[string]struct {},
	allocator:      mem.Allocator,
	perm:           mem.Allocator,
}

// Names the meshes, skies and Sounds under assets_dir and loads none of them.
// A Load needs packs_attach first. The allocator must free, because packs
// unload in any order.
packs_init :: proc(p: ^Packs, assets_dir: string, allocator: mem.Allocator) {
	mesh_dir := fmt.aprintf("%v/meshes", assets_dir, allocator = allocator)
	sky_dir := fmt.aprintf("%v/sky", assets_dir, allocator = allocator)
	sound_dir := fmt.aprintf("%v/sound", assets_dir, allocator = allocator)
	mesh_names := mesh_names_on_disk(mesh_dir, allocator)
	defer delete(mesh_names, allocator)
	sky_names := sky_names_on_disk(sky_dir, allocator)
	defer delete(sky_names, allocator)
	sound_files := make(map[string]string, allocator)
	logged_stems := make(map[string]struct {}, allocator)
	sound_names := sound_names_on_disk(sound_dir, &sound_files, &logged_stems, allocator)
	defer delete(sound_names, allocator)
	p^ = {
		mesh_dir       = mesh_dir,
		sky_dir        = sky_dir,
		sound_dir      = sound_dir,
		on_disk        = slice.concatenate([][]string{mesh_names, sky_names, sound_names}, allocator),
		sound_files    = sound_files,
		loaded         = make(map[string][]Held_Asset, allocator),
		logged_packs   = make(map[string]struct {}, allocator),
		logged_unloads = make(map[string]struct {}, allocator),
		logged_assets  = make(map[string]struct {}, allocator),
		logged_full    = make(map[string]struct {}, allocator),
		logged_stems   = logged_stems,
		allocator      = allocator,
	}
}

// Runs after launch, because the tables take their size from the Launch.
// The refs take one slot per table slot from perm.
packs_attach :: proc(p: ^Packs, meshes: ^Mesh_Table, skies: ^Sky_Table, audio: ^Audio, perm: mem.Allocator) {
	p.meshes = meshes
	p.skies = skies
	p.audio = audio
	p.mesh_refs = make([]int, len(meshes.meshes), perm)
	p.sky_refs = make([]int, len(skies.skies), perm)
	p.sound_refs = make([]int, len(audio.sounds.sounds), perm)
	p.perm = perm
}

// Frees what the packs own. The assets stay in their tables.
packs_destroy :: proc(p: ^Packs) {
	for name, ids in p.loaded {
		delete(name, p.allocator)
		delete(ids, p.allocator)
	}
	delete(p.loaded)
	for name, file in p.sound_files {
		delete(name, p.allocator)
		delete(file, p.allocator)
	}
	delete(p.sound_files)
	for set in ([]^map[string]struct {}{&p.logged_packs, &p.logged_unloads, &p.logged_assets, &p.logged_full, &p.logged_stems}) {
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
	delete(p.sound_dir, p.allocator)
	delete(p.mesh_refs, p.perm)
	delete(p.sky_refs, p.perm)
	delete(p.sound_refs, p.perm)
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

// The mesh a Manifest line names, if the line names a loaded mesh.
pack_line_mesh :: proc(p: ^Packs, line: Manifest_Line) -> (mesh: ^Mesh, ok: bool) {
	if pack_kind(line.name) != .Mesh {
		return nil, false
	}
	return mesh_lookup(p.meshes, line.id)
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
		case .Sound:
			audio_sound_remove(p.audio, sound_slot(asset.id))
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

// Id 0 is the fallback mesh, no sky or no Sound, and a primitive never
// unloads.
@(private = "file")
pack_refcounted :: proc(asset: Held_Asset) -> bool {
	switch asset.kind {
	case .Mesh:
		return mesh_slot(asset.id) >= len(Primitive)
	case .Sky, .Sound:
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
	case .Sound:
		return &p.sound_refs[sound_slot(asset.id)]
	}
	unreachable()
}

// A primitive or an asset another pack loaded keeps its id. A name that
// failed once is not read again, but a full table can empty, so a name that
// found it full tries again.
@(private = "file")
pack_asset_id :: proc(p: ^Packs, pack, name: string) -> Held_Asset {
	kind := pack_kind(name)
	found_id: u32
	found: bool
	dir: string
	full: bool
	full_reason: string
	switch kind {
	case .Mesh:
		found_id, found = mesh_table_find(p.meshes, name)
		dir, full = p.mesh_dir, mesh_table_full(p.meshes)
	case .Sky:
		found_id, found = sky_table_find(p.skies, name)
		dir, full = p.sky_dir, sky_table_full(p.skies)
	case .Sound:
		found_id, found = sound_table_find(&p.audio.sounds, name)
		dir, full = p.sound_dir, sound_table_full(&p.audio.sounds)
	}
	if found {
		return {kind, found_id}
	}
	if name in p.logged_assets {
		return {kind, 0}
	}
	if !slice.contains(p.on_disk, name) {
		pack_log_asset(p, name, fmt.tprintf("pack %q names %q, which is not in %v", pack, name, dir))
		return {kind, 0}
	}
	if full {
		if name not_in p.logged_full {
			p.logged_full[strings.clone(name, p.allocator)] = {}
			switch kind {
			case .Mesh:
				full_reason = mesh_table_full_reason(p.meshes)
			case .Sky:
				full_reason = sky_table_full_reason(p.skies)
			case .Sound:
				full_reason = sound_table_full_reason(&p.audio.sounds)
			}
			fmt.eprintfln("pack %q names %q, but %v; its id is 0", pack, name, full_reason)
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
	case .Sound:
		id, reason, ok = sound_load_file(&p.audio.sounds, p.sound_dir, name, p.sound_files[name])
	}
	if !ok {
		pack_log_asset(p, name, fmt.tprintf("pack %q names %q, which did not load: %v", pack, name, reason))
		return {kind, 0}
	}
	return {kind, id}
}

// The prefix chooses the kind. A name with no known prefix is a mesh.
@(private = "file")
pack_kind :: proc(name: string) -> Asset_Kind {
	switch {
	case strings.has_prefix(name, SKY_PREFIX):
		return .Sky
	case strings.has_prefix(name, SOUND_PREFIX):
		return .Sound
	}
	return .Mesh
}

@(private = "file")
pack_log_asset :: proc(p: ^Packs, name, message: string) {
	p.logged_assets[strings.clone(name, p.allocator)] = {}
	fmt.eprintfln("%v; its id is 0", message)
}
