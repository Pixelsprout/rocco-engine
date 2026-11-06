import pf.Shader

Foliage := [].{

	## The shader asset key within the supplied Pack.
	asset : Str -> Shader.Asset
	asset = |pack| { pack, asset: "shader/Foliage" }

	## Numeric Scene values. Start from scene_default for declared defaults.
	SceneParameters : { wind : F32 }

	## Declared numeric defaults for Scene scope.
	scene_default : SceneParameters
	scene_default = { wind: 0.2 }

	## Assign numeric values only to Scene scope.
	scene : Str, SceneParameters -> Shader.Values
	scene = |pack, values| { shader: asset(pack), scope: Scene, parameters: [{ name: "wind", value: Scalar(values.wind) }], textures: [] }

	## Explicit textures for Scene scope. Numeric-only assignments retain texture defaults.
	SceneTextures : { weights : [Default, Image2D(Shader.Asset)] }

	## Keep all declared texture defaults in Scene scope.
	scene_textures_default : SceneTextures
	scene_textures_default = { weights: Default }

	## Assign numeric values and textures together in Scene scope.
	scene_with_textures : Str, SceneParameters, SceneTextures -> Shader.Values
	scene_with_textures = |pack, values, textures| {
		..scene(pack, values),
		textures: List.join([
			match textures.weights {
				Default => []
				Image2D(reference) => [{ name: "weights", texture: Image2D(reference) }]
			},
		]),
	}

	## Replace weights in Scene scope.
	scene_weights : Str, [Image2D(Shader.Asset)] -> Shader.Values
	scene_weights = |pack, texture| {
		shader: asset(pack),
		scope: Scene,
		parameters: [],
		textures: [
			{
				name: "weights",
				texture: match texture {
					Image2D(reference) => Image2D(reference)
				},
			},
		],
	}

	## Numeric Material values. Start from material_default for declared defaults.
	MaterialParameters : { leaf_tint : Shader.Colour }

	## Declared numeric defaults for Material scope.
	material_default : MaterialParameters
	material_default = { leaf_tint: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 } }

	## Assign numeric values only to Material scope.
	material : Str, MaterialParameters -> Shader.Values
	material = |pack, values| { shader: asset(pack), scope: Material, parameters: [{ name: "leaf_tint", value: LinearColour(values.leaf_tint) }], textures: [] }

	## Numeric Draw values. Start from draw_default for declared defaults.
	DrawParameters : { phase : F32 }

	## Declared numeric defaults for Draw scope.
	draw_default : DrawParameters
	draw_default = { phase: 0.0 }

	## Assign numeric values only to Draw scope.
	draw : Str, DrawParameters -> Shader.Values
	draw = |pack, values| { shader: asset(pack), scope: Draw, parameters: [{ name: "phase", value: Scalar(values.phase) }], textures: [] }
}
