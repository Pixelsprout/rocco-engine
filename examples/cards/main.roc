app [init, step, view] { roc: "nightly-2026-09-27-a3ce7f1", pf: platform "../../platform/main.roc", cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Config, Contact, Input, Scene]
import pf.Key

# A second game on the same platform. No entities and no positions in the Model.
Card : [Ace, King, Number(U8)]
Model : { hand : List(Card), turns : U64, name : Str, card_mesh : U32 }

init : Config -> Model
init = |config| {
    # A plane until a card mesh is loaded from disk. Then Mesh.resolve(config, "card").
    { hand: [Ace, Number(7)], turns: 0, name: "solitaire", card_mesh: Mesh.primitive(config, Plane) }
}

step : Model, Input, List(Contact), F32 -> Model
step = |m, input, _contacts, _dt|
    if Key.pressed(input, Space) {
        { ..m, hand: List.append(m.hand, King), turns: m.turns + 1 }
    } else {
        m
    }

view : Model -> Scene
view = |m| {
    draws = List.map_with_index(m.hand, |card, i| {
        tint = match card {
            Ace => { r: 1.0, g: 0.787, b: 0.033 }
            King => { r: 0.604, g: 0.033, b: 0.033 }
            Number(_) => { r: 0.787, g: 0.787, b: 0.787 }
        }
        # The slot index is the draw id: a card slides to its slot when dealt.
        { id: i, mesh: m.card_mesh, pos: { x: i.to_f32() * 1.2, y: 0.0, z: 0.0 }, scale: { x: 1.0, y: 1.0, z: 1.4 }, yaw: 0.0, tint }
    })
    { camera: Cam.look_at({ x: 0.0, y: 8.0, z: 8.0 }, { x: 0.0, y: 0.0, z: 0.0 }), draws, colliders: [] }
}

expect {
    press = { held: [], pressed: [Key.code(Space)], mouse: { dx: 0.0, dy: 0.0 } }
    after = step(init({ seed: 0, meshes: [{ name: "primitive/plane", id: 7 }] }), press, [], 0.1)
    List.len(after.hand) == 3 and after.turns == 1 and after.card_mesh == 7
}
