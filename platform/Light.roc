import Vocabulary exposing [Rgb, Vec3]

## Builds the Lights that your game returns in `Scene.lights`. A colour carries
## its intensity and can exceed 1.
Light := [].{

	## Light from all directions.
	ambient : Rgb -> Vocabulary.Light
	ambient = |color| Ambient(color)

	## Light that travels along `dir` and casts no shadow.
	directional : Vec3, Rgb -> Vocabulary.Light
	directional = |dir, color| Directional({ dir, color, shadow: False })

	## A Directional light that casts a shadow. Only the first Sun in the list
	## casts one.
	sun : Vec3, Rgb -> Vocabulary.Light
	sun = |dir, color| Directional({ dir, color, shadow: True })

	## Light from `pos` that falls off to zero at `range`.
	point : Vec3, Rgb, F32 -> Vocabulary.Light
	point = |pos, color, range| Point({ pos, color, range })
}

grey : Rgb
grey = { r: 0.1, g: 0.1, b: 0.1 }

expect Light.ambient(grey) == Ambient(grey)
expect Light.directional({ x: 0.0, y: -1.0, z: 0.0 }, grey) == Directional({ dir: { x: 0.0, y: -1.0, z: 0.0 }, color: grey, shadow: False })
expect Light.sun({ x: 0.0, y: -1.0, z: 0.0 }, grey) == Directional({ dir: { x: 0.0, y: -1.0, z: 0.0 }, color: grey, shadow: True })
expect Light.point({ x: 1.0, y: 2.0, z: 3.0 }, grey, 6.0) == Point({ pos: { x: 1.0, y: 2.0, z: 3.0 }, color: grey, range: 6.0 })
