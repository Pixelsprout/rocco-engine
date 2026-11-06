import pf.Shader

VillageCanopy := [].{

	## The shader asset key within the supplied Pack.
	asset : Str -> Shader.Asset
	asset = |pack| { pack, asset: "shader/VillageCanopy" }

	## Numeric Scene values. Start from scene_default for declared defaults.
	SceneParameters : { wind : F32 }

	## Declared numeric defaults for Scene scope.
	scene_default : SceneParameters
	scene_default = { wind: 1.0 }

	## Assign numeric values only to Scene scope.
	scene : Str, SceneParameters -> Shader.Values
	scene = |pack, values| { shader: asset(pack), scope: Scene, parameters: [{ name: "wind", value: Scalar(values.wind) }], textures: [] }

	## Numeric Material values. Start from material_default for declared defaults.
	MaterialParameters : { canopy_center : Shader.Vec3, canopy_radius : F32, canopy_base : F32, normal_soften : F32 }

	## Declared numeric defaults for Material scope.
	material_default : MaterialParameters
	material_default = { canopy_center: { x: 0.0, y: 4.0, z: 0.0 }, canopy_radius: 2.5, canopy_base: 0.0, normal_soften: 0.85 }

	## Assign numeric values only to Material scope.
	material : Str, MaterialParameters -> Shader.Values
	material = |pack, values| { shader: asset(pack), scope: Material, parameters: [{ name: "canopy_center", value: Vector3(values.canopy_center) }, { name: "canopy_radius", value: Scalar(values.canopy_radius) }, { name: "canopy_base", value: Scalar(values.canopy_base) }, { name: "normal_soften", value: Scalar(values.normal_soften) }], textures: [] }

	## Numeric Draw values. Start from draw_default for declared defaults.
	DrawParameters : {}

	## Declared numeric defaults for Draw scope.
	draw_default : DrawParameters
	draw_default = {}

	## Assign numeric values only to Draw scope.
	draw : Str, DrawParameters -> Shader.Values
	draw = |pack, _values| { shader: asset(pack), scope: Draw, parameters: [], textures: [] }
}
