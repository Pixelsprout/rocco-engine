platform ""
	requires {
		[Model : model] for init : Str -> model,
		step : Model, U64 -> { model : Model, line : Str }
	}
	exposes []
	packages { roc: "nightly-2026-11-04-2622062" }
	provides {
		"roc_init": init_for_host,
		"roc_step": step_for_host,
	}
	targets: {
		inputs_dir: "targets/",
		wasm32: {
			inputs: ["host.o", app],
			exports: ["__wasm_call_ctors", "main", "__indirect_function_table", "fflush", "emscripten_stack_get_end", "emscripten_stack_get_base", "strerror", "setThrew", "emscripten_stack_init", "emscripten_stack_get_free", "_emscripten_stack_restore", "_emscripten_stack_alloc", "emscripten_stack_get_current"],
		},
	}

init_for_host : Str -> Box(Model)
init_for_host = |text| Box.box(init(text))

step_for_host : Box(Model), U64 -> { model : Box(Model), line : Str }
step_for_host = |boxed, step_number| {
	stepped = step(Box.unbox(boxed), step_number)
	{ model: Box.box(stepped.model), line: stepped.line }
}
