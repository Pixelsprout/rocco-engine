Camera := [].{
    Vec3 : { x : F32, y : F32, z : F32 }
    View : { eye : Vec3, target : Vec3, fov_y : F32 }

    # 60 degrees, in radians.
    default_fov_y : F32
    default_fov_y = 1.047

    look_at : Vec3, Vec3 -> View
    look_at = |eye, target| { eye, target, fov_y: default_fov_y }

    # The eye sits at target + offset.
    follow : Vec3, Vec3 -> View
    follow = |target, offset| {
        eye: { x: target.x + offset.x, y: target.y + offset.y, z: target.z + offset.z },
        target,
        fov_y: default_fov_y,
    }
}

expect {
    view = Camera.look_at({ x: 0.0, y: 8.0, z: 8.0 }, { x: 1.0, y: 0.0, z: 0.0 })
    view.eye.y == 8.0 and view.target.x == 1.0 and view.fov_y == Camera.default_fov_y
}

expect {
    view = Camera.follow({ x: 1.0, y: 0.0, z: -2.0 }, { x: 0.0, y: 8.0, z: 8.0 })
    view.eye.x == 1.0 and view.eye.y == 8.0 and view.eye.z == 6.0 and view.target.z == -2.0
}
