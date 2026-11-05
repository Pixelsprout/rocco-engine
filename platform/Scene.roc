import Environment
import Vocabulary
import Shadow

## Gives the Scene that your game starts a record update from.
Scene := [].{

	## A Camera at (0, 5, 10) that looks at the origin with a field of view of
	## about 60 degrees. No Nodes, UI or Queries. The Cursor is `Free`. The
	## Environment is `Environment.default`. Shadows use `Shadow.default`.
	empty : Vocabulary.Scene
	empty = {
		# fov_y copies Camera.default_fov_y in packages/camera, which the platform cannot import.
		camera: { eye: { x: 0.0, y: 5.0, z: 10.0 }, target: { x: 0.0, y: 0.0, z: 0.0 }, up: { x: 0.0, y: 1.0, z: 0.0 }, fov_y: 1.047 },
		shader_values: [],
		nodes: [],
		emitters: [],
		cursor: Free,
		environment: Environment.default,
		shadow: Shadow.default,
		ui: [],
		queries: [],
	}
}

expect Scene.empty == { camera: { eye: { x: 0.0, y: 5.0, z: 10.0 }, target: { x: 0.0, y: 0.0, z: 0.0 }, up: { x: 0.0, y: 1.0, z: 0.0 }, fov_y: 1.047 }, shader_values: [], nodes: [], emitters: [], cursor: Free, environment: Environment.default, shadow: Shadow.default, ui: [], queries: [] }
