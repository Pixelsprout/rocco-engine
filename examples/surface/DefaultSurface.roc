import pf.Shader

DefaultSurface := [].{

	## The shader asset key within the supplied Pack.
	asset : Str -> Shader.Asset
	asset = |pack| { pack, asset: "shader/DefaultSurface" }

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

	## Numeric Draw values. Start from draw_default for declared defaults.
	DrawParameters : {}

	## Declared numeric defaults for Draw scope.
	draw_default : DrawParameters
	draw_default = {}

	## Assign numeric values only to Draw scope.
	draw : Str, DrawParameters -> Shader.Values
	draw = |pack, _values| { shader: asset(pack), scope: Draw, parameters: [], textures: [] }
}
