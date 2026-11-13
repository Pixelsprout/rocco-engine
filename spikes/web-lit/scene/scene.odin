// The glow Scene of examples/glow/main.roc at time 0, plus one cube that
// draws with the IndirectSurface pack of examples/surface. The web host and
// the native twin both build it here. The slice collection names the
// engine: the slice copy on the web, the real engine natively.
package lit_scene

import "core:math"
import engine "slice:engine"

WIDTH :: 1280
HEIGHT :: 720
PROPS :: "props"
SURFACES :: "surfaces"
SURFACE_SHADER :: "shader/IndirectSurface"
CUBE :: u32(1)
SPHERE :: u32(2)
PLANE :: u32(3)
BLOOM_STRENGTH :: f32(0.2)
// The glue orders record fields by name, so Rgb and Quat literals name them.
IDENTITY :: engine.Quat{w = 1}

@(rodata)
PROP_ASSETS := [3]string{"salvage", "panel", "tube"}
@(rodata)
SURFACE_ASSETS := [1]string{SURFACE_SHADER}

// The mesh ids that the props Load gives. 0 draws the fallback mesh.
Meshes :: struct {
	salvage, panel, tube: u32,
}

// Window.samples X4, as in pf.Launch.default. DPI 1 on both sides.
launch :: proc() -> engine.Launch {
	l := engine.launch_default()
	l.window.width = WIDTH
	l.window.height = HEIGHT
	l.window.high_dpi = false
	return l
}

meshes_from :: proc(m: ^Meshes, lines: []engine.Manifest_Line) {
	for line in lines {
		switch line.name {
		case "salvage":
			m.salvage = line.id
		case "panel":
			m.panel = line.id
		case "tube":
			m.tube = line.id
		}
	}
}

// The lists come from the Roc heap, so the native seam can decref the Scene.
view :: proc(m: Meshes) -> engine.Scene {
	panel_centre := engine.Vec3{-1.35, 1.5, -1.35}
	tube_centre := engine.Vec3{1.6, 0.55, 0.4}
	spark_pos := engine.Vec3{panel_centre.x + 0.5, panel_centre.y, panel_centre.z + 0.02 + 0.4}
	spark_colour := rgb(1.2, 1.0, 0.75)

	nodes := [?]engine.Node {
		light_node(ambient(rgb(0.02, 0.02, 0.03))),
		light_node(sun({-0.25, -1.0, 0.7}, rgb(0.6, 0.55, 0.5))),
		draw_node(draw(1, PLANE, pos = {}, scale = {8, 1, 8}, tint = rgb(0.6, 0.6, 0.6))),
		draw_node(draw(2, CUBE, pos = {0, 1.2, -1.5}, scale = {4, 2.4, 0.3}, tint = rgb(0.40, 0.11, 0.05))),
		draw_node(draw(3, CUBE, pos = {0, 1.4, -1.33}, scale = {1.4, 0.6, 0.06}, tint = rgb(0.02, 0.018, 0.015), glow = rgb(3.2, 1.9, 0.6))),
		draw_node(draw(4, m.salvage, pos = {0, 0, -0.3}, scale = {1.3, 1.3, 1.3}, rot = yaw(-0.5))),
		draw_node(draw(5, m.panel, pos = panel_centre)),
		light_node(point({0.4, 2.2, -1.0}, rgb(2.0, 1.9, 1.7), 4)),
		draw_node(orb(10, {-1.6, 0.5, 0.4}, rgb(1.0, 0.55, 0.05))),
		light_node(point({-1.6, 0.5, 0.4}, rgb(3.0, 1.65, 0.15), 4)),
		draw_node(orb(11, tube_centre, rgb(0.15, 0.35, 1.0))),
		light_node(point(tube_centre, rgb(0.45, 1.05, 3.0), 4)),
		draw_node(draw(7, m.tube, pos = tube_centre)),
		draw_node(draw(6, SPHERE, pos = spark_pos, scale = {0.08, 0.08, 0.08}, tint = rgb(1.0, 0.9, 0.7), glow = rgb(3.6, 3.0, 2.25))),
		light_node(point(spark_pos, spark_colour, 2)),
		draw_node(surface_cube(20)),
	}
	return {
		nodes = engine.roc_list_from_slice(nodes[:]),
		camera = {eye = {0, 2.4, 5}, target = {0, 0.8, 0}, up = {0, 1, 0}, fov_y = 1.047},
		environment = {
			clear = {},
			tone_map = .Aces,
			exposure = 1,
			fog = {color = rgb(0.5, 0.5, 0.5), start = 10, end = 50},
			bloom = {strength = BLOOM_STRENGTH, threshold = 2, knee = 0.5},
		},
		shadow = {normal_bias = 0.05, distribution = 0.5, blend = 0.1, filter = .Pcf3},
		cursor = .Free,
	}
}

// pf.Draw.default with the given fields.
draw :: proc(
	id: u64,
	mesh: u32,
	pos: engine.Vec3,
	scale := engine.Vec3{1, 1, 1},
	rot := IDENTITY,
	tint := engine.Rgb{r = 1, g = 1, b = 1},
	glow := engine.Rgb{},
) -> engine.Draw {
	return {id = id, mesh = mesh, pos = pos, scale = scale, rot = rot, scale_rot = IDENTITY, tint = tint, glow = glow, casts_shadow = true}
}

orb :: proc(id: u64, pos: engine.Vec3, colour: engine.Rgb) -> engine.Draw {
	lit := rgb(colour.r * 3, colour.g * 3, colour.b * 3)
	return draw(id, SPHERE, pos = pos, scale = {0.5, 0.5, 0.5}, tint = colour, glow = lit)
}

// A green cube right of the tube with the IndirectSurface defaults.
surface_cube :: proc(id: u64) -> engine.Draw {
	d := draw(id, CUBE, pos = {2.7, 0.4, 1.0}, scale = {0.8, 0.8, 0.8}, rot = yaw(0.6), tint = rgb(0.3, 0.8, 0.4))
	d.material.surface.tag = .Surface
	d.material.surface.payload.surface = {
		shader = {pack = engine.roc_str_from_slice(SURFACES), asset = engine.roc_str_from_slice(SURFACE_SHADER)},
		scope = .Material,
	}
	return d
}

rgb :: proc(r, g, b: f32) -> engine.Rgb {
	return {r = r, g = g, b = b}
}

// Quat.from_yaw: a turn about +y.
yaw :: proc(angle: f32) -> engine.Quat {
	return {y = math.sin(angle / 2), w = math.cos(angle / 2)}
}

ambient :: proc(colour: engine.Rgb) -> engine.Light {
	return {tag = .Ambient, payload = {ambient = colour}}
}

sun :: proc(dir: engine.Vec3, colour: engine.Rgb) -> engine.Light {
	return {tag = .Directional, payload = {directional = {dir = dir, color = colour, shadow = true}}}
}

point :: proc(pos: engine.Vec3, colour: engine.Rgb, range: f32) -> engine.Light {
	return {tag = .Point, payload = {point = {pos = pos, color = colour, range = range}}}
}

light_node :: proc(l: engine.Light) -> engine.Node {
	return {tag = .Light, payload = {light = l}}
}

draw_node :: proc(d: engine.Draw) -> engine.Node {
	return {tag = .Draw, payload = {draw = d}}
}
