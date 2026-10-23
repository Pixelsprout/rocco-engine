// The Odin twin of bench/model-size. It runs the same logic on the same Model
// fields through the same run loop, so the gap between the two is the cost of
// the seam and of Roc.
package model_size_twin

import engine "../../engine"
import "core:fmt"
import "core:os"
import "core:strconv"

// These match bench/model-size/main.roc.
DRAW_COUNT :: 100
LIGHT_COUNT :: 2
HALF_EXTENT :: f32(20)
MAX_SPEED :: f32(4)
CUBE_MESH :: u32(1)

TWIN :: engine.Game_Calls {
	launch     = twin_launch,
	init       = twin_init,
	step       = twin_step,
	loaded     = twin_loaded,
	view       = twin_view,
	drop_model = twin_drop_model,
}

Entity :: struct {
	id:  u64,
	pos: engine.Vec3,
	vel: engine.Vec3,
}

Model :: struct {
	cube:     u32,
	rng:      u64,
	entities: []Entity,
}

main :: proc() {
	engine.run(TWIN)
}

// The seam treats the Model as a Roc box, so it keeps a refcount in front.
box_refcount :: proc(box: rawptr) -> ^int {
	return (^int)(uintptr(box) - size_of(int))
}

box_new :: proc(model: Model) -> rawptr {
	base := engine.roc_alloc(size_of(int) + size_of(Model), align_of(Model))
	box := rawptr(uintptr(base) + size_of(int))
	box_refcount(box)^ = 1
	(^Model)(box)^ = model
	return box
}

// high_dpi off, as in the bench game, so the numbers do not depend on the display.
twin_launch :: proc(config: engine.Config) -> engine.Launch {
	engine.roc_decref(config)
	launch := engine.launch_default()
	launch.window.high_dpi = false
	return launch
}

twin_init :: proc(config: engine.Config) -> engine.Init_Result {
	args := config.args
	n, ok := entity_count(args.elements[:args.length])
	seed := config.seed
	engine.roc_decref(config)
	if !ok {
		fmt.eprintln("The model-size twin needs N, a positive integer, as its first Arg.")
		os.exit(1)
	}
	return {model = box_new(spawn(seed, n))}
}

entity_count :: proc(args: []engine.Roc_Str) -> (n: int, ok: bool) {
	if len(args) == 0 {
		return 0, false
	}
	count, parsed := strconv.parse_u64_of_base(engine.roc_str_string(&args[0]), 10)
	if !parsed || count == 0 {
		return 0, false
	}
	return int(count), true
}

// The Model is unique here, as it is in the Roc game, so step updates it in place.
twin_step :: proc(model: rawptr, input: engine.Input, results: engine.Query_Results, dt: f32) -> engine.Step_Result {
	engine.roc_decref(input)
	engine.roc_decref(results)
	update((^Model)(model), dt)
	return {model = model}
}

twin_loaded :: proc(model: rawptr, pack: engine.Roc_Str, manifest: engine.Roc_List(engine.Manifest_Entry)) -> rawptr {
	engine.roc_decref(pack)
	engine.roc_list_decref(manifest)
	return model
}

// view consumes one reference, as the Roc view does.
twin_view :: proc(model: rawptr) -> engine.Scene {
	scene := view((^Model)(model))
	box_refcount(model)^ -= 1
	return scene
}

twin_drop_model :: proc(model: rawptr) {
	rc := box_refcount(model)
	rc^ -= 1
	if rc^ > 0 {
		return
	}
	delete((^Model)(model).entities)
	engine.roc_dealloc(rawptr(uintptr(model) - size_of(int)), align_of(Model))
}

spawn :: proc(seed: u64, n: int) -> Model {
	m := Model {
		cube     = CUBE_MESH,
		rng      = seed,
		entities = make([]Entity, n),
	}
	for &e, i in m.entities {
		r1 := next_rng(m.rng)
		r2 := next_rng(r1)
		r3 := next_rng(r2)
		r4 := next_rng(r3)
		e = {
			id  = u64(i),
			pos = {x = spread(r1, HALF_EXTENT), y = 0, z = spread(r2, HALF_EXTENT)},
			vel = {x = spread(r3, MAX_SPEED), y = 0, z = spread(r4, MAX_SPEED)},
		}
		m.rng = r4
	}
	return m
}

update :: proc(m: ^Model, dt: f32) {
	move(m, dt)
	bounce(m)
}

move :: proc(m: ^Model, dt: f32) {
	for &e in m.entities {
		e.pos = {x = e.pos.x + e.vel.x * dt, y = e.pos.y, z = e.pos.z + e.vel.z * dt}
	}
}

bounce :: proc(m: ^Model) {
	for &e in m.entities {
		e.vel.x = turn_back(e.pos.x, e.vel.x)
		e.vel.z = turn_back(e.pos.z, e.vel.z)
	}
}

turn_back :: proc(pos, vel: f32) -> f32 {
	if pos > HALF_EXTENT && vel > 0 || pos < -HALF_EXTENT && vel < 0 {
		return -vel
	}
	return vel
}

// The Draws, then the two Lights, as in the Roc game. Draw id i shows entity
// i * N / DRAW_COUNT.
view :: proc(m: ^Model) -> engine.Scene {
	nodes: [DRAW_COUNT + LIGHT_COUNT]engine.Node
	n := len(m.entities)
	for &node, i in nodes[:DRAW_COUNT] {
		node = {tag = .Draw, payload = {draw = cube_draw(m.cube, u64(i), m.entities[i * n / DRAW_COUNT].pos)}}
	}
	nodes[DRAW_COUNT] = {tag = .Light}
	nodes[DRAW_COUNT].payload.light = {tag = .Ambient}
	nodes[DRAW_COUNT].payload.light.payload.ambient = {r = 0.2, g = 0.2, b = 0.2}
	nodes[DRAW_COUNT + 1] = {tag = .Light}
	nodes[DRAW_COUNT + 1].payload.light = {tag = .Directional}
	nodes[DRAW_COUNT + 1].payload.light.payload.directional = {dir = {x = -2.0 / 7.0, y = -3.0 / 7.0, z = -6.0 / 7.0}, color = {r = 5.03, g = 5.03, b = 5.03}}
	return {
		camera = {eye = {x = 0, y = 40, z = 30}, target = {}, up = {x = 0, y = 1, z = 0}, fov_y = 1.047},
		nodes = engine.roc_list_from_slice(nodes[:]),
		cursor = .Free,
	}
}

cube_draw :: proc(mesh: u32, id: u64, pos: engine.Vec3) -> engine.Draw {
	identity := engine.Quat {
		w = 1,
	}
	return {id = id, mesh = mesh, pos = pos, scale = {x = 0.5, y = 0.5, z = 0.5}, rot = identity, scale_rot = identity, tint = {r = 0.8, g = 0.8, b = 0.8}}
}

next_rng :: proc(s: u64) -> u64 {
	return s * 6364136223846793005 + 1
}

// A value in [-limit, limit) from the top bits of the generator state.
spread :: proc(s: u64, limit: f32) -> f32 {
	return (f32((s >> 40) % 1000) / 500.0 - 1.0) * limit
}
