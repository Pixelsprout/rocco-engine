package engine

import sg "../sokol-odin/sokol/gfx"
import "arenas"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

shader_read_file :: proc(path: string, allocator: mem.Allocator, limit: int) -> ([]byte, bool) {
	file, err := shader_open_file(path)
	if err != nil { return nil, false }
	defer os.close(file)
	size, size_error := os.file_size(file)
	if size_error != nil || size < 0 || size > i64(limit) { return nil, false }
	bytes := make([]byte, int(size), allocator)
	read := 0
	for read < len(bytes) {
		n, error := os.read(file, bytes[read:]); read += n
		if n == 0 || error != nil { delete(bytes, allocator); return nil, false }
	}
	extra: [1]byte
	if n, _ := os.read(file, extra[:]); n != 0 { delete(bytes, allocator); return nil, false }
	return bytes, true
}

shader_hash_text :: proc(bytes: []byte) -> string {
	hash := shader_hash(bytes)
	buffer := make([]byte, 64, context.temp_allocator)
	hex := "0123456789abcdef"
	for b, i in hash { buffer[i*2] = hex[b>>4]; buffer[i*2+1] = hex[b&15] }
	return string(buffer)
}

shader_candidate_destroy :: proc(t: ^Shader_Table, slot: int) {
	s := &t.assets[slot]
	shader_gpu_destroy(s)
	delete(s.pipelines)
	json.destroy_value(s.package_data.manifest, t.allocator)
	delete(s.package_data.bytes, t.allocator); delete(s.name, t.allocator)
	s^ = {generation = s.generation}
}

shader_candidate_stage :: proc(t: ^Shader_Table, name: string, bytes: []byte, active: ^Shader) -> (slot: int, reason: string) {
	slot = shader_free_slot(t)
	if slot == 0 { return 0, "Shader staging capacity exhausted" }
	pkg, error, ok := shader_package_parse(bytes, t.allocator)
	if !ok { return 0, error }
	if active != nil && pkg.fingerprint != active.package_data.fingerprint {
		json.destroy_value(pkg.manifest, t.allocator)
		return 0, "interface changed; rebuild the game and restart"
	}
	s := &t.assets[slot]
	s^ = {name = strings.clone(name, t.allocator), staged = true, generation = s.generation, package_data = pkg, pipelines = make(map[Shader_Pipeline_Key]sg.Pipeline, t.allocator)}
	return slot, ""
}

shader_candidate_validate :: proc(t: ^Shader_Table, candidate, active: ^Shader) -> bool {
	if !t.uploaded { return true }
	if !shader_upload(t, candidate) { return false }
	if active != nil {
		for key in active.pipelines { if _, ok := shader_pipeline(t, candidate, key); !ok { return false } }
		for pipeline, index in active.post_pipelines {
			if pipeline.id == 0 { continue }
			location := Post_Location.BeforeBloom if index == 0 else .AfterToneMap
			if _, ok := post_pipeline(candidate, location); !ok { return false }
		}
	}
	return true
}

shader_candidate_publish :: proc(t: ^Shader_Table, slot, active_slot: int) -> u32 {
	candidate := &t.assets[slot]
	candidate.staged = false; candidate.live = true
	if active_slot == 0 { return shader_id(t, slot) }
	active := &t.assets[active_slot]
	generation := active.generation
	retire_generation := candidate.generation
	active^, candidate^ = candidate^, active^
	active.generation = generation; candidate.generation = retire_generation
	// Pack-held IDs stay live while the old GPU generation occupies a retirement slot.
	shader_table_remove(t, slot)
	return shader_id(t, active_slot)
}

packs_shader_requested :: proc(p: ^Packs) -> bool {
	for pack, names in p.shader_requests { if len(names) > 0 && pack in p.loaded { return true } }
	return false
}

packs_shader_reload_poll :: proc(p: ^Packs) {
	if !packs_shader_requested(p) { return }
	if p.shader_polled && time.tick_since(p.shader_poll_at) < 250*time.Millisecond { return }
	p.shader_poll_at = time.tick_now(); p.shader_polled = true
	packs_shader_reload(p)
}

