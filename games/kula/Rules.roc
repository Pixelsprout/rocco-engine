import World
import Level
import Ball

Rules := [].{
	# Cleared waits for the next level's Theme to load. Starting holds the seconds left before the new level plays.
	Phase : [Playing, Cleared, Starting(F32), Won]

	# collected holds the cells of the keys taken so far. The Level keeps every item.
	# Levels count from 1. unloads holds the packs the next step unloads.
	Model : { level_number : U64, level : World.Level, ball : Ball.Ball, meshes : World.Meshes, phase : Phase, keys_left : U64, collected : Set(World.Cell), unloads : List(Str) }

	start : World.Meshes, U64 -> Model
	start = |meshes, level_number| {
		level = parse_or_crash(Level.text(level_number))
		keys = level.items.keep_if(|entry| entry.item == Key).len()
		{ level_number, level, ball: Ball.start(level.start), meshes, phase: Playing, keys_left: keys, collected: Set.empty(), unloads: [] }
	}

	restart : Model -> Model
	restart = |model| start(model.meshes, model.level_number)

	start_pause : F32
	start_pause = 1.0

	next_level : Model -> Model
	next_level = |model| { ..start(model.meshes, model.level_number + 1), phase: Starting(start_pause) }

	count_down : F32 -> (Model -> Model)
	count_down = |dt| |model| match model.phase {
		Starting(seconds) => if seconds - dt > 0.0 {
			{ ..model, phase: Starting(seconds - dt) }
		} else {
			{ ..model, phase: Playing }
		}
		_ => model
	}

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
		if model.phase == Playing and exit_open(model) and has_item(model.level, model.ball.pose.cell, Exit) {
			{
				..model,
				phase: if model.level_number < Level.count {
					Cleared
				} else {
					Won
				},
			}
		} else {
			model
		}

	fall : Model -> Model
	# A restart in Cleared would leave the next Theme's pack loaded with no level to take it.
	fall = |model| if model.phase != Cleared and Ball.fell_off(model.ball) {
		restart(model)
	} else {
		model
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
meshes = { cube: 1, face: 5, ball: 4, sky: 1 }

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
	model = Rules.start(meshes, 1)
	model.keys_left == 2 and model.phase == Playing and model.collected.len() == 0 and !Rules.exit_open(model)
}

expect {
	model = Rules.collect(at(Rules.start(meshes, 1), first_key))
	model.keys_left == 1 and model.collected.contains(first_key)
}

# Standing on a collected key does not count it twice.
expect Rules.collect(Rules.collect(at(Rules.start(meshes, 1), first_key))).keys_left == 1

expect Rules.collect(Rules.start(meshes, 1)) == Rules.start(meshes, 1)

expect {
	both = Rules.collect(at(Rules.collect(at(Rules.start(meshes, 1), first_key)), second_key))
	both.keys_left == 0 and Rules.exit_open(both)
}

expect Rules.exit(at(Rules.start(meshes, 1), exit_cell)).phase == Playing

expect {
	model = at(Rules.start(meshes, 1), first_key)
	ball = { ..model.ball, motion: Falling({ from: model.level.start, offset: 0.0, over: model.level.start, drop: Off(3), seconds: 0.5, spin_rate: 0.0 }) }
	Rules.fall({ ..model, ball }) == { ..model, ball }
}

expect {
	dirty = { ..Rules.collect(at(Rules.start(meshes, 1), first_key)), phase: Won }
	ball = { ..dirty.ball, motion: Falling({ from: dirty.level.start, offset: 0.0, over: dirty.level.start, drop: Off(3), seconds: 1.0, spin_rate: 0.0 }) }
	Rules.fall({ ..dirty, ball }) == Rules.start(meshes, 1)
}

expect Ok(Rules.start(meshes, 2).level) == Level.parse(Level.text(2))
expect Rules.start(meshes, 3).keys_left == 2 and Rules.start(meshes, 3).level_number == 3

# The exit of a level before the last clears it. The last level's exit wins.
expect {
	open = { ..Rules.start(meshes, 1), keys_left: 0 }
	Rules.exit(at(open, exit_cell)).phase == Cleared
}

expect {
	last = Rules.start(meshes, 3)
	open = { ..last, keys_left: 0 }
	Rules.exit(at(open, exit_cell)).phase == Won and Rules.exit(open).phase == Playing
}

# The next level starts with the ball still for a short pause.
expect {
	next = Rules.next_level({ ..Rules.start(meshes, 1), phase: Cleared })
	next.level_number == 2 and next.phase == Starting(Rules.start_pause) and next.ball == Ball.start(next.level.start) and next.keys_left == 2
}

expect Rules.count_down(0.4)({ ..Rules.start(meshes, 2), phase: Starting(1.0) }).phase == Starting(0.6)
expect Rules.count_down(1.0)({ ..Rules.start(meshes, 2), phase: Starting(1.0) }).phase == Playing
expect Rules.count_down(1.0)(Rules.start(meshes, 2)).phase == Playing

# A fall restarts the level the ball is on.
expect {
	model = Rules.start(meshes, 2)
	ball = { ..model.ball, motion: Falling({ from: model.level.start, offset: 0.0, over: model.level.start, drop: Off(3), seconds: 1.0, spin_rate: 0.0 }) }
	Rules.fall({ ..model, ball }) == model
}

expect {
	model = { ..Rules.start(meshes, 1), phase: Cleared }
	ball = { ..model.ball, motion: Falling({ from: model.level.start, offset: 0.0, over: model.level.start, drop: Off(3), seconds: 1.0, spin_rate: 0.0 }) }
	Rules.fall({ ..model, ball }).phase == Cleared
}
