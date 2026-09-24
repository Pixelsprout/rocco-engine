app [init, step, view] { roc: "nightly-2026-09-12-220fd47", pf: platform "../../platform/main.roc", cam: "../../packages/camera/main.roc" }

import cam.Camera as Cam

# A second game on the same platform. No entities and no positions in the Model.
Vec3 : { x : F32, y : F32, z : F32 }
Rgb : { r : F32, g : F32, b : F32 }
Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }
Draw : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, yaw : F32, tint : Rgb }
Scene : { camera : Cam.View, draws : List(Draw) }
Config : { seed : U64, meshes : List({ name : Str, id : U32 }) }

Card : [Ace, King, Number(U8)]
Model : { hand : List(Card), turns : U64, name : Str, card_mesh : U32 }

key_space : U16
key_space = 32

init : Config -> Model
init = |config| {
    # A Blender export would be named here exactly like a primitive.
    card_mesh = match List.find_first(config.meshes, |m| m.name == "card") {
        Ok(m) => m.id
        Err(NotFound) => 0
    }
    { hand: [Ace, Number(7)], turns: 0, name: "solitaire", card_mesh }
}

step : Model, Input, F32 -> Model
step = |m, input, _dt|
    if List.contains(input.pressed, key_space) {
        { ..m, hand: List.append(m.hand, King), turns: m.turns + 1 }
    } else {
        m
    }

view : Model -> Scene
view = |m| {
    draws = List.map_with_index(m.hand, |card, i| {
        tint = match card {
            Ace => { r: 1.0, g: 0.9, b: 0.2 }
            King => { r: 0.8, g: 0.2, b: 0.2 }
            Number(_) => { r: 0.9, g: 0.9, b: 0.9 }
        }
        # The slot index is the draw id: a card slides to its slot when dealt.
        { id: i, mesh: m.card_mesh, pos: { x: i.to_f32() * 1.2, y: 0.0, z: 0.0 }, scale: { x: 1.0, y: 0.05, z: 1.4 }, yaw: 0.0, tint }
    })
    { camera: Cam.look_at({ x: 0.0, y: 8.0, z: 8.0 }, { x: 0.0, y: 0.0, z: 0.0 }), draws }
}

expect {
    press = { held: [], pressed: [key_space], mouse: { dx: 0.0, dy: 0.0 } }
    after = step(init({ seed: 0, meshes: [{ name: "card", id: 7 }] }), press, 0.1)
    List.len(after.hand) == 3 and after.turns == 1 and after.card_mesh == 7
}
