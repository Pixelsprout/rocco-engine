app [
	init,
	launch,
	loaded,
	step,
	view,
] {
	mesh: "../../packages/mesh/main.roc",
	pf: platform "../../platform/main.roc",
	roc: "nightly-2026-10-11-7d256b9",
	ui: "../../packages/ui/main.roc",
}

import Colour
import Depth
import Foliage
import Selection
import Outline
import Tree
import mesh.Mesh
import ui.Ui
import pf.Config
import pf.Draw
import pf.Environment
import pf.Key
import pf.Launch
import pf.Light
import pf.Material
import pf.Post
import pf.Pose
import pf.Scene
import pf.Vocabulary

Model : {
	tree : U32,
	mode : Str,
	enabled : Bool,
	reverse : Bool,
	wind : F32,
	blend : Bool,
	solid : Bool,
	fixture : Bool,
	selected : Bool,
	visible_only : Bool,
	occluder : Bool,
	pip : U32,
	glass : U32,
	clip : U32,
	time : F32,
	skin : Bool,
	subset : [
		All,
		LeftOnly,
		RightOnly,
		Boxes,
	],
	bloom : Bool,
	override_glass : Bool,
	mask_zero : Bool,
}

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |config| {
	samples = if config.args.contains("--x2") X2 else if config.args.contains("--x4") X4 else if config.args.contains("--x8") X8 else Off
	width = if config.args.contains("--small") 480 else 800
	height = if config.args.contains("--small") 360 else 600
	{
		..Launch.default,
		window: {
			..Launch.default.window,
			title: "Post",
			width,
			height,
			samples,
			high_dpi: !config.args.contains("--low-dpi"),
		},
		capacity: { ..Launch.default.capacity, draws: 64 },
	}
}

init : Vocabulary.Config -> { model : Model, commands : List(Vocabulary.Command) }
init = |config| {
	mode = if config.args.contains("--outline") "outline" else if config.args.contains("--depth") "depth" else if config.args.contains("--empty") "empty" else if config.args.contains("--failed-only") "failed-only" else if config.args.contains("--failed") "failed" else if config.args.contains("--selection") "selection" else if config.args.contains("--hdr") "hdr" else "chain"
	{
		model: {
			tree: 0,
			mode,
			enabled: !config.args.contains("--disabled"),
			reverse: config.args.contains("--reverse"),
			wind: if config.args.contains("--wind") 0.3 else 0.0,
			blend: !config.args.contains("--no-blend"),
			solid: config.args.contains("--solid"),
			fixture: config.args.contains("--fixture") or config.args.contains("--selection") or config.args.contains("--outline"),
			selected: !config.args.contains("--no-selection"),
			visible_only: !config.args.contains("--through-wall"),
			occluder: !config.args.contains("--no-occluder"),
			pip: 0,
			glass: 0,
			clip: 0,
			time: 0.0,
			skin: !config.args.contains("--no-skin"),
			subset: if config.args.contains("--left-only") LeftOnly else if config.args.contains("--right-only") RightOnly else if config.args.contains("--boxes") Boxes else All,
			bloom: !config.args.contains("--no-bloom"),
			override_glass: config.args.contains("--override-glass"),
			mask_zero: config.args.contains("--mask-zero"),
		},
		commands: [
			Load({
				pack: "post",
				assets: [
					"tree",
					"pip",
					"glass",
					"shader/Foliage",
					"shader/Colour",
					"shader/Depth",
					"shader/Selection",
					"shader/Outline",
				],
			}),
		],
	}
}

loaded : Model, Str, Vocabulary.Manifest -> Model
loaded = |model, _pack, manifest| {
	..model,
	tree: Mesh.resolve(manifest, "tree"),
	pip: Mesh.resolve(manifest, "pip"),
	glass: Mesh.resolve(manifest, "glass"),
	clip: Mesh.clip(manifest, "pip", "Walk"),
}

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Vocabulary.Command) }
step = |model, input, _results, dt| {
	model: {
		..model,
		time: model.time + dt,
		selected: if Key.pressed(input, S) !model.selected else model.selected,
		visible_only: if Key.pressed(input, V) !model.visible_only else model.visible_only,
		enabled: if Key.pressed(input, E) !model.enabled else model.enabled,
		reverse: if Key.pressed(input, R) !model.reverse else model.reverse,
	},
	commands: if Key.pressed(input, U) [Unload("post")] else [],
}

colour : F32, F32 -> Vocabulary.Post
colour = |gain, offset| Post.after_tone_map(
	Colour.draw(
		"post",
		{
			gain: {
				x: gain,
				y: gain,
				z: gain,
			},
			offset: {
				x: offset,
				y: offset,
				z: offset,
			},
		},
	),
)

