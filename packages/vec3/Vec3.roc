Vec3 := [].{
    Vec3 : { x : F32, y : F32, z : F32 }

    zero : Vec3.Vec3
    zero = { x: 0.0, y: 0.0, z: 0.0 }

    one : Vec3.Vec3
    one = { x: 1.0, y: 1.0, z: 1.0 }

    add : Vec3.Vec3, Vec3.Vec3 -> Vec3.Vec3
    add = |a, b| { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }

    sub : Vec3.Vec3, Vec3.Vec3 -> Vec3.Vec3
    sub = |a, b| { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }

    neg : Vec3.Vec3 -> Vec3.Vec3
    neg = |v| { x: -v.x, y: -v.y, z: -v.z }

    scale : Vec3.Vec3, F32 -> Vec3.Vec3
    scale = |v, s| { x: v.x * s, y: v.y * s, z: v.z * s }

    dot : Vec3.Vec3, Vec3.Vec3 -> F32
    dot = |a, b| a.x * b.x + a.y * b.y + a.z * b.z

    cross : Vec3.Vec3, Vec3.Vec3 -> Vec3.Vec3
    cross = |a, b| {
        x: a.y * b.z - a.z * b.y,
        y: a.z * b.x - a.x * b.z,
        z: a.x * b.y - a.y * b.x,
    }

    length : Vec3.Vec3 -> F32
    length = |v| dot(v, v).sqrt()

    # Zero stays zero, so a caller never divides by a zero length.
    normalize : Vec3.Vec3 -> Vec3.Vec3
    normalize = |v| {
        len = length(v)
        if len == 0.0 {
            zero
        } else {
            scale(v, 1.0 / len)
        }
    }

    lerp : Vec3.Vec3, Vec3.Vec3, F32 -> Vec3.Vec3
    lerp = |a, b, t| add(a, scale(sub(b, a), t))
}

expect Vec3.zero == { x: 0.0, y: 0.0, z: 0.0 }

expect Vec3.one == { x: 1.0, y: 1.0, z: 1.0 }

expect Vec3.add({ x: 1.0, y: 2.0, z: 3.0 }, { x: 4.0, y: -5.0, z: 0.5 }) == { x: 5.0, y: -3.0, z: 3.5 }

expect Vec3.sub({ x: 1.0, y: 2.0, z: 3.0 }, { x: 4.0, y: -5.0, z: 0.5 }) == { x: -3.0, y: 7.0, z: 2.5 }

expect Vec3.neg({ x: 1.0, y: -2.0, z: 0.0 }) == { x: -1.0, y: 2.0, z: 0.0 }

expect Vec3.scale({ x: 1.0, y: -2.0, z: 3.0 }, 2.0) == { x: 2.0, y: -4.0, z: 6.0 }

expect Vec3.dot({ x: 1.0, y: 2.0, z: 3.0 }, { x: 4.0, y: -5.0, z: 6.0 }) == 12.0

# Right-handed: x cross y is z.
expect Vec3.cross({ x: 1.0, y: 0.0, z: 0.0 }, { x: 0.0, y: 1.0, z: 0.0 }) == { x: 0.0, y: 0.0, z: 1.0 }

expect Vec3.length({ x: 3.0, y: 0.0, z: 4.0 }) == 5.0

expect Vec3.normalize({ x: 0.0, y: 0.0, z: -4.0 }) == { x: 0.0, y: 0.0, z: -1.0 }

expect Vec3.normalize(Vec3.zero) == Vec3.zero

expect Vec3.lerp({ x: 0.0, y: 2.0, z: -4.0 }, { x: 4.0, y: 2.0, z: 4.0 }, 0.25) == { x: 1.0, y: 2.0, z: -2.0 }
