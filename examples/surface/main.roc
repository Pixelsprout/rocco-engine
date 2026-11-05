app [init, launch, loaded, step, view] { mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

import Foliage
import DefaultSurface
import Tree
import mesh.Mesh
import pf.Config
import pf.Draw
import pf.Key
import pf.Launch
import pf.Light
import pf.Material
import pf.Scene
import pf.Vocabulary

Model : { tree : U32, instances : Bool, red : Bool, casts_shadow : Bool, whole : Bool, builtin : Bool, default_shader : Bool, shader_loaded : Bool, broken : Bool, wind : F32 }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Surface", width: 800, height: 600, samples: Off }, shadow_cascades: 2, capacity: { ..Launch.default.capacity, draws: 64 } }

init : Vocabulary.Config -> { model : Model, commands : List(Vocabulary.Command) }
init = |config| {
	model = { tree: 0, instances: config.args.contains("--instances"), red: Bool.False, casts_shadow: !config.args.contains("--no-shadow"), whole: config.args.contains("--whole"), builtin: config.args.contains("--builtin"), default_shader: config.args.contains("--default-shader"), shader_loaded: Bool.True, broken: config.args.contains("--broken"), wind: if config.args.contains("--no-wind") 0.0 else 0.3 }
	{ model, commands: [Load({ pack: "trees", assets: ["tree"] }), Load({ pack: "surfaces", assets: shader_assets(model.broken) })] }
}

shader_assets : Bool -> List(Str)
shader_assets = |broken| if broken ["shader/Broken", "shader/DefaultSurface"] else ["shader/Foliage", "shader/DefaultSurface"]

loaded : Model, Str, Vocabulary.Manifest -> Model
loaded = |model, pack, manifest| if pack == "trees" { ..model, tree: Mesh.resolve(manifest, "tree") } else model

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Vocabulary.Command) }
step = |model, input, _results, _dt| {
	red = if Key.pressed(input, C) !model.red else model.red
	casts_shadow = if Key.pressed(input, N) !model.casts_shadow else model.casts_shadow
	shader_loaded = if Key.pressed(input, U) !model.shader_loaded else model.shader_loaded
	commands = if shader_loaded == model.shader_loaded [] else if shader_loaded [Load({ pack: "surfaces", assets: shader_assets(model.broken) })] else [Unload("surfaces")]
	{ model: { ..model, red, casts_shadow, shader_loaded }, commands }
}

view : Model -> Vocabulary.Scene
view = |model| {
	tint = if model.red { r: 4.0, g: 0.15, b: 0.1, a: 1.0 } else Foliage.material_default.leaf_tint
	base_values = Foliage.material("surfaces", { ..Foliage.material_default, leaf_tint: tint })
	values = if model.broken { ..base_values, shader: { pack: "surfaces", asset: "shader/Broken" } } else base_values
	material = if model.default_shader Material.surface(DefaultSurface.material("surfaces", DefaultSurface.material_default)) else if model.whole Material.surface(values) else Material.default
	materials = if model.whole or model.default_shader or model.builtin [] else [Tree.leaves("trees", values)]
	tree = { ..Draw.default, id: 10, mesh: model.tree, casts_shadow: model.casts_shadow, material, materials, shader_values: [Foliage.draw("surfaces", Foliage.draw_default)] }
	trees = if model.instances [
		Draw({ ..tree, pos: { x: -1.4, y: 0.0, z: 0.0 }, scale: { x: 0.8, y: 0.8, z: 0.8 } }),
		Draw({ ..tree, id: 11, pos: { x: 0.2, y: 0.0, z: -1.2 }, tint: { r: 0.7, g: 0.9, b: 0.8 } }),
		Draw({ ..tree, id: 12, pos: { x: 1.5, y: 0.0, z: 0.0 }, shader_values: [Foliage.draw("surfaces", { phase: 1.4 })] }),
	] else [Draw(tree)]
	ground = { ..Draw.default, id: 1, mesh: Mesh.primitive(Cube), pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 8.0, y: 0.2, z: 7.0 }, tint: { r: 0.4, g: 0.4, b: 0.35 } }
	{
		..Scene.empty,
		camera: { eye: { x: 4.0, y: 3.0, z: 6.0 }, target: { x: 0.0, y: 1.1, z: 0.0 }, up: { x: 0.0, y: 1.0, z: 0.0 }, fov_y: 0.8 },
		shader_values: [Foliage.scene("surfaces", { ..Foliage.scene_default, wind: model.wind })],
		nodes: List.join([[Light(Light.ambient({ r: 0.25, g: 0.3, b: 0.4 })), Light(Light.sun({ x: -0.5, y: -0.9, z: -0.4 }, { r: 3.0, g: 2.7, b: 2.3 })), Draw(ground)], trees]),
	}
}

expect init(Config.empty).commands == [Load({ pack: "trees", assets: ["tree"] }), Load({ pack: "surfaces", assets: ["shader/Foliage", "shader/DefaultSurface"] })]
expect view(init(Config.empty).model).shader_values.len() == 1