effects : Model -> List(Vocabulary.Post)
effects = |model| {
	missing = Post.after_tone_map({ ..Colour.draw("post", Colour.draw_default), shader: { pack: "post", asset: "shader/Missing" } })
	a = colour(0.5, 0.0)
	b = colour(1.0, 0.15)
	chain = if model.reverse [b, a] else [a, b]
	list = match model.mode {
		"depth" => [Post.after_tone_map(Depth.draw("post", Depth.draw_default))]
		"empty" => []
		"failed-only" => [missing]
		"failed" => [
			a,
			missing,
			b,
		]
		"outline" => [
			Post.before_bloom(Outline.draw("post", { ..Outline.draw_default, visible_only: model.visible_only })),
		]
		"selection" => [Post.after_tone_map(Selection.draw("post", Selection.draw_default))]
		"hdr" => List.join([
			[
				Post.before_bloom(
					Colour.draw(
						"post",
						{
							gain: {
								x: 2.0,
								y: 2.0,
								z: 2.0,
							},
							offset: {
								x: 0.5,
								y: 0.0,
								z: 0.0,
							},
						},
					),
				),
			],
			chain,
		])
		_ => chain
	}
	list.map(|effect| { ..effect, enabled: model.enabled })
}

view : Model -> Vocabulary.Scene
view = |model| {
	ground = {
		..Draw.default,
		id: 1,
		mesh: Mesh.primitive(Cube),
		pos: {
			x: 0.0,
			y: -0.1,
			z: 0.0,
		},
		scale: {
			x: 8.0,
			y: 0.2,
			z: 7.0,
		},
		tint: {
			r: 0.4,
			g: 0.4,
			b: 0.35,
		},
	}
	tree = {
		..Draw.default,
		id: 10,
		mesh: model.tree,
		casts_shadow: Bool.False,
		material: { ..Material.default, properties: if model.solid [Alpha(Opaque)] else [] },
		materials: [Tree.leaves("post", Foliage.material("post", Foliage.material_default))],
		shader_values: [Foliage.draw("post", Foliage.draw_default)],
	}
	wall = {
		..Draw.default,
		id: 2,
		mesh: Mesh.primitive(Cube),
		pos: {
			x: 2.1,
			y: 1.0,
			z: -1.0,
		},
		scale: {
			x: 1.3,
			y: 2.0,
			z: 0.2,
		},
		tint: {
			r: 0.2,
			g: 0.3,
			b: 0.6,
		},
	}
	glass = {
		..Draw.default,
		id: 3,
		mesh: Mesh.primitive(Cube),
		pos: {
			x: 2.1,
			y: 1.0,
			z: 0.7,
		},
		scale: {
			x: 1.4,
			y: 2.0,
			z: 0.2,
		},
		material: {
			..Material.default,
			properties: [
				Alpha(Blend),
				BaseColour({
					r: 0.1,
					g: 0.7,
					b: 0.9,
					a: 0.4,
				}),
			],
		},
	}
	nodes = List.join([
		[
			Light(
				Light.ambient({
					r: 0.5,
					g: 0.5,
					b: 0.5,
				}),
			),
			Draw(ground),
			Draw(tree),
			Draw(wall),
		],
		if model.blend [Draw(glass)] else [],
	])
	{
		..Scene.empty,
		camera: {
			eye: if model.fixture {
				x: 0.0,
				y: 2.0,
				z: 10.0,
			} else {
				x: 4.0,
				y: 3.0,
				z: 6.0,
			},
			target: {
				x: 0.0,
				y: 1.1,
				z: 0.0,
			},
			up: {
				x: 0.0,
				y: 1.0,
				z: 0.0,
			},
			fov_y: 0.8,
		},
		post: effects(model),
		shader_values: [Foliage.scene("post", { ..Foliage.scene_default, wind: model.wind })],
		environment: {
			..Environment.default,
			clear: {
				r: 0.03,
				g: 0.05,
				b: 0.08,
			},
			bloom: {
				strength: if model.bloom and (model.mode == "hdr" or model.mode == "outline") 0.3 else 0.0,
				threshold: 0.6,
				knee: 0.2,
			},
		},
		nodes: if model.fixture selection_nodes(model) else nodes,
		ui: [
			Panel(
				{
					..Ui.float_at(LeftTop, { x: 12.0, y: 12.0 }),
					width: Fixed(96.0),
					height: Fixed(36.0),
					radius: 8.0,
					background: {
						r: 1.0,
						g: 0.0,
						b: 0.0,
						a: 1.0,
					},
				},
				[],
			),
		],
	}
}

