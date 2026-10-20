import Vocabulary

# The Scene a game starts a record update from.
Scene := [].{
	# fov_y copies Camera.default_fov_y in packages/camera, which the platform cannot import.
	empty : Vocabulary.Scene
	empty = {
		camera: { eye: { x: 0.0, y: 5.0, z: 10.0 }, target: { x: 0.0, y: 0.0, z: 0.0 }, up: { x: 0.0, y: 1.0, z: 0.0 }, fov_y: 1.047 },
		draws: [],
		colliders: [],
		lights: [],
		cursor: Free,
		sky: 0,
		ui: [],
		queries: [],
	}
}

expect Scene.empty == { camera: { eye: { x: 0.0, y: 5.0, z: 10.0 }, target: { x: 0.0, y: 0.0, z: 0.0 }, up: { x: 0.0, y: 1.0, z: 0.0 }, fov_y: 1.047 }, draws: [], colliders: [], lights: [], cursor: Free, sky: 0, ui: [], queries: [] }
