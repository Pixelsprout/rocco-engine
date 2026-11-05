import pf.Shader

VillageGrass := [].{

	## The shader asset key within the supplied Pack.
	asset : Str -> Shader.Asset
	asset = |pack| { pack, asset: "shader/VillageGrass" }

	## Numeric Scene values. Start from scene_default for declared defaults.
	SceneParameters : { wind : F32, viewer : Shader.Vec3, visibility_distance : F32 }

	## Declared numeric defaults for Scene scope.
	scene_default : SceneParameters
	scene_default = { wind: 1.0, viewer: { x: 0.0, y: 1.7, z: 17.0 }, visibility_distance: 65.0 }

	## Assign numeric values only to Scene scope.
	scene : Str, SceneParameters -> Shader.Values
	scene = |pack, values| { shader: asset(pack), scope: Scene, parameters: [{ name: "wind", value: Scalar(values.wind) }, { name: "viewer", value: Vector3(values.viewer) }, { name: "visibility_distance", value: Scalar(values.visibility_distance) }], textures: [] }

	## Explicit textures for Scene scope. Numeric-only assignments retain texture defaults.
	SceneTextures : { noise : [Default, Image2D(Shader.Asset)] }

	## Keep all declared texture defaults in Scene scope.
	scene_textures_default : SceneTextures
	scene_textures_default = { noise: Default }

	## Assign numeric values and textures together in Scene scope.
	scene_with_textures : Str, SceneParameters, SceneTextures -> Shader.Values
	scene_with_textures = |pack, values, textures| {
		..scene(pack, values),
		textures: List.join([
			match textures.noise {
				Default => []
				Image2D(reference) => [{ name: "noise", texture: Image2D(reference) }]
			},
		]),
	}

	## Replace noise in Scene scope.
	scene_noise : Str, [Image2D(Shader.Asset)] -> Shader.Values
	scene_noise = |pack, texture| {
		shader: asset(pack),
		scope: Scene,
		parameters: [],
		textures: [
			{
				name: "noise",
				texture: match texture {
					Image2D(reference) => Image2D(reference)
				},
			},
		],
	}

	## Numeric Material values. Start from material_default for declared defaults.
	MaterialParameters : { plant_height : F32, vertex_weights : Bool, field_fade : Bool }

	## Declared numeric defaults for Material scope.
	material_default : MaterialParameters
	material_default = { plant_height: 1.0, vertex_weights: Bool.True, field_fade: Bool.False }

	## Assign numeric values only to Material scope.
	material : Str, MaterialParameters -> Shader.Values
	material = |pack, values| { shader: asset(pack), scope: Material, parameters: [{ name: "plant_height", value: Scalar(values.plant_height) }, { name: "vertex_weights", value: Boolean(values.vertex_weights) }, { name: "field_fade", value: Boolean(values.field_fade) }], textures: [] }

	## Numeric Draw values. Start from draw_default for declared defaults.
	DrawParameters : {}

	## Declared numeric defaults for Draw scope.
	draw_default : DrawParameters
	draw_default = {}

	## Assign numeric values only to Draw scope.
	draw : Str, DrawParameters -> Shader.Values
	draw = |pack, _values| { shader: asset(pack), scope: Draw, parameters: [], textures: [] }
}
