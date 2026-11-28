#+test
package engine

import sg "../sokol-odin/sokol/gfx"
import "core:math"
import "core:testing"

@(test)
test_particles_seed_identity_burst_and_drain :: proc(t: ^testing.T) {
	a, b: Particles
	particles_init(&a, context.allocator)
	particles_init(&b, context.allocator)
	defer particles_destroy(&a)
	defer particles_destroy(&b)
	emitters := [2]Emitter{particle_test_emitter(7), particle_test_emitter(8)}
	for _ in 0 ..< 30 {
		particles_burst(&a, {emitter = 7, count = 3})
		particles_burst(&b, {emitter = 7, count = 3})
		particles_step(&a, emitter_nodes(emitters[:]), nil, 1.0/120)
		particles_step(&b, emitter_nodes(emitters[:]), nil, 1.0/120)
	}
	testing.expect_value(t, a.count, b.count)
	for particle, i in a.particles[:a.count] { testing.expect_value(t, particle, b.particles[i]) }
	random := a.sources[0].random
	particles_step(&a, nil, nil, 0)
	testing.expect(t, a.sources[0].live && !a.sources[0].present)
	emitters[1] = emitters[0]
	emitters[1].pos.x = 99
	particles_step(&a, emitter_nodes(emitters[:]), nil, 0)
	testing.expect_value(t, a.sources[0].config.pos.x, f32(0))
	testing.expect_value(t, a.sources[0].random, random)
	particles_step(&a, nil, nil, 2)
	testing.expect_value(t, a.count, 0)
	testing.expect(t, !a.sources[0].live)
	particles_step(&a, emitter_nodes(emitters[:1]), nil, 0)
	testing.expect_value(t, a.sources[0].random, emitters[0].seed)
}

@(test)
test_particles_capacity_drops_new_and_bursts_use_current_scene :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	emitters := [2]Emitter{particle_test_emitter(1), particle_test_emitter(2)}
	particles_burst(&p, {emitter = 1, count = max(u32)})
	particles_burst(&p, {emitter = 1, count = max(u32)})
	particles_burst(&p, {emitter = 2, count = 1})
	particles_step(&p, emitter_nodes(emitters[:]), nil, 0)
	testing.expect_value(t, p.count, PARTICLE_LIMIT)
	testing.expect_value(t, p.sources[1].count, 0)
	testing.expect_value(t, p.burst_count, 0)
	particles_step(&p, nil, nil, 2)
	particles_burst(&p, {emitter = 1, count = 10})
	particles_step(&p, nil, nil, 0)
	testing.expect_value(t, p.count, 0)
	many := make([]Emitter, EMITTER_LIMIT + 1, context.temp_allocator)
	for &e, i in many { e = particle_test_emitter(u64(i)) }
	particles_step(&p, emitter_nodes(many), nil, 0)
	live := 0
	for source in p.sources { if source.live { live += 1 } }
	testing.expect_value(t, live, EMITTER_LIMIT)
}

@(test)
test_particles_interpolate_position_size_colour_and_drag :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(1)
	e.velocity = {x = 4}
	e.velocity_spread = {}
	e.drag = 1
	e.lifetime = 2
	e.start_size = 1
	e.end_size = 3
	e.start_colour = {r = 1, a = 1}
	e.end_colour = {b = 1}
	particles_burst(&p, {emitter = 1, count = 1})
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 0)
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 1)
	instances, batches := particles_frame(&p, 0.5)
	testing.expect_value(t, len(instances), 1)
	expect_v4_near(t, instances[0].position_size, {1, 0, 0, 1.5})
	expect_v4_near(t, instances[0].colour, {0.75, 0, 0.25, 0.75})
	testing.expect_value(t, batches[0].count, 1)
	testing.expect_value(t, p.particles[0].velocity.x, f32(2))
}

@(test)
test_particles_rate_credit_seed_change_and_invalid_values :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(4)
	e.rate = 3
	for _ in 0 ..< 4 { particles_step(&p, emitter_nodes([]Emitter{e}), nil, 0.125) }
	testing.expect_value(t, p.count, 1)
	e.seed = 123
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 0)
	testing.expect_value(t, p.sources[0].random, u64(123))
	e.rate = math.nan_f32()
	e.pos.x = math.inf_f32(1)
	e.lifetime = -1
	e.start_colour.a = 10
	e.end_size = -1
	c := particle_emitter_clamp(e)
	testing.expect_value(t, c.rate, f32(0))
	testing.expect_value(t, c.pos.x, f32(0))
	testing.expect_value(t, c.lifetime, f32(0.001))
	testing.expect_value(t, c.start_colour.a, f32(1))
	testing.expect_value(t, c.end_size, f32(0))
}

