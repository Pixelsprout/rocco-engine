## Turns mesh names into the mesh ids that a Draw carries.
Mesh := [].{

	## The name-to-id list that `loaded` gets for one Pack. It has the same
	## shape as `Vocabulary.Manifest`.
	Manifest : List({ name : Str, id : U32, clips : List({ name : Str, id : U32, duration : F32 }) })

	## The meshes that the engine builds itself. A loaded file has no tag. Give
	## its name to `resolve`.
	Primitive : [Cube, Sphere, Plane]

	## The fixed mesh id of a Primitive: cube 1, sphere 2, plane 3. The
	## Primitives load at startup and never unload, so you need no Pack.
	primitive : Primitive -> U32
	primitive = |p| match p {
		Cube => 1
		Sphere => 2
		Plane => 3
	}

	## The mesh id of a name in the Manifest. Call it once, in `loaded`, and keep
	## the id in your Model. A name that the engine did not load gives 0, the
	## Fallback mesh, and prints the name.
	resolve : Manifest, Str -> U32
	resolve = |manifest, name| match List.find_first(manifest, |m| m.name == name) {
		Ok(m) => m.id
		Err(NotFound) => {
			dbg name
			0
		}
	}

	## The Clip id of a Clip of a skinned mesh, by the mesh's name and the
	## Clip's name in the file. Call it once, in `loaded`, and keep the id in
	## your Model for a Draw's `pose`. A mesh or Clip name that is not in the
	## Manifest gives 0, which draws the bind pose, and prints the names.
	clip : Manifest, Str, Str -> U32
	clip = |manifest, mesh_name, clip_name| {
		clips = match List.find_first(manifest, |m| m.name == mesh_name) {
			Ok(m) => m.clips
			Err(NotFound) => []
		}
		match List.find_first(clips, |c| c.name == clip_name) {
			Ok(c) => c.id
			Err(NotFound) => {
				dbg (mesh_name, clip_name)
				0
			}
		}
	}

	## The duration in seconds of the Clip with this Clip id, the time of its
	## last key. Give it to `Pose.loop` to repeat the Clip. Clip id 0, or an id
	## that is not in the Manifest, gives 0.
	clip_duration : Manifest, U32 -> F32
	clip_duration = |manifest, clip_id| {
		clips = List.join_map(manifest, |m| m.clips)
		match List.find_first(clips, |c| c.id == clip_id and clip_id != 0) {
			Ok(c) => c.duration
			Err(NotFound) => 0.0
		}
	}
}

# engine/mesh_test.odin pins the same primitive ids, so a change to the slot order fails a test on each side.
expect Mesh.primitive(Cube) == 1
expect Mesh.primitive(Sphere) == 2
expect Mesh.primitive(Plane) == 3

manifest : Mesh.Manifest
manifest = [
	{ name: "sprout", id: 4, clips: [] },
	{ name: "missing", id: 0, clips: [] },
	{ name: "pip", id: 5, clips: [{ name: "Idle", id: 1, duration: 2.0 }, { name: "Walk", id: 2, duration: 1.0 }] },
	{ name: "crab", id: 6, clips: [{ name: "Walk", id: 3, duration: 0.5 }] },
]

expect Mesh.resolve(manifest, "sprout") == 4
expect Mesh.resolve(manifest, "missing") == 0
expect Mesh.resolve(manifest, "sprotu") == 0
expect Mesh.resolve([], "sprout") == 0

expect Mesh.clip(manifest, "pip", "Idle") == 1
expect Mesh.clip(manifest, "pip", "Walk") == 2
expect Mesh.clip(manifest, "crab", "Walk") == 3
expect Mesh.clip(manifest, "pip", "Run") == 0
expect Mesh.clip(manifest, "sprout", "Walk") == 0
expect Mesh.clip(manifest, "pi", "Walk") == 0

expect Mesh.clip_duration(manifest, 1) == 2.0
expect Mesh.clip_duration(manifest, 3) == 0.5
expect Mesh.clip_duration(manifest, 9) == 0.0
expect Mesh.clip_duration(manifest, 0) == 0.0
expect Mesh.clip_duration([], 1) == 0.0