expect effects(init(Config.empty).model).len() == 2

selection_nodes : Model -> List(Vocabulary.Node)
selection_nodes = |model| {
	identity = {
		x: 0.0,
		y: 0.0,
		z: 0.0,
		w: 1.0,
	}
	origin = {
		x: 0.0,
		y: 0.0,
		z: 0.0,
	}
	cube = {
		..Draw.default,
		mesh: Mesh.primitive(Cube),
		casts_shadow: Bool.False,
		tint: {
			r: 0.2,
			g: 0.6,
			b: 0.3,
		},
	}
	left = {
		..cube,
		id: 20,
		pos: {
			x: -0.8,
			y: 1.0,
			z: 0.0,
		},
		scale: {
			x: 1.4,
			y: 1.6,
			z: 0.6,
		},
	}
	right = {
		..left,
		id: 21,
		pos: {
			x: 0.0,
			y: 1.0,
			z: -0.5,
		},
	}
	glass = {
		..cube,
		id: 22,
		mesh: if model.override_glass Mesh.primitive(Cube) else model.glass,
		material: if model.override_glass {
			..Material.default,
			properties: [
				Alpha(Blend),
				Unlit(Bool.True),
				BaseColour({
					r: 0.1,
					g: 0.7,
					b: 0.9,
					a: 0.0,
				}),
			],
		} else Material.default,
		pos: {
			x: -2.4,
			y: 1.0,
			z: 0.0,
		},
		scale: {
			x: 0.7,
			y: 1.5,
			z: 1.0,
		},
	}
	tree = {
		..cube,
		id: 23,
		mesh: model.tree,
		pos: {
			x: 1.5,
			y: 0.0,
			z: 0.0,
		},
		scale: {
			x: 0.8,
			y: 0.8,
			z: 0.8,
		},
		material: { ..Material.default, properties: if model.solid [Alpha(Opaque)] else [] },
		materials: [Tree.leaves("post", Foliage.material("post", Foliage.material_default))],
		shader_values: [Foliage.draw("post", Foliage.draw_default)],
	}
	pip = {
		..cube,
		id: 24,
		mesh: model.pip,
		pos: {
			x: 2.7,
			y: 0.0,
			z: 0.0,
		},
		material: if model.mask_zero {
			..Material.default,
			properties: [
				Alpha(Mask(0.5)),
				BaseColour({
					r: 1.0,
					g: 1.0,
					b: 1.0,
					a: 0.0,
				}),
			],
		} else Material.surface(Foliage.material("post", Foliage.material_default)),
		pose: Pose.still(model.clip, model.time),
	}
	wall = {
		..cube,
		id: 30,
		pos: {
			x: -0.6,
			y: 1.0,
			z: 1.0,
		},
		scale: {
			x: 0.6,
			y: 2.5,
			z: 0.2,
		},
		tint: {
			r: 0.2,
			g: 0.2,
			b: 0.5,
		},
	}
	ground = {
		..cube,
		id: 31,
		pos: {
			x: 0.0,
			y: -0.1,
			z: 0.0,
		},
		scale: {
			x: 10.0,
			y: 0.2,
			z: 7.0,
		},
		tint: {
			r: 0.2,
			g: 0.2,
			b: 0.2,
		},
	}
	unselected = {
		..left,
		id: 32,
		pos: {
			x: 0.0,
			y: 0.4,
			z: 2.0,
		},
		scale: {
			x: 0.4,
			y: 0.6,
			z: 0.4,
		},
	}
	all_children = List.join([
		[
			Draw(left),
			Group(
				{
					id: 101,
					pos: origin,
					rot: identity,
					selected: Bool.False,
				},
				[Draw(right)],
			),
			Draw(tree),
		],
		if model.blend [Draw(glass)] else [],
		if model.skin [Draw(pip)] else [],
	])
	children = match model.subset {
		LeftOnly => [Draw(left)]
		RightOnly => [
			Group(
				{
					id: 101,
					pos: origin,
					rot: identity,
					selected: Bool.False,
				},
				[Draw(right)],
			),
		]
		Boxes => [
			Draw(left),
			Group(
				{
					id: 101,
					pos: origin,
					rot: identity,
					selected: Bool.False,
				},
				[Draw(right)],
			),
		]
		All => all_children
	}
	List.join([
		[
			Light(
				Light.ambient({
					r: 0.5,
					g: 0.5,
					b: 0.5,
				}),
			),
			Draw(ground),
			Draw(unselected),
			Group(
				{
					id: 100,
					pos: origin,
					rot: identity,
					selected: model.selected,
				},
				children,
			),
		],
		if model.occluder [Draw(wall)] else [],
	])
}