@(test)
test_particle_alpha_sort_with_draws_and_add_skips_sort :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	emitters := [3]Emitter{particle_test_emitter(1), particle_test_emitter(2), particle_test_emitter(3)}
	emitters[0].pos.z = 2
	emitters[1].pos.z = 8
	emitters[2].pos.z = 99
	emitters[2].blend = .Add
	for e in emitters { particles_burst(&p, {emitter = e.id, count = 1}) }
	particles_step(&p, emitter_nodes(emitters[:]), nil, 0)
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	f.fr.particles = &p
	f.fr.submits.submit_particles = particle_record_submit
	f.meshes.meshes[int(Primitive.Cube)].parts[0].material.alpha_mode = .Blend
	scene := scene_of([]Draw{{id = 1, mesh = u32(Primitive.Cube), pos = {z = 5}, scale = {1,1,1}, rot = IDENTITY, scale_rot = IDENTITY}})
	frame_fixture_draw(&f, scene, scene, 0)
	testing.expect_value(t, len(f.rec.particles), 3)
	testing.expect_value(t, f.rec.particles[0].batch.position.z, f32(8))
	testing.expect_value(t, f.rec.particles[0].before, 0)
	testing.expect_value(t, f.rec.particles[1].batch.position.z, f32(2))
	testing.expect_value(t, f.rec.particles[1].before, 1)
	testing.expect_value(t, f.rec.particles[2].batch.blend, Particle_Blend.Add)
	for blend in Particle_Blend {
		d := particle_pipeline_desc(4, blend)
		testing.expect(t, !d.depth.write_enabled && d.depth.compare == .GREATER_EQUAL)
		testing.expect_value(t, d.colors[0].blend.src_factor_rgb, sg.Blend_Factor.ONE)
		testing.expect_value(t, d.colors[0].blend.dst_factor_rgb, sg.Blend_Factor.ONE if blend == .Add else sg.Blend_Factor.ONE_MINUS_SRC_ALPHA)
	}
}

@(test)
test_particle_image_unload_omits_draining_particles_and_zero_uses_round :: proc(t: ^testing.T) {
	table: Image_Table
	image_table_init(&table, 2, context.allocator, context.allocator)
	defer image_table_destroy(&table)
	slot, _ := image_table_add(&table, "", 1, 1, nil)
	id := image_id(&table, slot)
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(1)
	e.image = id
	particles_burst(&p, {emitter = 1, count = 1})
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 0)
	particles_step(&p, nil, nil, 0.1)
	testing.expect_value(t, p.count, 1)
	testing.expect(t, p.sources[0].live && !p.sources[0].present)
	_, batches := particles_frame(&p, 1)
	testing.expect_value(t, batches[0].image, id)
	_, found := particle_image_resolve(&table, id)
	testing.expect(t, found)
	image_table_remove(&table, slot)
	image_table_add(&table, "", 1, 1, nil)
	_, stale := particle_image_resolve(&table, batches[0].image)
	testing.expect(t, !stale)
	_, round := particle_image_resolve(&table, 0)
	testing.expect(t, round)
	testing.expect(t, id in table.logged)
}

emitter_nodes :: proc(emitters: []Emitter) -> []Node {
	nodes := make([]Node, len(emitters), context.temp_allocator)
	for e, i in emitters { nodes[i] = node_emitter(e) }
	return nodes
}

node_emitter :: proc(e: Emitter) -> Node {
	return {tag = .Emitter, payload = {emitter = e}}
}

particle_test_emitter :: proc(id: u64) -> Emitter {
	return {id = id, seed = 1, lifetime = 1, start_size = 0.2, end_size = 1, start_colour = {r = 1, g = 1, b = 1, a = 0.5}, end_colour = {r = 1, g = 1, b = 1}, velocity = {y = 1}, velocity_spread = {x = 0.2, y = 0.2, z = 0.2}, time_scale = 1, blend = .Alpha}
}

