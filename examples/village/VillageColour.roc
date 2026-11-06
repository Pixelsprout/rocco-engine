import pf.Shader

VillageColour := [].{

	## The shader asset key within the supplied Pack.
	asset : Str -> Shader.Asset
	asset = |pack| { pack, asset: "shader/VillageColour" }

	## Numeric Scene values. Start from scene_default for declared defaults.
	SceneParameters : {}

	## Declared numeric defaults for Scene scope.
	scene_default : SceneParameters
	scene_default = {}

	## Assign numeric values only to Scene scope.
	scene : Str, SceneParameters -> Shader.Values
	scene = |pack, _values| { shader: asset(pack), scope: Scene, parameters: [], textures: [] }

	## Numeric Draw values. Start from draw_default for declared defaults.
	DrawParameters : { gain : Shader.Vec3, saturation : F32, contrast : F32, vignette : F32 }

	## Declared numeric defaults for Draw scope.
	draw_default : DrawParameters
	draw_default = { gain: { x: 1.015, y: 1.0, z: 0.985 }, saturation: 1.03, contrast: 1.025, vignette: 0.07 }

	## Assign numeric values only to Draw scope.
	draw : Str, DrawParameters -> Shader.Values
	draw = |pack, values| { shader: asset(pack), scope: Draw, parameters: [{ name: "gain", value: Vector3(values.gain) }, { name: "saturation", value: Scalar(values.saturation) }, { name: "contrast", value: Scalar(values.contrast) }, { name: "vignette", value: Scalar(values.vignette) }], textures: [] }
}
