import Vocabulary exposing [Rgb, Vec3]

# Builds the Lights a game returns in its Scene.
Light := [].{
	ambient : Rgb -> Vocabulary.Light
	ambient = |color| Ambient(color)

	directional : Vec3, Rgb -> Vocabulary.Light
	directional = |dir, color| Directional({ dir, color, shadow: False })

	sun : Vec3, Rgb -> Vocabulary.Light
	sun = |dir, color| Directional({ dir, color, shadow: True })

	point : Vec3, Rgb, F32 -> Vocabulary.Light
	point = |pos, color, range| Point({ pos, color, range })
}

grey : Rgb
grey = { r: 0.1, g: 0.1, b: 0.1 }

expect Light.ambient(grey) == Ambient(grey)
expect Light.directional({ x: 0.0, y: -1.0, z: 0.0 }, grey) == Directional({ dir: { x: 0.0, y: -1.0, z: 0.0 }, color: grey, shadow: False })
expect Light.sun({ x: 0.0, y: -1.0, z: 0.0 }, grey) == Directional({ dir: { x: 0.0, y: -1.0, z: 0.0 }, color: grey, shadow: True })
expect Light.point({ x: 1.0, y: 2.0, z: 3.0 }, grey, 6.0) == Point({ pos: { x: 1.0, y: 2.0, z: 3.0 }, color: grey, range: 6.0 })
