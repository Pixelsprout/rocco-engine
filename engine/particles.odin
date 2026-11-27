package engine

import "core:math"
import "core:math/linalg"
import "core:mem"
import "system"

PARTICLE_LIMIT :: 8192
EMITTER_LIMIT :: 128

Particle :: struct {
	position, previous, velocity: [3]f32,
	age, previous_age: f32,
	emitter: int,
}

// An Emitter with a non-zero id pairs by id alone. One with id 0 pairs by its
// anchor and its index among the id-0 Emitters under that anchor.
Emitter_Key :: struct {
	id:     u64,
	anchor: Parent_Id,
	index:  int,
}

// config holds the Emitter at its world place. rot is its world rot, which
// turns velocity and velocity_spread. from is the world place of the previous
// step, the start of the line that continuous spawns spread along.
Particle_Source :: struct {
	config: Emitter,
	key:    Emitter_Key,
	rot:    quaternion128,
	from:   [3]f32,
	random: u64,
	credit: f64,
	live, present, was_present: bool,
	count: int,
}

Placed_Emitter :: struct {
	emitter: Emitter,
	key:     Emitter_Key,
	world:   Pose,
}

Emitter_Gather :: struct {
	placed:         [dynamic]Placed_Emitter,
	zero_id_counts: [dynamic]Zero_Id_Count,
}

Zero_Id_Count :: struct {
	anchor: Parent_Id,
	count:  int,
}

Particle_Instance :: struct {
	position_size: [4]f32,
	colour: [4]f32,
}

Particle_Batch :: struct {
	position: [3]f32,
	start, count: int,
	image: u32,
	blend: Particle_Blend,
}

Particles :: struct {
	sources: []Particle_Source,
	particles: []Particle,
	count: int,
	bursts: [EMITTER_LIMIT]Burst_Command,
	burst_count: int,
	duplicate_logged: bool,
	allocator: mem.Allocator,
}

particles_init :: proc(p: ^Particles, allocator: mem.Allocator) {
	p.allocator = allocator
	p.sources = make([]Particle_Source, EMITTER_LIMIT, allocator)
	p.particles = make([]Particle, PARTICLE_LIMIT, allocator)
}

particles_destroy :: proc(p: ^Particles) {
	delete(p.sources, p.allocator)
	delete(p.particles, p.allocator)
}

particles_burst :: proc(p: ^Particles, burst: Burst_Command) {
	if p == nil || len(p.sources) == 0 { return }
	for &pending in p.bursts[:p.burst_count] {
		if pending.emitter == burst.emitter {
			pending.count = u32(min(u64(pending.count) + u64(burst.count), PARTICLE_LIMIT))
			return
		}
	}
	if p.burst_count < len(p.bursts) {
		p.bursts[p.burst_count] = burst
		p.bursts[p.burst_count].count = min(burst.count, PARTICLE_LIMIT)
		p.burst_count += 1
	}
}

// Runs after each view on the current Scene's Nodes. The world places come
// from the walked Scene, with no interpolation.
particles_step :: proc(p: ^Particles, nodes: []Node, meshes: ^Mesh_Table, dt: f32) {
	if p == nil || len(p.sources) == 0 { return }
	for &source in p.sources {
		source.was_present = source.present
		source.present = false
		source.count = 0
	}
	for placed in emitters_gather(nodes, meshes) {
		slot := -1
		for source, i in p.sources {
			if source.live && source.key == placed.key { slot = i; break }
		}
		if slot < 0 {
			for source, i in p.sources {
				if !source.live { slot = i; break }
			}
		}
		if slot < 0 { continue }
		source := &p.sources[slot]
		if source.present {
			if !p.duplicate_logged {
				p.duplicate_logged = true
				system.eprintfln("two emitters share id %v; the first one emits", placed.key.id)
			}
			continue
		}
		if !source.live || source.config.seed != placed.emitter.seed { source.random = placed.emitter.seed }
		config := particle_emitter_clamp(placed.emitter)
		config.pos = particle_vector_clamp(to_vec3(placed.world.pos), {}, -1000000)
		source.from = vec3_array(source.config.pos if source.was_present else config.pos)
		source.config = config
		source.key = placed.key
		source.rot = placed.world.rot
		source.live = true
		source.present = true
	}
	write := 0
	for item in p.particles[:p.count] {
		particle := item
		source := &p.sources[particle.emitter]
		e := source.config
		step := dt * e.time_scale
		particle.previous = particle.position
		particle.previous_age = particle.age
		particle.age += step
		if particle.age >= e.lifetime { continue }
		particle.velocity += [3]f32{e.acceleration.x, e.acceleration.y, e.acceleration.z} * step
		particle.velocity *= 1 / (1 + e.drag * step)
		particle.position += particle.velocity * step
		particle.position = particle_about_axis(particle.position, e, step)
		p.particles[write] = particle
		write += 1
		source.count += 1
	}
	p.count = write
	for burst in p.bursts[:p.burst_count] {
		if burst.emitter == 0 { continue }
		for &source, slot in p.sources {
			if source.present && source.key.id == burst.emitter {
				particles_spawn(p, slot, int(burst.count), along_line = false)
				break
			}
		}
	}
	p.burst_count = 0
	for &source, slot in p.sources {
		if !source.live { continue }
		if source.present {
			source.credit += f64(source.config.rate) * f64(dt * source.config.time_scale)
			count := int(math.floor(source.credit))
			source.credit -= f64(count)
			particles_spawn(p, slot, count, along_line = true)
		} else {
			source.credit = 0
			if source.count == 0 { source = {} }
		}
	}
}

