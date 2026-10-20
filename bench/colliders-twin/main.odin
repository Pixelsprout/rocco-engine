// The Odin twin of bench/colliders. It moves the same Colliders and asks the
// same Queries through the same run loop, so the gap between the two is the
// cost of the seam and of Roc.
package colliders_twin

import engine "../../engine"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"

// These match bench/colliders/main.roc.
SLOT_COUNT :: 8
MAX_SPEED :: f32(4)
RADIUS :: f32(0.5)
PROBE_RADIUS :: f32(2)
OWNER :: u64(0)
WATCHED :: u64(1)
QUERY_COUNT :: 2 * SLOT_COUNT + 1

TWIN :: engine.Game_Calls {
	launch     = twin_launch,
	init       = twin_init,
	step       = twin_step,
	loaded     = twin_loaded,
	view       = twin_view,
	drop_model = twin_drop_model,
}

Body :: struct {
	id:  u64,
	pos: engine.Vec3,
	vel: engine.Vec3,
	yaw: f32,
}

// answered counts the QueryResults of the last step, so step reads every answer.
Model :: struct {
	rng:      u64,
	half:     f32,
	bodies:   []Body,
	answered: u64,
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
	n, ok := collider_count(args.elements[:args.length])
	seed := config.seed
	engine.roc_decref(config)
	if !ok {
		fmt.eprintln("The colliders twin needs N, a positive integer, as its first Arg.")
		os.exit(1)
	}
	return {model = box_new(spawn(seed, n))}
}

collider_count :: proc(args: []engine.Roc_Str) -> (n: int, ok: bool) {
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
	m := (^Model)(model)
	m.answered = u64(results.contacts.length + results.rays.length + results.overlaps.length)
	engine.roc_decref(input)
	engine.roc_decref(results)
	move(m, dt)
	bounce(m)
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
	delete((^Model)(model).bodies)
	engine.roc_dealloc(rawptr(uintptr(model) - size_of(int)), align_of(Model))
}

// Each Collider gets 4 square units, so the arena half extent is sqrt(N).
spawn :: proc(seed: u64, n: int) -> Model {
	m := Model {
		rng    = seed,
		half   = math.sqrt(f32(n)),
		bodies = make([]Body, n),
	}
	for &b, i in m.bodies {
		r1 := next_rng(m.rng)
		r2 := next_rng(r1)
		r3 := next_rng(r2)
		r4 := next_rng(r3)
		r5 := next_rng(r4)
		b = {
			id  = u64(i + 1),
			pos = {x = spread(r1, m.half), y = 0, z = spread(r2, m.half)},
			vel = {x = spread(r3, MAX_SPEED), y = 0, z = spread(r4, MAX_SPEED)},
			yaw = spread(r5, 3),
		}
		m.rng = r5
	}
	return m
}

move :: proc(m: ^Model, dt: f32) {
	for &b in m.bodies {
		b.pos = {x = b.pos.x + b.vel.x * dt, y = b.pos.y, z = b.pos.z + b.vel.z * dt}
	}
}

bounce :: proc(m: ^Model) {
	for &b in m.bodies {
		b.vel.x = turn_back(b.pos.x, b.vel.x, m.half)
		b.vel.z = turn_back(b.pos.z, b.vel.z, m.half)
	}
}

turn_back :: proc(pos, vel, half: f32) -> f32 {
	if pos > half && vel > 0 || pos < -half && vel < 0 {
		return -vel
	}
	return vel
}

view :: proc(m: ^Model) -> engine.Scene {
	colliders := make([]engine.Collider, len(m.bodies), context.temp_allocator)
	for b, i in m.bodies {
		colliders[i] = to_collider(b)
	}
	qs := queries(m.half)
	return {
		camera = {eye = {x = 0, y = m.half * 2, z = m.half * 1.5}, target = {}, up = {x = 0, y = 1, z = 0}, fov_y = 1.047},
		colliders = engine.roc_list_from_slice(colliders),
		queries = engine.roc_list_from_slice(qs[:]),
		cursor = .Free,
	}
}

// Even ids are spheres and odd ids are turned boxes, so both narrowphases run.
to_collider :: proc(b: Body) -> engine.Collider {
	c := engine.Collider {
		id  = b.id,
		pos = b.pos,
	}
	if b.id % 2 == 0 {
		c.shape.tag = .Sphere
		c.shape.payload.sphere = RADIUS
	} else {
		c.shape.tag = .Box
		c.shape.payload.box = {x = RADIUS, y = RADIUS, z = RADIUS}
		c.yaw = b.yaw
	}
	return c
}

// Each raycast crosses the arena along x in its own lane. The overlaps sit on
// the diagonal through the lanes.
queries :: proc(half: f32) -> (qs: [QUERY_COUNT]engine.Query) {
	for k in 0 ..< SLOT_COUNT {
		ray := &qs[k]
		ray.tag = .Raycast
		ray.payload.raycast = {
			owner        = OWNER,
			slot         = u32(k),
			origin       = {x = -half - 1, y = 0, z = lane(k, half)},
			dir          = {x = 1, y = 0, z = 0},
			max_distance = half * 2 + 2,
		}
		overlap := &qs[SLOT_COUNT + k]
		overlap.tag = .Overlap
		overlap.payload.overlap = {
			owner = OWNER,
			slot  = u32(k),
			pos   = {x = lane(k, half), y = 0, z = lane(k, half)},
		}
		overlap.payload.overlap.shape.tag = .Sphere
		overlap.payload.overlap.shape.payload.sphere = PROBE_RADIUS
	}
	qs[QUERY_COUNT - 1].tag = .ContactsOf
	qs[QUERY_COUNT - 1].payload.contacts_of = WATCHED
	return
}

// The centre of lane k of the equal lanes across [-half, half].
lane :: proc(k: int, half: f32) -> f32 {
	return (f32(2 * k + 1) / SLOT_COUNT - 1) * half
}

next_rng :: proc(s: u64) -> u64 {
	return s * 6364136223846793005 + 1
}

// A value in [-limit, limit) from the top bits of the generator state.
spread :: proc(s: u64, limit: f32) -> f32 {
	return (f32((s >> 40) % 1000) / 500.0 - 1.0) * limit
}
