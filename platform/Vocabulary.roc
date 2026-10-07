# The types that cross the seam; see CONTEXT.md. Nothing in them names a game.
# Key codes are sokol's; pf.Key names them. Mesh ids come from the manifest
# in Config. An id the engine does not know draws the fallback mesh. Collider
# kinds are numbers because the glue has no tag unions; pf.Collider names them.
Vocabulary := [].{
    Vec3 : { x : F32, y : F32, z : F32 }
    Rgb : { r : F32, g : F32, b : F32 }
    Config : { seed : U64, meshes : List({ name : Str, id : U32 }) }
    Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }
    Camera : { eye : Vec3, target : Vec3, fov_y : F32 }
    Draw : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, yaw : F32, tint : Rgb }
    Collider : { id : U64, kind : U8, pos : Vec3, yaw : F32, extent : Vec3 }
    Contact : { a : U64, b : U64, normal : Vec3, depth : F32 }
    Scene : { camera : Camera, draws : List(Draw), colliders : List(Collider) }
}
