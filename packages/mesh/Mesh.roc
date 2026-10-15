Mesh := [].{
	Manifest : List({ name : Str, id : U32 })

	# The meshes the engine builds itself. Loaded files have no tag; name them.
	Primitive : [Cube, Sphere, Plane]

	# The primitives load at startup and never unload, so their ids are fixed.
	primitive : Primitive -> U32
	primitive = |p| match p {
		Cube => 1
		Sphere => 2
		Plane => 3
	}

	# Mesh ids are opaque. Resolve them here once, in loaded, and keep them in the Model.
	# A name the engine did not load resolves to 0, the fallback mesh, and prints the name.
	resolve : Manifest, Str -> U32
	resolve = |manifest, name| match List.find_first(manifest, |m| m.name == name) {
		Ok(m) => m.id
		Err(NotFound) => {
			dbg name
			0
		}
	}
}

# engine/mesh_test.odin pins the same primitive ids, so a change to the slot order fails a test on each side.
expect Mesh.primitive(Cube) == 1
expect Mesh.primitive(Sphere) == 2
expect Mesh.primitive(Plane) == 3

manifest : Mesh.Manifest
manifest = [{ name: "sprout", id: 4 }, { name: "missing", id: 0 }]

expect Mesh.resolve(manifest, "sprout") == 4
expect Mesh.resolve(manifest, "missing") == 0
expect Mesh.resolve(manifest, "sprotu") == 0
expect Mesh.resolve([], "sprout") == 0
