import pf.Shader

Outline := [].{

	## The shader asset key within the supplied Pack.
	asset : Str -> Shader.Asset
	asset = |pack| { pack, asset: "shader/Outline" }

	## Numeric Scene values. Start from scene_default for declared defaults.
	SceneParameters : {}

	## Declared numeric defaults for Scene scope.
	scene_default : SceneParameters
	scene_default = {}

	## Assign numeric values only to Scene scope.
	scene : Str, SceneParameters -> Shader.Values
	scene = |pack, _values| { shader: asset(pack), scope: Scene, parameters: [], textures: [] }

	## Numeric Draw values. Start from draw_default for declared defaults.
	DrawParameters : { outline : Shader.Colour, visible_only : Bool }

	## Declared numeric defaults for Draw scope.
	draw_default : DrawParameters
	draw_default = { outline: { r: 4.0, g: 1.0, b: 0.0, a: 1.0 }, visible_only: Bool.True }

	## Assign numeric values only to Draw scope.
	draw : Str, DrawParameters -> Shader.Values
	draw = |pack, values| { shader: asset(pack), scope: Draw, parameters: [{ name: "outline", value: LinearColour(values.outline) }, { name: "visible_only", value: Boolean(values.visible_only) }], textures: [] }
}
