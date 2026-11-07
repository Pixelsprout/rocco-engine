import pf.Shader

VillageOutline := [].{

	## The shader asset key within the supplied Pack.
	asset : Str -> Shader.Asset
	asset = |pack| { pack, asset: "shader/VillageOutline" }

	## Numeric Scene values. Start from scene_default for declared defaults.
	SceneParameters : {}

	## Declared numeric defaults for Scene scope.
	scene_default : SceneParameters
	scene_default = {}

	## Assign numeric values only to Scene scope.
	scene : Str, SceneParameters -> Shader.Values
	scene = |pack, _values| { shader: asset(pack), scope: Scene, parameters: [], textures: [] }

	## Numeric Draw values. Start from draw_default for declared defaults.
	DrawParameters : { outline : Shader.Colour, visible_only : Bool, width : F32, pulse : F32, glow : F32 }

	## Declared numeric defaults for Draw scope.
	draw_default : DrawParameters
	draw_default = { outline: { r: 3.6, g: 1.3, b: 0.22, a: 1.0 }, visible_only: Bool.True, width: 2.0, pulse: 0.18, glow: 0.2 }

	## Assign numeric values only to Draw scope.
	draw : Str, DrawParameters -> Shader.Values
	draw = |pack, values| { shader: asset(pack), scope: Draw, parameters: [{ name: "outline", value: LinearColour(values.outline) }, { name: "visible_only", value: Boolean(values.visible_only) }, { name: "width", value: Scalar(values.width) }, { name: "pulse", value: Scalar(values.pulse) }, { name: "glow", value: Scalar(values.glow) }], textures: [] }
}
