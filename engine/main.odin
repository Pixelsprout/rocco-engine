package engine

import "core:mem"
import "system"

TRACK_ALLOC :: #config(ROCCO_TRACK_ALLOC, false)

// Only the TRACK_ALLOC code uses mem, so -vet needs this when it is off.
_ :: mem

ROC_GAME :: Game_Calls {
	launch     = roc_game_launch,
	init       = roc_game_init,
	step       = roc_game_step,
	loaded     = roc_game_loaded,
	view       = roc_game_view,
	drop_model = roc_game_drop_model,
}

when TRACK_ALLOC {
	g_track: mem.Tracking_Allocator
}

main :: proc() {
	run(ROC_GAME)
	// The Windows host links with -no-crt, and Odin's no-CRT entry point
	// returns without ExitProcess. Windows then keeps the process alive until
	// the D3D11 driver threads end, about two minutes. system.exit ends it now.
	system.exit(0)
}

// An Odin twin calls run from its own main package with its own Game calls.
run :: proc(calls: Game_Calls) {
	when TRACK_ALLOC {
		mem.tracking_allocator_init(&g_track, context.allocator)
		context.allocator = mem.tracking_allocator(&g_track)
	}

	if err := app_run(calls); err != nil {
		system.eprintfln("engine failed to start: %v", err)
		return
	}
}

@(private = "file")
roc_game_launch :: proc(config: Config) -> Launch {return roc_launch(config)}

@(private = "file")
roc_game_init :: proc(config: Config) -> Init_Result {return roc_init(config)}

@(private = "file")
roc_game_step :: proc(model: rawptr, input: Input, results: Query_Results, dt: f32) -> Step_Result {
	return roc_step(model, input, results, dt)
}

@(private = "file")
roc_game_loaded :: proc(model: rawptr, pack: Roc_Str, manifest: Roc_List(Manifest_Entry)) -> rawptr {
	return roc_loaded(model, pack, manifest)
}

@(private = "file")
roc_game_view :: proc(model: rawptr) -> Scene {return roc_view(model)}

@(private = "file")
roc_game_drop_model :: proc(model: rawptr) {roc_drop_model(model)}
