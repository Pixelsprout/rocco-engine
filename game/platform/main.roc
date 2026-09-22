platform ""
    requires {} {
        init: U64 -> { bodies : List({ v : F32, x : F32, x_prev: F32, mass: F64}), frame: U64 },
        step: { bodies : List({ v : F32, x : F32, x_prev : F32, mass: F64 }), frame : U64 }, F32 -> { bodies : List({ v : F32, x : F32, x_prev : F32, mass: F64 }), frame : U64 },
    }
    exposes []
    packages { roc: "nightly-2026-09-12-220fd47" }
    provides {
        "roc_init": init_for_host,
        "roc_step": step_for_host,
    }
    targets: {
        inputs_dir: "targets/",
        arm64mac: { inputs: [
            "libhost.a",
            "sokol_app_macos_arm64_metal_debug.a",
            "sokol_gfx_macos_arm64_metal_debug.a",
            "sokol_glue_macos_arm64_metal_debug.a",
            "sokol_log_macos_arm64_metal_debug.a",
            "libclang_rt.osx.a",
            app,
        ] },
    }

Body : { v : F32, x : F32, x_prev : F32, mass: F64 }
State : { bodies: List(Body), frame : U64 }

init_for_host : U64 -> State
init_for_host = |n| init(n)

step_for_host : State, F32 -> State
step_for_host = |state, dt| step(state, dt)
