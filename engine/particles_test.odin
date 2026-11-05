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
		particles_step(&a, emitters[:], 1.0/120)
		particles_step(&b, emitters[:], 1.0/120)
	}
	testing.expect_value(t, a.count, b.count)
	for particle, i in a.particles[:a.count] { testing.expect_value(t, particle, b.particles[i]) }
	random := a.sources[0].random
	particles_step(&a, nil, 0)
	testing.expect(t, a.sources[0].live && !a.sources[0].present)
	emitters[1] = emitters[0]
	emitters[1].position.x = 99
	particles_step(&a, emitters[:], 0)
	testing.expect_value(t, a.sources[0].config.position.x, f32(0))
	testing.expect_value(t, a.sources[0].random, random)
	particles_step(&a, nil, 2)
	testing.expect_value(t, a.count, 0)
	testing.expect(t, !a.sources[0].live)
	particles_step(&a, emitters[:1], 0)
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
	particles_step(&p, emitters[:], 0)
	testing.expect_value(t, p.count, PARTICLE_LIMIT)
	testing.expect_value(t, p.sources[1].count, 0)
	testing.expect_value(t, p.burst_count, 0)
	particles_step(&p, nil, 2)
	particles_burst(&p, {emitter = 1, count = 10})
	particles_step(&p, nil, 0)
	testing.expect_value(t, p.count, 0)
	many := make([]Emitter, EMITTER_LIMIT + 1, context.temp_allocator)
	for &e, i in many { e = particle_test_emitter(u64(i)) }
	particles_step(&p, many, 0)
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
	particles_step(&p, []Emitter{e}, 0)
	particles_step(&p, []Emitter{e}, 1)
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
	for _ in 0 ..< 4 { particles_step(&p, []Emitter{e}, 0.125) }
	testing.expect_value(t, p.count, 1)
	e.seed = 123
	particles_step(&p, []Emitter{e}, 0)
	testing.expect_value(t, p.sources[0].random, u64(123))
	e.rate = math.nan_f32()
	e.position.x = math.inf_f32(1)
	e.lifetime = -1
	e.start_colour.a = 10
	e.end_size = -1
	c := particle_emitter_clamp(e)
	testing.expect_value(t, c.rate, f32(0))
	testing.expect_value(t, c.position.x, f32(0))
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
	emitters[0].position.z = 2
	emitters[1].position.z = 8
	emitters[2].position.z = 99
	emitters[2].blend = .Add
	for e in emitters { particles_burst(&p, {emitter = e.id, count = 1}) }
	particles_step(&p, emitters[:], 0)
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
	particles_step(&p, []Emitter{e}, 0)
	particles_step(&p, nil, 0.1)
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

particle_test_emitter :: proc(id: u64) -> Emitter {
	return {id = id, seed = 1, lifetime = 1, start_size = 0.2, end_size = 1, start_colour = {r = 1, g = 1, b = 1, a = 0.5}, end_colour = {r = 1, g = 1, b = 1}, velocity = {y = 1}, velocity_spread = {x = 0.2, y = 0.2, z = 0.2}, blend = .Alpha}
}

@(test)
test_particle_bursts_fill_capacity_in_command_order_before_continuous_emission :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	emitters := [2]Emitter{particle_test_emitter(1), particle_test_emitter(2)}
	for &e in emitters { e.rate = PARTICLE_LIMIT }
	particles_step(&p, emitters[:], 0)
	particles_burst(&p, {emitter = 2, count = PARTICLE_LIMIT - 1})
	particles_burst(&p, {emitter = 1, count = 1})
	particles_step(&p, emitters[:], 1.0 / 120)
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
	for i in 0 ..< EMITTER_LIMIT + 1 { particles_burst(&p, {emitter = u64(i), count = 1}) }
	testing.expect_value(t, p.burst_count, EMITTER_LIMIT)
	particles_burst(&p, {emitter = 0, count = max(u32)})
	testing.expect_value(t, p.bursts[0].count, u32(PARTICLE_LIMIT))
	particles_step(&p, []Emitter{particle_test_emitter(0)}, 0)
	testing.expect_value(t, p.count, PARTICLE_LIMIT)
}

@(test)
test_particles_scene_reorder_preserves_identity_and_live_settings_apply :: proc(t: ^testing.T) {
	p: Particles
	particles_init(&p, context.allocator)
	defer particles_destroy(&p)
	emitters := [2]Emitter{particle_test_emitter(5), particle_test_emitter(6)}
	particles_burst(&p, {emitter = 5, count = 1})
	particles_step(&p, emitters[:], 0)
	random := p.sources[0].random
	emitters[0], emitters[1] = emitters[1], emitters[0]
	emitters[1].start_size = 4
	particles_step(&p, emitters[:], 0)
	instances, _ := particles_frame(&p, 0)
	testing.expect_value(t, p.sources[0].config.id, u64(5))
	testing.expect_value(t, p.sources[0].random, random)
	testing.expect_value(t, instances[0].position_size.w, f32(4))
}
