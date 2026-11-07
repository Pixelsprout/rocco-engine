package engine

import "core:math"
import "core:mem"

PARTICLE_LIMIT :: 8192
EMITTER_LIMIT :: 128

Particle :: struct {
	position, previous, velocity: [3]f32,
	age, previous_age: f32,
	emitter: int,
}

Particle_Source :: struct {
	config: Emitter,
	random: u64,
	credit: f64,
	live, present: bool,
	count: int,
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

particles_step :: proc(p: ^Particles, emitters: []Emitter, dt: f32) {
	if p == nil || len(p.sources) == 0 { return }
	for &source in p.sources { source.present = false; source.count = 0 }
	for emitter in emitters {
		slot := -1
		for source, i in p.sources {
			if source.live && source.config.id == emitter.id { slot = i; break }
		}
		if slot < 0 {
			for source, i in p.sources {
				if !source.live { slot = i; break }
			}
		}
		if slot < 0 || p.sources[slot].present { continue }
		source := &p.sources[slot]
		if !source.live || source.config.seed != emitter.seed { source.random = emitter.seed }
		source.config = particle_emitter_clamp(emitter)
		source.live = true
		source.present = true
	}
	write := 0
	for item in p.particles[:p.count] {
		particle := item
		source := &p.sources[particle.emitter]
		particle.previous = particle.position
		particle.previous_age = particle.age
		particle.age += dt
		if particle.age >= source.config.lifetime { continue }
		particle.velocity *= 1 / (1 + source.config.drag * dt)
		particle.position += particle.velocity * dt
		p.particles[write] = particle
		write += 1
		source.count += 1
	}
	p.count = write
	for burst in p.bursts[:p.burst_count] {
		for &source, slot in p.sources {
			if source.present && source.config.id == burst.emitter {
				particles_spawn(p, slot, int(burst.count))
				break
			}
		}
	}
	p.burst_count = 0
	for &source, slot in p.sources {
		if !source.live { continue }
		if source.present {
			source.credit += f64(source.config.rate) * f64(dt)
			count := int(math.floor(source.credit))
			source.credit -= f64(count)
			particles_spawn(p, slot, count)
		} else {
			source.credit = 0
			if source.count == 0 { source = {} }
		}
	}
}

particles_spawn :: proc(p: ^Particles, slot, count: int) {
	source := &p.sources[slot]
	e := source.config
	spawn_count := min(count, len(p.particles) - p.count)
	for _ in 0 ..< spawn_count {
		velocity := [3]f32{e.velocity.x, e.velocity.y, e.velocity.z}
		spread := [3]f32{e.velocity_spread.x, e.velocity_spread.y, e.velocity_spread.z}
		for axis in 0 ..< 3 { velocity[axis] += particle_random(&source.random) * spread[axis] }
		position := [3]f32{e.position.x, e.position.y, e.position.z}
		p.particles[p.count] = {position = position, previous = position, velocity = velocity, emitter = slot}
		p.count += 1
		source.count += 1
	}
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
	e.position = particle_vector_clamp(e.position, {}, -1000000)
	e.velocity = particle_vector_clamp(e.velocity, {y = 1}, -1000000)
	e.velocity_spread = particle_vector_clamp(e.velocity_spread, {x = 0.2, y = 0.2, z = 0.2}, 0)
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
		append(&batches, Particle_Batch{position = {e.position.x, e.position.y, e.position.z}, start = write, count = source.count, image = e.image, blend = e.blend})
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
