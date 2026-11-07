app [init, launch, loaded, step, view] {
	mesh: "../../packages/mesh/main.roc",
	pf: platform "../../platform/main.roc",
	roc: "nightly-2026-11-04-2622062",
}

import Foliage
import Outline
import Selection
import Tree
import mesh.Mesh
import pf.Draw
import pf.Environment
import pf.Key
import pf.Launch
import pf.Light
import pf.Material
import pf.Post
import pf.Scene
import pf.Vocabulary

Model : {
	tree : U32,
	wind : F32,
	selected : Bool,
	visible_only : Bool,
	casts_shadow : Bool,
	red : Bool,
	solid : Bool,
	occluder : Bool,
	shader_loaded : Bool,
	effect : [OutlineEffect, SelectionInputs, NoEffect],
}

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| {
	..Launch.default,
	window: {
		..Launch.default.window,
		title: "Shader authoring proof",
		width: 800,
		height: 600,
		high_dpi: Bool.False,
		samples: Off,
	},
	shadow_cascades: 2,
	capacity: { ..Launch.default.capacity, draws: 64 },
}

init : Vocabulary.Config -> { model : Model, commands : List(Vocabulary.Command) }
init = |config| {
	model: {
		tree: 0,
		wind: if (config.args.contains("--no-wind")) 0.0 else 0.2,
		selected: !config.args.contains("--no-selection"),
		visible_only: !config.args.contains("--through-wall"),
		casts_shadow: !config.args.contains("--no-shadow"),
		red: Bool.False,
		solid: config.args.contains("--solid"),
		occluder: !config.args.contains("--no-occluder"),
		shader_loaded: Bool.True,
		effect: if (config.args.contains("--selection")) SelectionInputs else if (config.args.contains("--empty")) NoEffect else OutlineEffect,
	},
	commands: [
		Load({ pack: "trees", assets: ["tree"] }),
		Load({ pack: "shaders", assets: ["shader/Foliage", "shader/Outline", "shader/Selection"] }),
	],
}

loaded : Model, Str, Vocabulary.Manifest -> Model
loaded = |model, pack, manifest| if (pack == "trees") { ..model, tree: Mesh.resolve(manifest, "tree") } else model

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Vocabulary.Command) }
step = |model, input, _results, _dt| {
	shader_loaded = if (Key.pressed(input, U)) !model.shader_loaded else model.shader_loaded
	commands = if (shader_loaded == model.shader_loaded) [] else if (shader_loaded) [Load({ pack: "shaders", assets: ["shader/Foliage", "shader/Outline", "shader/Selection"] })] else [Unload("shaders")]
	{
		model: {
			..model,
			shader_loaded,
			red: if (Key.pressed(input, C)) !model.red else model.red,
			casts_shadow: if (Key.pressed(input, N)) !model.casts_shadow else model.casts_shadow,
			selected: if (Key.pressed(input, S)) !model.selected else model.selected,
			visible_only: if (Key.pressed(input, V)) !model.visible_only else model.visible_only,
		},
		commands,
	}
}

view : Model -> Vocabulary.Scene
view = |model| {
	leaf_tint = if (model.red) { r: 4.0, g: 0.15, b: 0.1, a: 1.0 } else Foliage.material_default.leaf_tint
	tree = {
		..Draw.default,
		id: 10,
		mesh: model.tree,
		casts_shadow: model.casts_shadow,
		material: { ..Material.default, properties: if (model.solid) [Alpha(Opaque)] else [] },
		materials: [Tree.leaves("trees", Foliage.material("shaders", { ..Foliage.material_default, leaf_tint }))],
		shader_values: [Foliage.draw("shaders", Foliage.draw_default)],
	}
	marker = {
		..Draw.default,
		id: 11,
		mesh: Mesh.primitive(Cube),
		casts_shadow: Bool.False,
		pos: { x: -0.65, y: 0.3, z: 0.0 },
		scale: { x: 0.8, y: 0.6, z: 0.6 },
		tint: { r: 0.55, g: 0.3, b: 0.12 },
	}
	ground = {
		..Draw.default,
		id: 1,
		mesh: Mesh.primitive(Cube),
		pos: { x: 0.0, y: -0.1, z: 0.0 },
		scale: { x: 8.0, y: 0.2, z: 7.0 },
		tint: { r: 0.4, g: 0.4, b: 0.35 },
	}
	wall = {
		..Draw.default,
		id: 2,
		mesh: Mesh.primitive(Cube),
		casts_shadow: Bool.False,
		pos: { x: -0.35, y: 1.2, z: 0.8 },
		scale: { x: 0.5, y: 2.4, z: 0.2 },
		tint: { r: 0.15, g: 0.22, b: 0.5 },
	}
	effects = match model.effect {
		OutlineEffect => [Post.before_bloom(Outline.draw("shaders", { ..Outline.draw_default, visible_only: model.visible_only }))]
		SelectionInputs => [Post.after_tone_map(Selection.draw("shaders", Selection.draw_default))]
		NoEffect => []
	}
	{
		..Scene.empty,
		camera: {
			eye: { x: 0.0, y: 3.0, z: 8.0 },
			target: { x: 0.0, y: 1.1, z: 0.0 },
			up: { x: 0.0, y: 1.0, z: 0.0 },
			fov_y: 0.8,
		},
		environment: { ..Environment.default, bloom: { ..Environment.default.bloom, strength: 0.0 } },
		post: effects,
		shader_values: [Foliage.scene("shaders", { ..Foliage.scene_default, wind: model.wind })],
		nodes: List.join([
			[
				Light(Light.ambient({ r: 0.25, g: 0.3, b: 0.4 })),
				Light(Light.sun({ x: -0.5, y: -0.9, z: -0.4 }, { r: 3.0, g: 2.7, b: 2.3 })),
				Draw(ground),
				Group(
					{ id: 100, pos: { x: 0.0, y: 0.0, z: 0.0 }, rot: { x: 0.0, y: 0.0, z: 0.0, w: 1.0 }, selected: model.selected },
					[Draw(tree), Draw(marker)],
				),
			],
			if (model.occluder) [Draw(wall)] else [],
		]),
	}
}
