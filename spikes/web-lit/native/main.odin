// The native side of the web lit slice: an Odin twin that draws the slice
// Scene through the real engine. Run it with ROCCO_BRIDGE and take frame N
// with the Bridge screenshot op. See spikes/web-lit/README.md.
package web_lit_native

import engine "slice:engine"
import scene "spike:scene"

TWIN :: engine.Game_Calls {
	launch     = twin_launch,
	init       = twin_init,
	step       = twin_step,
	loaded     = twin_loaded,
	view       = twin_view,
	drop_model = twin_drop_model,
}

Model :: struct {
	meshes: scene.Meshes,
}

main :: proc() {
	engine.run(TWIN)
}

// The seam treats the Model as a Roc box, so it keeps a refcount in front.
box_refcount :: proc(box: rawptr) -> ^int {
	return (^int)(uintptr(box) - size_of(int))
}

twin_launch :: proc(config: engine.Config) -> engine.Launch {
	engine.roc_decref(config)
	return scene.launch()
}

twin_init :: proc(config: engine.Config) -> engine.Init_Result {
	engine.roc_decref(config)
	base := engine.roc_alloc(size_of(int) + size_of(Model), align_of(Model))
	box := rawptr(uintptr(base) + size_of(int))
	box_refcount(box)^ = 1
	(^Model)(box)^ = {}
	commands := [2]engine.Command{load(scene.PROPS, scene.PROP_ASSETS[:]), load(scene.SURFACES, scene.SURFACE_ASSETS[:])}
	return {model = box, commands = engine.roc_list_from_slice(commands[:])}
}

load :: proc(pack: string, assets: []string) -> engine.Command {
	return {tag = .Load, payload = {load = {pack = engine.roc_str_from_slice(pack), assets = engine.roc_str_list_make(assets)}}}
}

twin_step :: proc(model: rawptr, input: engine.Input, results: engine.Query_Results, dt: f32) -> engine.Step_Result {
	engine.roc_decref(input)
	engine.roc_decref(results)
	return {model = model}
}

twin_loaded :: proc(model: rawptr, pack: engine.Roc_Str, manifest: engine.Roc_List(engine.Manifest_Entry)) -> rawptr {
	m := (^Model)(model)
	for &entry in manifest.elements[:manifest.length] {
		line := engine.Manifest_Line{name = engine.roc_str_string(&entry.name), id = entry.id}
		scene.meshes_from(&m.meshes, {line})
	}
	engine.roc_decref(pack)
	engine.roc_list_decref(manifest)
	return model
}

// view consumes one reference, as the Roc view does.
twin_view :: proc(model: rawptr) -> engine.Scene {
	s := scene.view((^Model)(model).meshes)
	box_refcount(model)^ -= 1
	return s
}

twin_drop_model :: proc(model: rawptr) {
	rc := box_refcount(model)
	rc^ -= 1
	if rc^ > 0 {
		return
	}
	engine.roc_dealloc(rawptr(uintptr(model) - size_of(int)), align_of(Model))
}