// Along the line from the previous world place, a fast Emitter leaves an even
// trail and not a clump at each step.
particles_spawn :: proc(p: ^Particles, slot, count: int, along_line: bool) {
	source := &p.sources[slot]
	e := source.config
	spawn_count := min(count, len(p.particles) - p.count)
	for k in 0 ..< spawn_count {
		velocity := vec3_array(e.velocity)
		spread := vec3_array(e.velocity_spread)
		for axis in 0 ..< 3 { velocity[axis] += particle_random(&source.random) * spread[axis] }
		velocity = linalg.quaternion128_mul_vector3(source.rot, velocity)
		position := vec3_array(e.pos)
		if along_line { position = linalg.lerp(source.from, position, f32(k + 1) / f32(spawn_count)) }
		if e.spawn_radius > 0 {
			angle := (particle_random(&source.random) + 1) * math.PI
			reach := e.spawn_radius * math.sqrt((particle_random(&source.random) + 1) / 2)
			position.x += reach * math.cos(angle)
			position.z += reach * math.sin(angle)
		}
		p.particles[p.count] = {position = position, previous = position, velocity = velocity, emitter = slot}
		p.count += 1
		source.count += 1
	}
}

// Each Emitter of the Scene at its world Pose, in walk order, in the Frame
// allocator.
emitters_gather :: proc(nodes: []Node, meshes: ^Mesh_Table) -> []Placed_Emitter {
	gather := Emitter_Gather {
		placed         = make([dynamic]Placed_Emitter, 0, 8, context.temp_allocator),
		zero_id_counts = make([dynamic]Zero_Id_Count, 0, 4, context.temp_allocator),
	}
	joints := Scene_Joints{meshes, nodes}
	walk := Tree_Walk {
		visit           = emitter_visit,
		data            = &gather,
		joint_pose      = scene_attach_joint,
		joint_pose_data = &joints,
	}
	root := WALK_ROOT
	for &node, i in nodes {
		#partial switch node.tag {
		case .Emitter:
			emitter_place(&gather, node.payload.emitter, &root)
		case .Group, .Attach:
			tree_walk(&walk, nodes[i:i + 1], &root)
		}
	}
	tree_walk_attached(&walk)
	return gather.placed[:]
}

@(private = "file")
emitter_visit :: proc(walk: ^Tree_Walk, node: ^Node, parent: ^Walk_Parent) {
	if node.tag == .Emitter {
		emitter_place((^Emitter_Gather)(walk.data), node.payload.emitter, parent)
	}
}

@(private = "file")
emitter_place :: proc(gather: ^Emitter_Gather, e: Emitter, parent: ^Walk_Parent) {
	key := Emitter_Key{id = e.id}
	if e.id == 0 {
		key.anchor = parent.anchor
		found := false
		for &zero in gather.zero_id_counts {
			if zero.anchor == parent.anchor {
				key.index = zero.count
				zero.count += 1
				found = true
				break
			}
		}
		if !found { append(&gather.zero_id_counts, Zero_Id_Count{anchor = parent.anchor, count = 1}) }
	}
	world := pose_under(parent.id.grouped, parent.scene_world, {pos = vec3_array(e.pos), rot = 1})
	append(&gather.placed, Placed_Emitter{emitter = e, key = key, world = world})
}

