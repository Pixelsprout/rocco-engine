import World
import Level
import Ball

Rules := [].{
	Phase : [Playing, Won]

	# collected holds the cells of the keys taken so far. The Level keeps every item.
	Model : { level : World.Level, ball : Ball.Ball, meshes : World.Meshes, phase : Phase, keys_left : U64, collected : Set(World.Cell) }

	start : World.Meshes -> Model
	start = |meshes| {
		level = parse_or_crash(Level.level1_text)
		keys = level.items.keep_if(|entry| entry.item == Key).len()
		{ level, ball: Ball.start(level.start), meshes, phase: Playing, keys_left: keys, collected: Set.empty() }
	}

	restart : Model -> Model
	restart = |model| start(model.meshes)

	# Runs every step, so a key collects as soon as the move onto its cell commits.
	collect : Model -> Model
	collect = |model| {
		cell = model.ball.pose.cell
		if has_item(model.level, cell, Key) and !model.collected.contains(cell) {
			{ ..model, collected: model.collected.insert(cell), keys_left: model.keys_left - 1 }
		} else {
			model
		}
	}

	exit_open : Model -> Bool
	exit_open = |model| model.keys_left == 0

	exit : Model -> Model
	exit = |model|
		if exit_open(model) and has_item(model.level, model.ball.pose.cell, Exit) {
			{ ..model, phase: Won }
		} else {
			model
		}

	fall : Model -> Model
	fall = |model| match model.ball.motion {
		Falling({ t, .. }) if t >= 1.0 => restart(model)
		_ => model
	}
}

parse_or_crash : Str -> World.Level
parse_or_crash = |text| match Level.parse(text) {
	Ok(level) => level
	Err(err) => crash "The level does not parse: ${Str.inspect(err)}"
}

has_item : World.Level, World.Cell, World.Item -> Bool
has_item = |level, cell, item| level.items.any(|entry| entry.cell == cell and entry.item == item)

meshes : World.Meshes
meshes = { cube: 1, face: 5, ball: 4 }

cell : I32, I32, I32 -> World.Cell
cell = |x, y, z| { x, y, z }

at : Rules.Model, World.Cell -> Rules.Model
at = |model, c| { ..model, ball: Ball.start({ ..model.ball.pose, cell: c }) }

first_key : World.Cell
first_key = cell(0, 1, 7)

second_key : World.Cell
second_key = cell(0, 2, 5)

exit_cell : World.Cell
exit_cell = cell(0, 1, 0)

expect {
	model = Rules.start(meshes)
	model.keys_left == 2 and model.phase == Playing and model.collected.len() == 0 and !Rules.exit_open(model)
}

expect {
	model = Rules.collect(at(Rules.start(meshes), first_key))
	model.keys_left == 1 and model.collected.contains(first_key)
}

# Standing on a collected key does not count it twice.
expect Rules.collect(Rules.collect(at(Rules.start(meshes), first_key))).keys_left == 1

expect Rules.collect(Rules.start(meshes)) == Rules.start(meshes)

expect {
	both = Rules.collect(at(Rules.collect(at(Rules.start(meshes), first_key)), second_key))
	both.keys_left == 0 and Rules.exit_open(both)
}

expect Rules.exit(at(Rules.start(meshes), exit_cell)).phase == Playing

expect {
	open = { ..Rules.start(meshes), keys_left: 0 }
	Rules.exit(at(open, exit_cell)).phase == Won and Rules.exit(open).phase == Playing
}

expect {
	model = at(Rules.start(meshes), first_key)
	ball = { ..model.ball, motion: Falling({ from: model.level.start, t: 0.5 }) }
	Rules.fall({ ..model, ball }) == { ..model, ball }
}

expect {
	dirty = { ..Rules.collect(at(Rules.start(meshes), first_key)), phase: Won }
	ball = { ..dirty.ball, motion: Falling({ from: dirty.level.start, t: 1.0 }) }
	Rules.fall({ ..dirty, ball }) == Rules.start(meshes)
}
