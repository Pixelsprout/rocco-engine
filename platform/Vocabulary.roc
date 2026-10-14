# The types that cross the seam; see CONTEXT.md. Nothing in them names a game.
# Key codes are sokol's; pf.Key names them. Config names the assets on disk
# with no ids. Mesh ids come from the Manifest that loaded gets after a Load.
# An id the engine does not know draws the fallback mesh. A Box
# shape carries its half extents. A Light colour carries its intensity and
# can exceed 1. A Directional dir is the way the light travels.
Vocabulary := [].{
    Vec3 : { x : F32, y : F32, z : F32 }
    Quat : { x : F32, y : F32, z : F32, w : F32 }
    Rgb : { r : F32, g : F32, b : F32 }
    Config : { seed : U64, assets : List(Str) }
    Manifest : List({ name : Str, id : U32 })
    Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }
    Camera : { eye : Vec3, target : Vec3, up : Vec3, fov_y : F32 }
    Draw : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, rot : Quat, scale_rot : Quat, tint : Rgb }
    Collider : { id : U64, pos : Vec3, yaw : F32, shape : [Box(Vec3), Sphere(F32), Capsule({ radius : F32, half_height : F32 })] }
    Contact : { a : U64, b : U64, normal : Vec3, depth : F32 }
    Light : [Ambient(Rgb), Directional({ dir : Vec3, color : Rgb }), Point({ pos : Vec3, color : Rgb, range : F32 })]
    Scene : { camera : Camera, draws : List(Draw), colliders : List(Collider), lights : List(Light), cursor : Cursor }
    Cursor : [Free, Locked]
    Command : [Quit, Load({ pack : Str, assets : List(Str) }), Unload(Str)]
}
