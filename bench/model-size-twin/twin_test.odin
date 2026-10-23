#+test
package model_size_twin

import engine "../../engine"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"

// bench/model-size/main.roc checks its own positions against the same file.
// Set this define to rewrite the file from the twin.
WRITE_GOLDEN :: #config(TWIN_WRITE_GOLDEN, false)
GOLDEN_PATH :: "../model-size/positions.golden"
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

// One line per Draw: the bits of pos.x and pos.z as decimal u32, so the
// check is exact.
twin_positions :: proc(seed: u64, n: string, steps: int) -> string {
	model := TWIN.init(engine.config_make(seed, nil, {n})).model
	for _ in 0 ..< steps {
		model = TWIN.step(model, {}, {}, f32(1.0 / 120.0)).model
	}
	engine.roc_incref_box(model)
	scene := TWIN.view(model)
	b := strings.builder_make(context.temp_allocator)
	for node in scene.nodes.elements[LIGHT_COUNT:scene.nodes.length] {
		d := node.payload.draw
		fmt.sbprintf(&b, "%v %v\n", transmute(u32)d.pos.x, transmute(u32)d.pos.z)
	}
	engine.roc_decref(scene)
	TWIN.drop_model(model)
	return strings.to_string(b)
}

@(test)
twin_matches_the_roc_positions :: proc(t: ^testing.T) {
	heap_begin()
	defer heap_end()

	got := twin_positions(GOLDEN_SEED, GOLDEN_N, GOLDEN_STEPS)
	when WRITE_GOLDEN {
		testing.expect_value(t, os.write_entire_file(#directory + "/" + GOLDEN_PATH, transmute([]byte)got), nil)
	} else {
		testing.expect_value(t, got, GOLDEN)
	}
	testing.expect_value(t, engine.roc_heap_counters().live, 0)
}

@(test)
twin_view_gives_draw_count_draws :: proc(t: ^testing.T) {
	m := spawn(3, 64)
	defer delete(m.entities)
	heap_begin()
	defer heap_end()

	scene := view(&m)
	defer engine.roc_decref(scene)
	testing.expect_value(t, int(scene.nodes.length), LIGHT_COUNT + DRAW_COUNT)
	for node, i in scene.nodes.elements[LIGHT_COUNT:scene.nodes.length] {
		testing.expect_value(t, node.tag, engine.Node_Tag.Draw)
		testing.expect_value(t, node.payload.draw.id, u64(i))
		testing.expect_value(t, node.payload.draw.mesh, CUBE_MESH)
	}
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
		n, ok := entity_count(config.args.elements[:config.args.length])
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