// The swirl and the outward drift: the particle's place turned about the
// upright line through the Emitter's world place by `swirl` radians a second,
// counter-clockwise seen from above, and moved `outward` metres a second away
// from that line, never past it.
particle_about_axis :: proc(position: [3]f32, e: Emitter, step: f32) -> [3]f32 {
	if e.swirl == 0 && e.outward == 0 { return position }
	offset := [2]f32{position.x - e.pos.x, position.z - e.pos.z}
	reach := math.sqrt(offset.x * offset.x + offset.y * offset.y)
	if reach == 0 { return position }
	turn := e.swirl * step
	c, s := math.cos(turn), math.sin(turn)
	turned := [2]f32{offset.x * c + offset.y * s, -offset.x * s + offset.y * c}
	moved := turned * (max(0, reach + e.outward * step) / reach)
	return {e.pos.x + moved.x, position.y, e.pos.z + moved.y}
}

// SplitMix64 accepts every seed, including zero, without a zero-state trap.
particle_random :: proc(state: ^u64) -> f32 {
	state^ += 0x9e3779b97f4a7c15
	z := state^
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	z = z ~ (z >> 31)
	return f32(z >> 40) / f32(0xffffff) * 2 - 1
}

particle_emitter_clamp :: proc(input: Emitter) -> Emitter {
	e := input
	if e.blend != .Alpha && e.blend != .Add { e.blend = .Alpha }
	e.rate = particle_finite(e.rate, 0, 0, PARTICLE_LIMIT)
	e.lifetime = particle_finite(e.lifetime, 1, 0.001, 3600)
	e.drag = particle_finite(e.drag, 0, 0, 1000000)
	e.start_size = particle_finite(e.start_size, 0.2, 0, 1000000)
	e.end_size = particle_finite(e.end_size, 1, 0, 1000000)
	e.start_colour = particle_colour_clamp(e.start_colour, 0.5)
	e.end_colour = particle_colour_clamp(e.end_colour, 0)
	e.pos = particle_vector_clamp(e.pos, {}, -1000000)
	e.velocity = particle_vector_clamp(e.velocity, {y = 1}, -1000000)
	e.velocity_spread = particle_vector_clamp(e.velocity_spread, {x = 0.2, y = 0.2, z = 0.2}, 0)
	e.acceleration = particle_vector_clamp(e.acceleration, {}, -1000000)
	e.spawn_radius = particle_finite(e.spawn_radius, 0, 0, 1000000)
	e.swirl = particle_finite(e.swirl, 0, -1000, 1000)
	e.outward = particle_finite(e.outward, 0, -1000000, 1000000)
	e.time_scale = particle_finite(e.time_scale, 1, 0, 100)
	return e
}

particle_vector_clamp :: proc(v, fallback: Vec3, lo: f32) -> Vec3 {
	return {x = particle_finite(v.x, fallback.x, lo, 1000000), y = particle_finite(v.y, fallback.y, lo, 1000000), z = particle_finite(v.z, fallback.z, lo, 1000000)}
}

particle_colour_clamp :: proc(c: Rgba, alpha: f32) -> Rgba {
	return {r = particle_finite(c.r, 1, 0, 65504), g = particle_finite(c.g, 1, 0, 65504), b = particle_finite(c.b, 1, 0, 65504), a = particle_finite(c.a, alpha, 0, 1)}
}

particle_finite :: proc(v, fallback, lo, hi: f32) -> f32 {
	return fallback if math.is_nan(v) || math.is_inf(v) else clamp(v, lo, hi)
}

particles_frame :: proc(p: ^Particles, alpha: f32) -> ([]Particle_Instance, []Particle_Batch) {
	if p == nil || p.count == 0 { return nil, nil }
	instances := make([]Particle_Instance, p.count, context.temp_allocator)
	batches := make([dynamic]Particle_Batch, 0, EMITTER_LIMIT, context.temp_allocator)
	write := 0
	offsets: [EMITTER_LIMIT]int
	for source, slot in p.sources {
		if source.count == 0 { continue }
		e := source.config
		offsets[slot] = write
		append(&batches, Particle_Batch{position = {e.pos.x, e.pos.y, e.pos.z}, start = write, count = source.count, image = e.image, blend = e.blend})
		write += source.count
	}
	for particle in p.particles[:p.count] {
		e := p.sources[particle.emitter].config
		age := particle.previous_age + (particle.age - particle.previous_age) * alpha
		t := clamp(age / e.lifetime, 0, 1)
		position := particle.previous + (particle.position - particle.previous) * alpha
		size := e.start_size + (e.end_size - e.start_size) * t
		a, b := e.start_colour, e.end_colour
		index := offsets[particle.emitter]
		instances[index] = {position_size = {position.x, position.y, position.z, size}, colour = {a.r + (b.r-a.r)*t, a.g + (b.g-a.g)*t, a.b + (b.b-a.b)*t, a.a + (b.a-a.a)*t}}
		offsets[particle.emitter] += 1
	}
	return instances, batches[:]
}