@(test)
test_particle_bursts_fill_capacity_in_command_order_before_continuous_emission :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	emitters := [2]Emitter{particle_test_emitter(1), particle_test_emitter(2)}
	for &e in emitters { e.rate = PARTICLE_LIMIT }
	particles_step(&p, emitter_nodes(emitters[:]), nil, 0)
	particles_burst(&p, {emitter = 2, count = PARTICLE_LIMIT - 1})
	particles_burst(&p, {emitter = 1, count = 1})
	particles_step(&p, emitter_nodes(emitters[:]), nil, 1.0 / 120)
	testing.expect_value(t, p.count, PARTICLE_LIMIT)
	testing.expect_value(t, p.sources[0].count, 1)
	testing.expect_value(t, p.sources[1].count, PARTICLE_LIMIT - 1)
	testing.expect_value(t, p.particles[0].emitter, 1)
	testing.expect_value(t, p.particles[p.count - 1].emitter, 0)
}

particle_record_submit :: proc(ctx: rawptr, batch: Particle_Batch) {
	r := (^Recorder)(ctx)
	append(&r.particles, Particle_Recorded{batch = batch, before = len(r.submits)})
}

@(test)
test_particles_burst_queue_is_bounded_and_combines_without_overflow :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	for i in 1 ..= EMITTER_LIMIT + 1 { particles_burst(&p, {emitter = u64(i), count = 1}) }
	testing.expect_value(t, p.burst_count, EMITTER_LIMIT)
	particles_burst(&p, {emitter = 1, count = max(u32)})
	testing.expect_value(t, p.bursts[0].count, u32(PARTICLE_LIMIT))
	particles_step(&p, emitter_nodes([]Emitter{particle_test_emitter(1)}), nil, 0)
	testing.expect_value(t, p.count, PARTICLE_LIMIT)
}

@(test)
test_particles_scene_reorder_preserves_identity_and_live_settings_apply :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	emitters := [2]Emitter{particle_test_emitter(5), particle_test_emitter(6)}
	particles_burst(&p, {emitter = 5, count = 1})
	particles_step(&p, emitter_nodes(emitters[:]), nil, 0)
	random := p.sources[0].random
	emitters[0], emitters[1] = emitters[1], emitters[0]
	emitters[1].start_size = 4
	particles_step(&p, emitter_nodes(emitters[:]), nil, 0)
	instances, _ := particles_frame(&p, 0)
	testing.expect_value(t, p.sources[0].config.id, u64(5))
	testing.expect_value(t, p.sources[0].random, random)
	testing.expect_value(t, instances[0].position_size.w, f32(4))
}

@(test)
test_particles_acceleration_and_time_scale :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(1)
	e.velocity = {}
	e.velocity_spread = {}
	e.acceleration = {y = -2}
	e.lifetime = 10
	particles_burst(&p, {emitter = 1, count = 1})
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 0)
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 1)
	testing.expect_value(t, p.particles[0].velocity.y, f32(-2))
	testing.expect_value(t, p.particles[0].position.y, f32(-2))
	// A time scale of 0 holds the particle and emits nothing, however much
	// the host steps.
	e.time_scale = 0
	e.rate = 100
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 1)
	testing.expect_value(t, p.count, 1)
	testing.expect_value(t, p.particles[0].position.y, f32(-2))
	testing.expect_value(t, p.particles[0].age, f32(1))
	instances, _ := particles_frame(&p, 0.5)
	testing.expect_value(t, instances[0].position_size.y, f32(-2))
	// A time scale of 2 runs the source's clock twice as fast.
	e.time_scale = 2
	e.rate = 0
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 0.5)
	testing.expect_value(t, p.particles[0].age, f32(2))
	testing.expect_value(t, p.particles[0].velocity.y, f32(-4))
}

@(test)
test_particles_spawn_on_a_disc_round_the_source :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(1)
	e.pos = {x = 10, y = 2, z = -4}
	e.spawn_radius = 3
	particles_burst(&p, {emitter = 1, count = 400})
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 0)
	testing.expect_value(t, p.count, 400)
	far := f32(0)
	for particle in p.particles[:p.count] {
		dx, dz := particle.position.x - 10, particle.position.z + 4
		reach := math.sqrt(dx * dx + dz * dz)
		testing.expect(t, reach <= 3.0001)
		testing.expect_value(t, particle.position.y, f32(2))
		far = max(far, reach)
	}
	testing.expect(t, far > 2.5)
}

