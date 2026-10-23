#+test
package colliders_twin

import engine "../../engine"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"

// bench/colliders/main.roc checks its own Colliders against the same file.
// Set this define to rewrite the file from the twin.
WRITE_GOLDEN :: #config(TWIN_WRITE_GOLDEN, false)
GOLDEN_PATH :: "../colliders/colliders.golden"
GOLDEN :: string(#load(GOLDEN_PATH))
GOLDEN_SEED :: 7
GOLDEN_N :: "100"
GOLDEN_STEPS :: 600

// Only the WRITE_GOLDEN code uses os, so -vet needs this when it is off.
_ :: os

// The test runner uses several threads, and the Roc heap is a package global.
@(private = "file")
g_heap_lock: sync.Mutex

heap_begin :: proc() {
	sync.mutex_lock(&g_heap_lock)
	engine.roc_heap_init(context.allocator)
}

heap_end :: proc() {
	engine.roc_heap_shutdown()
	sync.mutex_unlock(&g_heap_lock)
}

bits :: proc(f: f32) -> u32 {
	return transmute(u32)f
}

// One line per Collider, with each f32 as the decimal u32 of its bits, so the
// check is exact.
twin_colliders :: proc(seed: u64, n: string, steps: int) -> string {
	model := TWIN.init(engine.config_make(seed, nil, {n})).model
	for _ in 0 ..< steps {
		model = TWIN.step(model, {}, {}, f32(1.0 / 120.0)).model
	}
	engine.roc_incref_box(model)
	scene := TWIN.view(model)
	b := strings.builder_make(context.temp_allocator)
	for node in scene.nodes.elements[:scene.nodes.length] {
		c := node.payload.collider
		fmt.sbprintf(&b, "%v ", c.id)
		switch c.shape.tag {
		case .Sphere:
			fmt.sbprintf(&b, "sphere %v", bits(c.shape.payload.sphere))
		case .Box:
			h := c.shape.payload.box
			fmt.sbprintf(&b, "box %v %v %v", bits(h.x), bits(h.y), bits(h.z))
		case .Capsule:
			fmt.sbprint(&b, "capsule")
		}
		fmt.sbprintf(&b, " %v %v %v", bits(c.pos.x), bits(c.pos.y), bits(c.pos.z))
		fmt.sbprintf(&b, " %v %v %v %v\n", bits(c.rot.x), bits(c.rot.y), bits(c.rot.z), bits(c.rot.w))
	}
	engine.roc_decref(scene)
	TWIN.drop_model(model)
	return strings.to_string(b)
}

@(test)
twin_matches_the_roc_colliders :: proc(t: ^testing.T) {
	heap_begin()
	defer heap_end()

	got := twin_colliders(GOLDEN_SEED, GOLDEN_N, GOLDEN_STEPS)
	when WRITE_GOLDEN {
		testing.expect_value(t, os.write_entire_file(#directory + "/" + GOLDEN_PATH, transmute([]byte)got), nil)
	} else {
		testing.expect_value(t, got, GOLDEN)
	}
	testing.expect_value(t, engine.roc_heap_counters().live, 0)
}

@(test)
twin_step_counts_the_answers :: proc(t: ^testing.T) {
	heap_begin()
	defer heap_end()

	model := TWIN.init(engine.config_make(0, nil, {"8"})).model
	results := engine.Query_Results {
		rays     = engine.roc_list_from_slice([]engine.Ray_Hit{{id = 3}}),
		overlaps = engine.roc_list_from_slice([]engine.Overlap_Hit{{id = 4, slot = 1}, {id = 6, slot = 1}}),
	}
	model = TWIN.step(model, {}, results, f32(1.0 / 120.0)).model
	testing.expect_value(t, (^Model)(model).answered, 3)
	TWIN.drop_model(model)
	testing.expect_value(t, engine.roc_heap_counters().live, 0)
}

@(test)
twin_view_asks_the_same_queries_at_every_n :: proc(t: ^testing.T) {
	heap_begin()
	defer heap_end()

	for n in ([]int{64, 4096}) {
		m := spawn(3, n)
		defer delete(m.bodies)
		testing.expect_value(t, m.half, f32(n == 64 ? 8 : 64))

		scene := view(&m)
		defer engine.roc_decref(scene)
		testing.expect_value(t, int(scene.nodes.length), n)
		qs := scene.queries.elements[:scene.queries.length]
		testing.expect_value(t, len(qs), QUERY_COUNT)
		for q, i in qs {
			want: engine.Query_Tag = i < SLOT_COUNT ? .Raycast : i < 2 * SLOT_COUNT ? .Overlap : .ContactsOf
			testing.expect_value(t, q.tag, want)
		}
		testing.expect_value(t, qs[QUERY_COUNT - 1].payload.contacts_of, WATCHED)
	}
}

@(test)
twin_colliders_alternate_box_and_sphere :: proc(t: ^testing.T) {
	heap_begin()
	defer heap_end()

	m := spawn(3, 4)
	defer delete(m.bodies)
	scene := view(&m)
	defer engine.roc_decref(scene)
	want := []engine.Collider_Shape_Tag{.Box, .Sphere, .Box, .Sphere}
	for node, i in scene.nodes.elements[:scene.nodes.length] {
		testing.expect_value(t, node.tag, engine.Node_Tag.Collider)
		testing.expect_value(t, node.payload.collider.id, u64(i + 1))
		testing.expect_value(t, node.payload.collider.shape.tag, want[i])
	}
}

@(test)
twin_lanes_span_the_arena :: proc(t: ^testing.T) {
	testing.expect_value(t, lane(0, 8), f32(-7))
	testing.expect_value(t, lane(7, 8), f32(7))
}

@(test)
twin_reads_n_from_the_first_arg :: proc(t: ^testing.T) {
	heap_begin()
	defer heap_end()

	cases := []struct {
		args: []string,
		n:    int,
		ok:   bool,
	}{{{"64"}, 64, true}, {{"16384", "extra"}, 16384, true}, {nil, 0, false}, {{"0"}, 0, false}, {{"-3"}, 0, false}, {{"many"}, 0, false}}
	for c in cases {
		config := engine.config_make(0, nil, c.args)
		n, ok := collider_count(config.args.elements[:config.args.length])
		engine.roc_decref(config)
		testing.expect_value(t, n, c.n)
		testing.expect_value(t, ok, c.ok)
	}
}

@(test)
twin_launch_is_the_default_with_high_dpi_off :: proc(t: ^testing.T) {
	heap_begin()
	defer heap_end()

	launch := TWIN.launch(engine.config_make(0, nil, {"64"}))
	want := engine.launch_default()
	want.window.high_dpi = false
	testing.expect_value(t, launch, want)
	testing.expect_value(t, engine.roc_heap_counters().live, 0)
}
