platform ""
	requires {
		[Model : model] for init : Vocabulary.Config -> { model : model, commands : List(Vocabulary.Command) },
		step : Model, Vocabulary.Input, List(Vocabulary.Contact), F32 -> { model : Model, commands : List(Vocabulary.Command) },
		loaded : Model, Str, Vocabulary.Manifest -> Model,
		view : Model -> Vocabulary.Scene
	}
	exposes [Vocabulary, Key, Collider, Light]
	packages { roc: "nightly-2026-10-11-7d256b9" }
	provides {
		"roc_init": init_for_host,
		"roc_step": step_for_host,
		"roc_loaded": loaded_for_host,
		"roc_view": view_for_host,
		"roc_drop_model": drop_model_for_host,
	}
	targets: {
		inputs_dir: "targets/",
		arm64mac: { inputs: ["libhost.a", "sokol_app.a", "sokol_gfx.a", "sokol_glue.a", "sokol_log.a", "clay.a", "libclang_rt.osx.a", app] },
		x64glibc: { inputs: ["Scrt1.o", "crti.o", "libhost.a", "sokol_app.a", "sokol_gfx.a", "sokol_glue.a", "sokol_log.a", "clay.a", app, "libX11.so.6", "libXi.so.6", "libXcursor.so.1", "libGL.so.1", "libc.so.6", "libm.so.6", "crtn.o"] },
		x64win: { inputs: ["host.lib", "sokol_app.lib", "sokol_gfx.lib", "sokol_glue.lib", "sokol_log.lib", app, "kernel32.lib", "user32.lib", "gdi32.lib", "shell32.lib", "ole32.lib", "d3d11.lib", "dxgi.lib"] },
	}

import Vocabulary exposing [Command, Config, Contact, Input, Manifest, Scene]

# Only here because every exposes entry needs a matching import.
import Key
import Collider
import Light

# Model is whatever the app declares under that name. The host holds it as
# one pointer and never reads inside. The host keeps exactly one reference,
# so Roc owns the Model uniquely and step mutates it in place. Interpolation
# happens in the host between two Scenes, paired by draw id; Roc never sees
# a previous Model or an alpha.
init_for_host : Config -> { model : Box(Model), commands : List(Command) }
init_for_host = |config| {
	started = init(config)
	{ model: Box.box(started.model), commands: started.commands }
}

step_for_host : Box(Model), Input, List(Contact), F32 -> { model : Box(Model), commands : List(Command) }
step_for_host = |boxed, input, contacts, dt| {
	stepped = step(Box.unbox(boxed), input, contacts, dt)
	{ model: Box.box(stepped.model), commands: stepped.commands }
}

loaded_for_host : Box(Model), Str, Manifest -> Box(Model)
loaded_for_host = |boxed, pack, manifest| Box.box(loaded(Box.unbox(boxed), pack, manifest))

view_for_host : Box(Model) -> Scene
view_for_host = |boxed| view(Box.unbox(boxed))

# The host cannot free the Model, because only the compiler knows its layout.
# Dropping the box here frees it and everything inside. Remove this export
# when the glue can emit a payload drop for Box(Model).
drop_model_for_host : Box(Model) -> {}
drop_model_for_host = |_boxed| {}
