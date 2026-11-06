import pf.Shader

VillageGround := [].{

	## The shader asset key within the supplied Pack.
	asset : Str -> Shader.Asset
	asset = |pack| { pack, asset: "shader/VillageGround" }

	## Numeric Scene values. Start from scene_default for declared defaults.
	SceneParameters : {}

	## Declared numeric defaults for Scene scope.
	scene_default : SceneParameters
	scene_default = {}

	## Assign numeric values only to Scene scope.
	scene : Str, SceneParameters -> Shader.Values
	scene = |pack, _values| { shader: asset(pack), scope: Scene, parameters: [], textures: [] }

	## Numeric Material values. Start from material_default for declared defaults.
	MaterialParameters : {}

	## Declared numeric defaults for Material scope.
	material_default : MaterialParameters
	material_default = {}

	## Assign numeric values only to Material scope.
	material : Str, MaterialParameters -> Shader.Values
	material = |pack, _values| { shader: asset(pack), scope: Material, parameters: [], textures: [] }

	## Explicit textures for Material scope. Numeric-only assignments retain texture defaults.
	MaterialTextures : { ground_mask : [Default, Image2D(Shader.Asset)], terrain_noise : [Default, Image2D(Shader.Asset)] }

	## Keep all declared texture defaults in Material scope.
	material_textures_default : MaterialTextures
	material_textures_default = { ground_mask: Default, terrain_noise: Default }

	## Assign numeric values and textures together in Material scope.
	material_with_textures : Str, MaterialParameters, MaterialTextures -> Shader.Values
	material_with_textures = |pack, values, textures| {
		..material(pack, values),
		textures: List.join([
			match textures.ground_mask {
				Default => []
				Image2D(reference) => [{ name: "ground_mask", texture: Image2D(reference) }]
			},
			match textures.terrain_noise {
				Default => []
				Image2D(reference) => [{ name: "terrain_noise", texture: Image2D(reference) }]
			},
		]),
	}

	## Replace ground_mask in Material scope.
	material_ground_mask : Str, [Image2D(Shader.Asset)] -> Shader.Values
	material_ground_mask = |pack, texture| {
		shader: asset(pack),
		scope: Material,
		parameters: [],
		textures: [
			{
				name: "ground_mask",
				texture: match texture {
					Image2D(reference) => Image2D(reference)
				},
			},
		],
	}

	## Replace terrain_noise in Material scope.
	material_terrain_noise : Str, [Image2D(Shader.Asset)] -> Shader.Values
	material_terrain_noise = |pack, texture| {
		shader: asset(pack),
		scope: Material,
		parameters: [],
		textures: [
			{
				name: "terrain_noise",
				texture: match texture {
					Image2D(reference) => Image2D(reference)
				},
			},
		],
	}

	## Numeric Draw values. Start from draw_default for declared defaults.
	DrawParameters : {}

	## Declared numeric defaults for Draw scope.
	draw_default : DrawParameters
	draw_default = {}

	## Assign numeric values only to Draw scope.
	draw : Str, DrawParameters -> Shader.Values
	draw = |pack, _values| { shader: asset(pack), scope: Draw, parameters: [], textures: [] }
}
