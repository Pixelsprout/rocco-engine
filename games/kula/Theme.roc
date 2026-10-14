import linalg.Vec3
import pf.Vocabulary exposing [Rgb]
import pf.Light
import Level

# The look of one level. Each Theme is a pack, so the next level's Theme loads
# while the current one still draws.
Theme := [].{
	Theme : { pack : Str, assets : List(Str), sun : Vec3.Vec3, lights : List(Vocabulary.Light), block_tint : Rgb }

	# Levels count from 1. A number past the last level gets the last Theme.
	of_level : U64 -> Theme.Theme
	of_level = |number| themes.get(number - 1) ?? arctic

	count : U64
	count = themes.len()
}

themes : List(Theme.Theme)
themes = [haze, inca, arctic]

haze : Theme.Theme
haze = theme("haze", { x: -2.0 / 7.0, y: -6.0 / 7.0, z: -3.0 / 7.0 }, grey(1.6), { r: 0.45, g: 0.5, b: 0.6 })

inca : Theme.Theme
inca = theme("inca", { x: 3.0 / 7.0, y: -6.0 / 7.0, z: -2.0 / 7.0 }, { r: 1.9, g: 1.6, b: 1.2 }, { r: 0.72, g: 0.55, b: 0.36 })

arctic : Theme.Theme
arctic = theme("arctic", { x: -3.0 / 7.0, y: -6.0 / 7.0, z: 2.0 / 7.0 }, { r: 1.2, g: 1.35, b: 1.6 }, { r: 0.62, g: 0.75, b: 0.85 })

# No two axes of a sun's dir share a size, so each face direction gets its own shade.
# The BRDF divides diffuse light by pi, so a sun of 1.6 lights a white surface facing it to 1.6.
theme : Str, Vec3.Vec3, Rgb, Rgb -> Theme.Theme
theme = |pack, sun, sun_rgb, block_tint| {
	pack,
	assets: ["face"],
	sun,
	lights: [
		Light.ambient(grey(0.15)),
		Light.directional(sun, times_pi(sun_rgb)),
		Light.directional(Vec3.neg(sun), times_pi(grey(0.3))),
	],
	block_tint,
}

grey : F32 -> Rgb
grey = |v| { r: v, g: v, b: v }

times_pi : Rgb -> Rgb
times_pi = |c| { r: c.r * pi, g: c.g * pi, b: c.b * pi }

pi : F32
pi = 3.14159265

# The sum of all lights on a face with this normal, over the three channels.
shade : List(Vocabulary.Light), Vec3.Vec3 -> F32
shade = |lights, normal| lights.fold(0.0, |sum, light| match light {
	Ambient(c) => sum + c.r + c.g + c.b
	Directional({ dir, color }) => {
		facing = Vec3.dot(normal, Vec3.neg(dir))
		if facing > 0.0 { sum + (color.r + color.g + color.b) * facing } else { sum }
	}
	Point(_) => sum
})

normals : List(Vec3.Vec3)
normals = [{ x: 1.0, y: 0.0, z: 0.0 }, { x: -1.0, y: 0.0, z: 0.0 }, { x: 0.0, y: 1.0, z: 0.0 }, { x: 0.0, y: -1.0, z: 0.0 }, { x: 0.0, y: 0.0, z: 1.0 }, { x: 0.0, y: 0.0, z: -1.0 }]

expect Theme.count == Level.count
expect themes.map(|t| t.pack) == ["haze", "inca", "arctic"]
expect Theme.of_level(1).pack == "haze" and Theme.of_level(3).pack == "arctic" and Theme.of_level(4).pack == "arctic"

expect themes.all(|t| {
	shades = normals.map(|n| shade(t.lights, n))
	shades.all(|a| shades.keep_if(|b| (a - b).abs() < 0.06).len() == 1)
})

expect themes.all(|a| themes.keep_if(|b| b.block_tint == a.block_tint or b.sun == a.sun).len() == 1)
