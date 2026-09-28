platform ""
    requires {} {
        [Model: model] for init : Vocabulary.Config -> model,
        step : Model, Vocabulary.Input, F32 -> Model,
        view : Model -> Vocabulary.Scene,
    }
    exposes [Vocabulary, Key]
    packages { roc: "nightly-2026-09-12-220fd47" }
    provides {
        "roc_init": init_for_host,
        "roc_step": step_for_host,
        "roc_view": view_for_host,
        "roc_drop_model": drop_model_for_host,
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
        x64glibc: { inputs: [
            "Scrt1.o",
            "crti.o",
            "libhost.a",
            "sokol_app_linux_x64_gl_debug.a",
            "sokol_gfx_linux_x64_gl_debug.a",
            "sokol_glue_linux_x64_gl_debug.a",
            "sokol_log_linux_x64_gl_debug.a",
            app,
            "libX11.so.6",
            "libXi.so.6",
            "libXcursor.so.1",
            "libGL.so.1",
            "libc.so.6",
            "libm.so.6",
            "crtn.o",
        ] },
        x64win: { inputs: [
            "host.lib",
            "sokol_app_windows_x64_d3d11_debug.lib",
            "sokol_gfx_windows_x64_d3d11_debug.lib",
            "sokol_glue_windows_x64_d3d11_debug.lib",
            "sokol_log_windows_x64_d3d11_debug.lib",
            app,
            "kernel32.lib",
            "user32.lib",
            "gdi32.lib",
            "shell32.lib",
            "ole32.lib",
            "d3d11.lib",
            "dxgi.lib",
        ] },
    }

import Vocabulary exposing [Config, Input, Scene]

# Only here because every exposes entry needs a matching import.
import Key

# Model is whatever the app declares under that name. The host holds it as
# one pointer and never reads inside. The host keeps exactly one reference,
# so Roc owns the Model uniquely and step mutates it in place. Interpolation
# happens in the host between two Scenes, paired by draw id; Roc never sees
# a previous Model or an alpha.
init_for_host : Config -> Box(Model)
init_for_host = |config| Box.box(init(config))

step_for_host : Box(Model), Input, F32 -> Box(Model)
step_for_host = |boxed, input, dt| Box.box(step(Box.unbox(boxed), input, dt))

view_for_host : Box(Model) -> Scene
view_for_host = |boxed| view(Box.unbox(boxed))

# The host cannot free the Model, because only the compiler knows its layout.
# Dropping the box here frees it and everything inside. Remove this export
# when the glue can emit a payload drop for Box(Model).
drop_model_for_host : Box(Model) -> {}
drop_model_for_host = |_boxed| {}
