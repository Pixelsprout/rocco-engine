platform ""
    requires {} {
        [Model: model] for init : { seed : U64, meshes : List({ name : Str, id : U32 }) } -> model,
        step : Model, { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }, F32 -> Model,
        view : Model -> { camera : { eye : { x : F32, y : F32, z : F32 }, target : { x : F32, y : F32, z : F32 }, fov_y : F32 }, draws : List({ id : U64, mesh : U32, pos : { x : F32, y : F32, z : F32 }, scale : { x : F32, y : F32, z : F32 }, yaw : F32, tint : { x : F32, y : F32, z : F32 } }) },
    }
    exposes []
    packages { roc: "nightly-2026-09-12-220fd47" }
    provides {
        "roc_init": init_for_host,
        "roc_step": step_for_host,
        "roc_view": view_for_host,
    }

# The engine's vocabulary. Every game speaks these three types and nothing
# in them names a game. Key codes are sokol's: SPACE = 32, A = 65, W = 87.
# Mesh ids come from the manifest in Config: the engine loads every asset it
# finds at startup, plus its own primitives, and names them here once. An id
# the engine does not know draws the fallback mesh.
Vec3 : { x : F32, y : F32, z : F32 }
Config : { seed : U64, meshes : List({ name : Str, id : U32 }) }
Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }
Camera : { eye : Vec3, target : Vec3, fov_y : F32 }
Scene : { camera : Camera, draws : List({ id : U64, mesh : U32, pos : Vec3, scale : Vec3, yaw : F32, tint : Vec3 }) }

# Model is whatever the app declares under that name. The host holds it as
# one pointer and never reads inside. The host keeps exactly one reference,
# so Roc owns the Model uniquely and step mutates it in place. Interpolation
# happens in the host between two Scenes, paired by draw id; Roc never sees
# a previous Model or an alpha.
init_for_host : Config -> Box(Model)
init_for_host = |config| Box.box(init(config))

step_for_host : Box(Model), Input, F32 -> Box(Model)
step_for_host = |boxed, input, dt| Box.box(step(Box.unbox(boxed), input, dt))

view_for_host : Box(Model) -> { camera : { eye : { x : F32, y : F32, z : F32 }, target : { x : F32, y : F32, z : F32 }, fov_y : F32 }, draws : List({ id : U64, mesh : U32, pos : { x : F32, y : F32, z : F32 }, scale : { x : F32, y : F32, z : F32 }, yaw : F32, tint : { x : F32, y : F32, z : F32 } }) }
view_for_host = |boxed| view(Box.unbox(boxed))
