import Vocabulary exposing [Rgb, Vec3]
import Draw

## Builds Nodes that glow. A glow lights no other surface, so a thing that
## should light the Scene around it also needs a Light.
Glow := [].{

	## A sphere of `radius` at `pos` that glows `color` times `strength`, and a
	## Point Light at its centre with the same colour, which falls off to zero
	## at `range`. `id` is the sphere's draw id. The tint is `color`, so other
	## Lights shade the sphere in its own colour. The Light counts toward the
	## Lights of the Scene.
	orb : { id : U64, pos : Vec3, radius : F32, color : Rgb, strength : F32, range : F32 } -> List(Vocabulary.Node)
	orb = |{ id, pos, radius, color, strength, range }| {
		lit = { r: color.r * strength, g: color.g * strength, b: color.b * strength }
		diameter = radius * 2.0
		sphere_draw = { ..Draw.default, id, mesh: sphere, pos, scale: { x: diameter, y: diameter, z: diameter }, tint: color, glow: lit }
		[Draw(sphere_draw), Light(Point({ pos, color: lit, range }))]
	}
}

# The Sphere Primitive's fixed mesh id. examples/glow checks it against Mesh.primitive(Sphere).
sphere : U32
sphere = 2

amber : Rgb
amber = { r: 1.0, g: 0.5, b: 0.1 }

lamp : List(Vocabulary.Node)
lamp = Glow.orb({ id: 9, pos: { x: 1.0, y: 2.0, z: 3.0 }, radius: 0.25, color: amber, strength: 4.0, range: 6.0 })

## The orb is one sphere Draw and then one Point Light.
expect lamp.len() == 2

## The sphere glows the colour times the strength and keeps the colour as its tint.
expect lamp.first() == Ok(Draw({ ..Draw.default, id: 9, mesh: 2, pos: { x: 1.0, y: 2.0, z: 3.0 }, scale: { x: 0.5, y: 0.5, z: 0.5 }, tint: amber, glow: { r: 4.0, g: 2.0, b: 0.4 } }))

## The Light sits at the centre with the glow's colour and the range.
expect lamp.last() == Ok(Light(Point({ pos: { x: 1.0, y: 2.0, z: 3.0 }, color: { r: 4.0, g: 2.0, b: 0.4 }, range: 6.0 })))