@(test)
test_particles_swirl_turns_about_the_source_and_outward_stops_at_it :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(1)
	e.pos = {x = 5, z = 5}
	e.velocity = {}
	e.velocity_spread = {}
	e.spawn_radius = 0
	e.lifetime = 100
	particles_burst(&p, {emitter = 1, count = 1})
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 0)
	p.particles[0].position = {6, 1, 5}
	// A quarter turn counter-clockwise seen from above takes +x to -z.
	e.swirl = math.PI / 2
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 1)
	got := p.particles[0].position
	testing.expect(t, abs(got.x - 5) < 1e-5 && abs(got.z - 4) < 1e-5 && got.y == 1)
	// Outward moves it straight off the line; inward stops at the line.
	e.swirl = 0
	e.outward = 2
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 1)
	testing.expect(t, abs(p.particles[0].position.z - 2) < 1e-5)
	e.outward = -10
	particles_step(&p, emitter_nodes([]Emitter{e}), nil, 1)
	testing.expect(t, abs(p.particles[0].position.z - 5) < 1e-5 && abs(p.particles[0].position.x - 5) < 1e-5)
	// The new fields clamp, and a non-finite time scale runs at 1.
	e.swirl = 5000
	e.time_scale = math.nan_f32()
	e.spawn_radius = -1
	c := particle_emitter_clamp(e)
	testing.expect_value(t, c.swirl, f32(1000))
	testing.expect_value(t, c.time_scale, f32(1))
	testing.expect_value(t, c.spawn_radius, f32(0))
}

@(test)
test_an_emitter_in_a_turned_group_spawns_at_its_world_place_with_a_turned_velocity :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(3)
	e.pos = {x = 1}
	e.velocity = {x = 2}
	e.velocity_spread = {}
	e.acceleration = {y = -10}
	e.lifetime = 10
	quarter := Quat{y = math.sin_f32(math.PI / 4), w = math.cos_f32(math.PI / 4)}
	tree := []Node{node_group(9, {x = 5}, quarter, []Node{node_emitter(e)})}
	particles_burst(&p, {emitter = 3, count = 1})
	particles_step(&p, tree, nil, 0)
	got := p.particles[0]
	testing.expect(t, abs(got.position.x - 5) < 1e-5 && abs(got.position.z + 1) < 1e-5, "the Group turns pos by a quarter turn about y")
	testing.expect(t, abs(got.velocity.x) < 1e-5 && abs(got.velocity.z + 2) < 1e-5, "velocity turns with the Group")
	particles_step(&p, tree, nil, 1)
	testing.expect(t, abs(p.particles[0].velocity.y + 10) < 1e-4, "acceleration stays in the world")
}

@(test)
test_an_emitter_that_moves_to_another_group_keeps_its_particles_and_sequence :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(3)
	e.lifetime = 10
	particles_burst(&p, {emitter = 3, count = 2})
	particles_step(&p, []Node{node_group(1, {}, IDENTITY, []Node{node_emitter(e)})}, nil, 0)
	random := p.sources[0].random
	particles_step(&p, []Node{node_group(2, {x = 4}, IDENTITY, []Node{node_emitter(e)})}, nil, 0.1)
	testing.expect_value(t, p.count, 2)
	testing.expect_value(t, p.sources[0].random, random)
	testing.expect_value(t, p.sources[0].config.pos.x, f32(4))
}

