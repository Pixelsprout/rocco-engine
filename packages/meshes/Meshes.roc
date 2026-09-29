Meshes := [].{
    Config : { seed : U64, meshes : List({ name : Str, id : U32 }) }

    # The meshes the engine builds itself. Loaded files have no tag; name them.
    Primitive : [Cube, Sphere, Plane]

    # Mesh ids are opaque. Resolve them here once, in init, and keep them in the Model.
    primitive : Config, Primitive -> U32
    primitive = |config, p| named(config, primitive_name(p))

    # A name the engine did not load resolves to 0, the fallback mesh, and prints the name.
    named : Config, Str -> U32
    named = |config, name| match List.find_first(config.meshes, |m| m.name == name) {
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
manifest : Meshes.Config
manifest = { seed: 0, meshes: [{ name: "primitive/fallback", id: 0 }, { name: "primitive/cube", id: 1 }, { name: "primitive/sphere", id: 2 }, { name: "primitive/plane", id: 3 }, { name: "sprout", id: 4 }] }

expect Meshes.primitive(manifest, Cube) == 1
expect Meshes.primitive(manifest, Sphere) == 2
expect Meshes.primitive(manifest, Plane) == 3
expect Meshes.named(manifest, "sprout") == 4
expect Meshes.named(manifest, "sprotu") == 0
expect Meshes.named(manifest, "plane") == 0
expect Meshes.primitive({ seed: 0, meshes: [] }, Cube) == 0
