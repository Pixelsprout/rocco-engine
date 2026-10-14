import Vec3

Quat := [].{
    Quat : { x : F32, y : F32, z : F32, w : F32 }

    identity : Quat.Quat
    identity = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 }

    # Turns about +y the way the host turns a Draw, so +z goes to (sin, 0, cos).
    from_yaw : F32 -> Quat.Quat
    from_yaw = |yaw| from_axis_angle({ x: 0.0, y: 1.0, z: 0.0 }, yaw)

    from_axis_angle : Vec3.Vec3, F32 -> Quat.Quat
    from_axis_angle = |axis, angle| {
        half = angle / 2.0
        s = half.sin()
        n = Vec3.normalize(axis)
        { x: n.x * s, y: n.y * s, z: n.z * s, w: half.cos() }
    }

    # The Hamilton product, the same as Odin's a * b: the result applies b first, then a.
    mul : Quat.Quat, Quat.Quat -> Quat.Quat
    mul = |a, b| {
        x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    }

    # The inverse of a unit quaternion.
    conjugate : Quat.Quat -> Quat.Quat
    conjugate = |q| { x: -q.x, y: -q.y, z: -q.z, w: q.w }

    # The shortest turn that sends a to b. Both must be unit length.
    between : Vec3.Vec3, Vec3.Vec3 -> Quat.Quat
    between = |a, b| {
        w = 1.0 + Vec3.dot(a, b)
        if w < 0.000001 {
            side = if a.x.abs() < 0.9 { { x: 1.0, y: 0.0, z: 0.0 } } else { { x: 0.0, y: 0.0, z: 1.0 } }
            axis = Vec3.normalize(Vec3.cross(a, side))
            { x: axis.x, y: axis.y, z: axis.z, w: 0.0 }
        } else {
            c = Vec3.cross(a, b)
            n = (c.x * c.x + c.y * c.y + c.z * c.z + w * w).sqrt()
            { x: c.x / n, y: c.y / n, z: c.z / n, w: w / n }
        }
    }

    # q must be unit length.
    rotate : Vec3.Vec3, Quat.Quat -> Vec3.Vec3
    rotate = |v, q| {
        u = { x: q.x, y: q.y, z: q.z }
        t = Vec3.scale(Vec3.cross(u, v), 2.0)
        Vec3.add(v, Vec3.add(Vec3.scale(t, q.w), Vec3.cross(u, t)))
    }
}

pi : F32
pi = 3.1415927

near : Vec3.Vec3, Vec3.Vec3 -> Bool
near = |a, b| Vec3.length(Vec3.sub(a, b)) < 0.0001

expect {
    v = { x: 1.0, y: 2.0, z: 3.0 }
    Quat.rotate(v, Quat.identity) == v
}

# Turning +z a quarter turn about +y gives +x.
expect near(Quat.rotate({ x: 0.0, y: 0.0, z: 1.0 }, Quat.from_yaw(pi / 2.0)), { x: 1.0, y: 0.0, z: 0.0 })

# The axis need not be unit length.
expect near(Quat.rotate({ x: 1.0, y: 0.0, z: 0.0 }, Quat.from_axis_angle({ x: 0.0, y: 0.0, z: 2.0 }, pi / 2.0)), { x: 0.0, y: 1.0, z: 0.0 })

# mul(a, b) applies b first. b turns +z to +x and a, about +x, keeps it.
# The other order sends +z to -y.
expect {
    a = Quat.from_axis_angle({ x: 1.0, y: 0.0, z: 0.0 }, pi / 2.0)
    b = Quat.from_yaw(pi / 2.0)
    near(Quat.rotate({ x: 0.0, y: 0.0, z: 1.0 }, Quat.mul(a, b)), { x: 1.0, y: 0.0, z: 0.0 })
}

# rotate matches the closed-form turn about +y.
expect {
    v = { x: 1.0, y: 2.0, z: 3.0 }
    yaw = 0.7
    c = yaw.cos()
    s = yaw.sin()
    near(Quat.rotate(v, Quat.from_yaw(yaw)), { x: v.x * c + v.z * s, y: v.y, z: v.z * c - v.x * s })
}

# The conjugate undoes the turn.
expect {
    q = Quat.from_axis_angle({ x: 1.0, y: 2.0, z: 3.0 }, 0.8)
    v = { x: 0.3, y: -1.0, z: 2.0 }
    near(Quat.rotate(Quat.rotate(v, q), Quat.conjugate(q)), v)
}

expect near(Quat.rotate({ x: 0.0, y: 1.0, z: 0.0 }, Quat.between({ x: 0.0, y: 1.0, z: 0.0 }, { x: 0.0, y: 0.0, z: -1.0 })), { x: 0.0, y: 0.0, z: -1.0 })

expect Quat.between({ x: 0.0, y: 1.0, z: 0.0 }, { x: 0.0, y: 1.0, z: 0.0 }) == Quat.identity

# Opposite vectors have no single axis. Any half turn that sends a to b will do.
expect {
    a = { x: 0.0, y: 1.0, z: 0.0 }
    near(Quat.rotate(a, Quat.between(a, Vec3.neg(a))), Vec3.neg(a))
}

expect {
    a = { x: 1.0, y: 0.0, z: 0.0 }
    near(Quat.rotate(a, Quat.between(a, Vec3.neg(a))), Vec3.neg(a))
}