packs_shader_reload :: proc(p: ^Packs) {
	if !packs_shader_requested(p) { return }
	scratch: arenas.Arena
	defer arenas.destroy(&scratch)
	context.temp_allocator = arenas.allocator(&scratch)
	record, read := shader_read_file(fmt.tprintf("%v/build.json", p.shader_dir), context.temp_allocator, SHADER_METADATA_LIMIT)
	if !read { return }
	revision := shader_hash(record)
	if p.shader_revision_set && p.shader_revision == revision { return }
	value, err := json.parse_string(string(record), spec = .JSON, parse_integers = true, allocator = context.temp_allocator)
	if err != nil { return }
	root := shader_object(value)
	if shader_int(root["contract"]) != 1 { return }
	assets, valid_assets := root["assets"].(json.Array)
	if !valid_assets { return }
	seen := make(map[string]bool, context.temp_allocator)
	for asset in assets {
		a := shader_object(asset); name := shader_text(a["asset"]); file := shader_text(a["file"])
		stem := strings.trim_prefix(name, SHADER_PREFIX)
		if !strings.has_prefix(name, SHADER_PREFIX) || !shader_identifier(stem) || file != fmt.tprintf("%v.shaderpack", stem) || seen[name] { return }
		seen[name] = true
		bytes, ok := shader_read_file(fmt.tprintf("%v/%v", p.shader_dir, file), p.allocator, SHADER_HEADER_SIZE + SHADER_METADATA_LIMIT + SHADER_PAYLOAD_LIMIT)
		if !ok { return }
		matches := shader_hash_text(bytes) == shader_text(a["sha256"])
		delete(bytes, p.allocator)
		if !matches { return }
	}
	retry := false
	for &s in p.shaders.assets {
		if s.live && s.declared && !seen[s.name] {
			fmt.eprintfln("Shader %q declaration removed or renamed; rebuild the game and restart; keeping the last valid generation", s.name)
		}
	}
	for asset in assets {
		a := shader_object(asset); name := shader_text(a["asset"])
		requested := false
		for pack, names in p.shader_requests { if pack in p.loaded && slice.contains(names, name) { requested = true; break } }
		if !requested { continue }
		id, found := shader_table_find(&p.shaders, name)
		active: ^Shader
		if found { active, _ = shader_lookup(&p.shaders, id); active.declared = true }
		if active != nil && shader_hash_text(active.package_data.bytes) == shader_text(a["sha256"]) { continue }
		if shader_table_full(&p.shaders) {
			key := fmt.tprintf("reload:%v", name)
			if key not_in p.logged_full {
				p.logged_full[strings.clone(key, p.allocator)] = {}
				fmt.eprintfln("Shader %q reload staging capacity exhausted; keeping the last valid generation and retrying", name)
			}
			retry = true; continue
		}
		bytes, ok := shader_read_file(fmt.tprintf("%v/%v", p.shader_dir, shader_text(a["file"])), p.allocator, SHADER_HEADER_SIZE + SHADER_METADATA_LIMIT + SHADER_PAYLOAD_LIMIT)
		if !ok { return }
		if shader_hash_text(bytes) != shader_text(a["sha256"]) { delete(bytes, p.allocator); return }
		slot, reason := shader_candidate_stage(&p.shaders, name, bytes, active)
		if slot == 0 {
			delete(bytes, p.allocator)
			fmt.eprintfln("Shader %q reload rejected: %v; keeping the last valid generation", name, reason)
			continue
		}
		if !shader_candidate_validate(&p.shaders, &p.shaders.assets[slot], active) {
			shader_candidate_destroy(&p.shaders, slot)
			fmt.eprintfln("Shader %q reload GPU or pipeline validation failed; keeping the last valid generation", name)
			continue
		}
		id = shader_candidate_publish(&p.shaders, slot, mesh_slot(id) if found else 0)
		published, _ := shader_lookup(&p.shaders, id); published.declared = true
		packs_shader_hold_requests(p, name, id)
		fmt.eprintfln("Shader %q reloaded", name)
	}
	if !retry { p.shader_revision = revision; p.shader_revision_set = true }
}

packs_shader_hold_requests :: proc(p: ^Packs, name: string, id: u32) {
	asset := Held_Asset{.Shader, id}
	for pack, names in p.shader_requests {
		held, loaded := p.loaded[pack]
		if !loaded || !slice.contains(names, name) || slice.contains(held, asset) { continue }
		replacement := make([]Held_Asset, len(held)+1, p.allocator)
		copy(replacement, held); replacement[len(held)] = asset
		p.loaded[pack] = replacement
		delete(held, p.allocator)
		p.shaders.refs[mesh_slot(id)] += 1
	}
}
