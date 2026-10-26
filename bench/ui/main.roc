app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", shared: "../shared/main.roc", ui: "../../packages/ui/main.roc" }

import shared.Bench
import cam.Camera as Cam
import ui.Ui
import pf.Vocabulary exposing [Command, Config, Element, Input, Manifest, Rgba, Scene]
import pf.QueryResults
import pf.Launch

# The UI bench game. Its Scene has no Draws, and its UI holds exactly N Box and
# Text elements inside one root Box: N / 2 cells of one Box and one Text, plus
# one empty Box when N is odd. One cell is lit, and it moves on each step, so
# the UI changes every step but its size does not.
Model : { labels : List(Str), lit : U64 }

cell_box : Ui.BoxConfig
cell_box = { ..Ui.default_box, width: Fixed(120.0), height: Fixed(16.0), pad: { left: 4.0, right: 4.0, top: 0.0, bottom: 0.0 }, background: { r: 0.15, g: 0.15, b: 0.2, a: 1.0 } }

lit_background : Rgba
lit_background = { r: 0.8, g: 0.5, b: 0.1, a: 1.0 }

root_box : Ui.BoxConfig
root_box = { ..Ui.default_box, width: Grow({ min: 0.0, max: 0.0 }), height: Grow({ min: 0.0, max: 0.0 }), direction: Col, gap: 2.0, pad: Ui.pad_all(8.0) }

label : Str -> Ui.Text
label = |str| { ..Ui.label(str), size: 12.0, wrap: None }

# high_dpi off, so the numbers do not depend on the display.
launch : Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, high_dpi: False } }

# N is the first Arg. A missing or bad N must stop the run, so a typo cannot
# give a benchmark at the wrong size.
init : Config -> { model : Model, commands : List(Command) }
init = |config| match Bench.n_arg(config.args) {
	Ok(n) => { model: spawn(n), commands: [] }
	Err(BadCount) => crash "The ui bench game needs N, a positive integer, as its first Arg."
}

# The labels are built once, so view copies no text.
spawn : U64 -> Model
spawn = |n| {
	labels = add_labels(List.with_capacity(n // 2 + 1), n // 2)
	{ labels: if n % 2 == 1 labels.append("") else labels, lit: 0 }
}

add_labels : List(Str), U64 -> List(Str)
add_labels = |labels, count| {
	if labels.len() >= count {
		labels
	} else {
		add_labels(labels.append("Cell ${labels.len().to_str()}"), count)
	}
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, _input, _results, _dt| { model: move_light(m), commands: [] }

move_light : Model -> Model
move_light = |m| { ..m, lit: (m.lit + 1) % m.labels.len() }

view : Model -> Scene
view = |m| {
	camera: Cam.look_at({ x: 0.0, y: 10.0, z: 10.0 }, { x: 0.0, y: 0.0, z: 0.0 }),
	nodes: [],
	cursor: Free,
	sky: 0,
	ui: elements(m),
	queries: [],
}

elements : Model -> List(Element)
elements = |m| {
	cells = m.labels.map_with_index(|text, i| cell(text, i == m.lit))
	[Box(root_box, cells)]
}

# The empty label marks the lone Box of an odd N.
cell : Str, Bool -> Element
cell = |text, lit| {
	config = if lit { ..cell_box, background: lit_background } else cell_box
	children = if text == "" [] else [Text(label(text))]
	Box(config, children)
}

ui_of : U64 -> List(Element)
ui_of = |n| view(init(Bench.with_n(n)).model).ui

boxes : List(Element) -> U64
boxes = |ui| ui.fold(
	0,
	|n, e| match e {
		Box(_, children) => n + 1 + boxes(children)
		Text(_) => n
	},
)

texts : List(Element) -> U64
texts = |ui| ui.fold(
	0,
	|n, e| match e {
		Box(_, children) => n + texts(children)
		Text(_) => n + 1
	},
)

cells_of : List(Element) -> List(Element)
cells_of = |ui| match ui {
	[Box(_, cells)] => cells
	_ => []
}

# The root Box is not one of the N elements, so the counts start at its children.
box_and_text_count : List(Element) -> U64
box_and_text_count = |ui| {
	cells = cells_of(ui)
	boxes(cells) + texts(cells)
}

expect launch(Bench.no_args).window.high_dpi == False
expect init(Bench.with_n(64)).commands == []

expect box_and_text_count(ui_of(64)) == 64 and texts(ui_of(64)) == 32
expect box_and_text_count(ui_of(1)) == 1 and texts(ui_of(1)) == 0
expect box_and_text_count(ui_of(7)) == 7 and texts(ui_of(7)) == 3
expect box_and_text_count(ui_of(16384)) == 16384
expect ui_of(64).len() == 1 and cells_of(ui_of(64)).len() == 32

expect view(init(Bench.with_n(64)).model).nodes == []

expect {
	m = init(Bench.with_n(6)).model
	[1, 2, 0, 1] == [move_light(m), move_light(move_light(m)), move_light(move_light(move_light(m))), move_light(move_light(move_light(move_light(m))))].map(|x| x.lit)
}

expect {
	m = init(Bench.with_n(64)).model
	after = step(m, Bench.idle, QueryResults.empty, 1.0 / 120.0)
	after.model.lit == 1 and after.model.labels == m.labels and after.commands == []
}

lit_count : List(Element) -> U64
lit_count = |ui| cells_of(ui).count_if(
	|e| match e {
		Box(config, _) => config == { ..cell_box, background: lit_background }
		Text(_) => Bool.False
	},
)

# A step changes which cell is lit, not the number of elements.
expect {
	m = init(Bench.with_n(64)).model
	before = elements(m)
	after = elements(move_light(m))
	lit_count(before) == 1 and lit_count(after) == 1 and before != after and cells_of(before).len() == cells_of(after).len()
}
