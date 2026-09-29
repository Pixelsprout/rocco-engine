Mesh := [].{
    Config : { seed : U64, meshes : List({ name : Str, id : U32 }) }

    # The meshes the engine builds itself. Loaded files have no tag; name them.
    Primitive : [Cube, Sphere, Plane]

    # Mesh ids are opaque. Resolve them here once, in init, and keep them in the Model.
    primitive : Config, Primitive -> U32
    primitive = |config, p| resolve(config, primitive_name(p))

    # A name the engine did not load resolves to 0, the fallback mesh, and prints the name.
    resolve : Config, Str -> U32
    resolve = |config, name| match List.find_first(config.meshes, |m| m.name == name) {
        Ok(m) => m.id
        Err(NotFound) => {
            dbg name
            0
        }
    }

    primitive_name : Primitive -> Str
    primitive_name = |p| match p {
        Cube => "primitive/cube"
        Sphere => "primitive/sphere"
        Plane => "primitive/plane"
    }
}

# engine/config_test.odin checks the same literal manifest against config_make.
manifest : Mesh.Config
manifest = { seed: 0, meshes: [{ name: "primitive/fallback", id: 0 }, { name: "primitive/cube", id: 1 }, { name: "primitive/sphere", id: 2 }, { name: "primitive/plane", id: 3 }, { name: "sprout", id: 4 }] }

expect Mesh.primitive(manifest, Cube) == 1
expect Mesh.primitive(manifest, Sphere) == 2
expect Mesh.primitive(manifest, Plane) == 3
expect Mesh.resolve(manifest, "sprout") == 4
expect Mesh.resolve(manifest, "sprotu") == 0
expect Mesh.resolve(manifest, "plane") == 0
expect Mesh.primitive({ seed: 0, meshes: [] }, Cube) == 0