@(test)
test_emitters_with_id_0_pair_by_their_place_under_the_nearest_group_with_an_id :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	smoke := particle_test_emitter(0)
	smoke.seed = 11
	steam := particle_test_emitter(0)
	steam.seed = 22
	chimney :: proc(id: u64, e: Emitter) -> Node {
		inner := make([]Node, 1, context.temp_allocator)
		inner[0] = node_emitter(e)
		children := make([]Node, 1, context.temp_allocator)
		children[0] = node_group(0, {y = 2}, IDENTITY, inner)
		return node_group(id, {}, IDENTITY, children)
	}
	particles_step(&p, []Node{chimney(1, smoke), chimney(2, steam), node_emitter(smoke), node_emitter(steam)}, nil, 0)
	live := 0
	for source in p.sources { if source.live { live += 1 } }
	testing.expect_value(t, live, 4)
	testing.expect_value(t, p.sources[1].config.seed, u64(22))
	particles_step(&p, []Node{chimney(2, steam), chimney(1, smoke)}, nil, 0)
	testing.expect_value(t, p.sources[1].config.seed, u64(22))
	testing.expect(t, p.sources[1].present)
	particles_burst(&p, {emitter = 0, count = 5})
	particles_step(&p, []Node{chimney(2, steam), chimney(1, smoke)}, nil, 0)
	testing.expect_value(t, p.count, 0)
}

@(test)
test_particles_drain_where_they_were_after_their_group_leaves :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(3)
	e.lifetime = 10
	e.velocity = {}
	e.velocity_spread = {}
	e.swirl = 1
	particles_burst(&p, {emitter = 3, count = 1})
	particles_step(&p, []Node{node_group(1, {x = 6}, IDENTITY, []Node{node_emitter(e)})}, nil, 0)
	p.particles[0].position.x = 7
	particles_step(&p, nil, nil, 0.5)
	testing.expect_value(t, p.count, 1)
	testing.expect_value(t, p.sources[0].config.pos.x, f32(6))
	dx, dz := p.particles[0].position.x - 6, p.particles[0].position.z
	testing.expect(t, abs(dx * dx + dz * dz - 1) < 1e-4, "the swirl keeps turning about the last world place")
}

@(test)
test_continuous_spawns_spread_along_the_line_from_the_previous_world_place :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(3)
	e.lifetime = 10
	e.velocity = {}
	e.velocity_spread = {}
	e.rate = 4
	particles_step(&p, []Node{node_group(1, {}, IDENTITY, []Node{node_emitter(e)})}, nil, 0)
	particles_step(&p, []Node{node_group(1, {x = 8}, IDENTITY, []Node{node_emitter(e)})}, nil, 1)
	testing.expect_value(t, p.count, 4)
	for particle, i in p.particles[:p.count] {
		testing.expect_value(t, particle.position.x, f32(2 * (i + 1)))
	}
}

@(test)
test_an_emitter_under_an_attach_spawns_at_the_joint :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := attach_fixture_chain(&f)
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(3)
	e.pos = {x = 1}
	particles_burst(&p, {emitter = 3, count = 1})
	nodes := []Node{node_attach(1, "tip", []Node{node_emitter(e)}), node_draw({id = 1, mesh = chain, pos = {0, 0, 3}, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY})}
	particles_step(&p, nodes, &f.meshes, 0)
	testing.expect_value(t, p.count, 1)
	expect_v3_near(t, p.particles[0].position, {1, 1, 3})
}

@(test)
test_the_spawn_disc_and_the_swirl_stay_level_under_a_tilted_group :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	e := particle_test_emitter(3)
	e.pos = {y = 1}
	e.lifetime = 10
	e.velocity = {}
	e.velocity_spread = {}
	e.spawn_radius = 2
	e.swirl = 1
	tilt := Quat{x = math.sin_f32(math.PI / 4), w = math.cos_f32(math.PI / 4)}
	tree := []Node{node_group(9, {y = 3}, tilt, []Node{node_emitter(e)})}
	particles_burst(&p, {emitter = 3, count = 16})
	particles_step(&p, tree, nil, 0)
	for particle in p.particles[:p.count] {
		testing.expect(t, abs(particle.position.y - 3) < 1e-5, "the disc stays level round the world place")
		testing.expect(t, abs(particle.position.z - 1) < 2 + 1e-4, "the disc centre is the turned pos")
	}
	before := p.particles[0].position
	particles_step(&p, tree, nil, 1)
	after := p.particles[0].position
	testing.expect(t, abs(after.y - before.y) < 1e-5, "the swirl turns about an upright line")
	reach_before := math.sqrt(before.x * before.x + (before.z - 1) * (before.z - 1))
	reach_after := math.sqrt(after.x * after.x + (after.z - 1) * (after.z - 1))
	testing.expect(t, abs(reach_after - reach_before) < 1e-4, "the swirl keeps the reach from the world place")
}
