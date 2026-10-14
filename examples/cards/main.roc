app [init, step, loaded, view] { roc: "nightly-2026-09-27-a3ce7f1", pf: platform "../../platform/main.roc", cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", linalg: "../../packages/linalg/main.roc" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import linalg.Quat
import pf.Vocabulary exposing [Command, Config, Contact, Input, Manifest, Scene]
import pf.Key
import pf.Light

# A second game on the same platform. No entities and no positions in the Model.
Card : [Ace, King, Number(U8)]
Model : { hand : List(Card), turns : U64, name : Str, card_mesh : U32 }

# A plane until a card mesh is on disk. Asking only for names in Config keeps a missing card out of the log.
init : Config -> { model : Model, commands : List(Command) }
init = |config| {
    assets = if config.assets.contains("card") { ["card"] } else { [] }
    model = { hand: [Ace, Number(7)], turns: 0, name: "solitaire", card_mesh: Mesh.primitive(Plane) }
    { model, commands: [Load({ pack: "cards", assets })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, manifest| match List.find_first(manifest, |entry| entry.name == "card") {
    Ok(entry) => { ..m, card_mesh: entry.id }
    Err(NotFound) => m
}

update : Model, Input, List(Contact), F32 -> Model
update = |m, input, _contacts, _dt|
    if Key.pressed(input, Space) {
        { ..m, hand: List.append(m.hand, King), turns: m.turns + 1 }
    } else {
        m
    }

step : Model, Input, List(Contact), F32 -> { model : Model, commands : List(Command) }
step = |m, input, contacts, dt| { model: update(m, input, contacts, dt), commands: [] }

# The BRDF divides diffuse light by pi, so 5.03 (1.6 pi) lights a white surface facing it to 1.6.
lights : List(Vocabulary.Light)
lights = [
    Light.ambient({ r: 0.2, g: 0.2, b: 0.2 }),
    Light.directional({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 }),
]

view : Model -> Scene
view = |m| {
    draws = List.map_with_index(m.hand, |card, i| {
        tint = match card {
            Ace => { r: 1.0, g: 0.787, b: 0.033 }
            King => { r: 0.604, g: 0.033, b: 0.033 }
            Number(_) => { r: 0.787, g: 0.787, b: 0.787 }
        }
        # The slot index is the draw id: a card slides to its slot when dealt.
        { id: i, mesh: m.card_mesh, pos: { x: i.to_f32() * 1.2, y: 0.0, z: 0.0 }, scale: { x: 1.0, y: 1.0, z: 1.4 }, rot: Quat.identity, scale_rot: Quat.identity, tint }
    })
    { camera: Cam.look_at({ x: 0.0, y: 8.0, z: 8.0 }, { x: 0.0, y: 0.0, z: 0.0 }), draws, colliders: [], lights, cursor: Free }
}

expect {
    press = { held: [], pressed: [Key.code(Space)], mouse: { dx: 0.0, dy: 0.0 } }
    after = update(init({ seed: 0, assets: [] }).model, press, [], 0.1)
    List.len(after.hand) == 3 and after.turns == 1 and after.card_mesh == Mesh.primitive(Plane)
}

expect init({ seed: 0, assets: [] }).commands == [Load({ pack: "cards", assets: [] })]
expect init({ seed: 0, assets: ["card"] }).commands == [Load({ pack: "cards", assets: ["card"] })]
expect loaded(init({ seed: 0, assets: ["card"] }).model, "cards", [{ name: "card", id: 4 }]).card_mesh == 4
expect loaded(init({ seed: 0, assets: [] }).model, "cards", []).card_mesh == Mesh.primitive(Plane)
