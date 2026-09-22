app [init, step] { roc: "nightly-2026-09-12-220fd47", pf: platform "platform/main.roc" }

Body : { v : F32, x : F32, x_prev : F32, mass : F64 }
State : { bodies : List(Body), frame : U64 }

track : F32
track = 5.0

init : U64 -> State
init = |n| {
    var $bodies = List.with_capacity(n)
    var $i = 0

    while $i < n {
        $bodies = List.append($bodies, { v: 4.0 + $i.to_f32(), x: 0.0, x_prev: 0.0, mass: 1.0 })
        $i = $i + 1
    }
    { bodies: $bodies, frame: 0 }
}

step : State, F32 -> State
step = |state, dt| {
    next = List.map_with_index(state.bodies, |b, i| {
        limit = track - i.to_f32()
        nx = b.x + b.v * dt

        if nx > limit or nx < -limit {
            clamped = if nx > limit { limit } else { -limit }
            { v: -b.v, x: clamped, x_prev: b.x, mass: b.mass}
        } else {
            { v: b.v, x: nx, x_prev: b.x, mass: b.mass}
        }
    })
    { bodies: next, frame: state.frame + 1 }
}
