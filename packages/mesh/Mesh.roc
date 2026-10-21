## Turns mesh names into the mesh ids that a Draw carries.
Mesh := [].{

	## The name-to-id list that `loaded` gets for one Pack. It has the same
	## shape as `Vocabulary.Manifest`.
	Manifest : List({ name : Str, id : U32 })

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
