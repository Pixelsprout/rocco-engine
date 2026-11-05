import Field
import Layout
import VillageCanopy
import VillageGrass
import mesh.Mesh
import pf.Draw
import pf.Material
import pf.Shader
import pf.Vocabulary

Vegetation := [].{
	Settings : { density : U64, distance : F32, wind : Bool, canopy : Bool, grass : Bool, field : Bool, casts_shadow : Bool }
	default : Settings
	default = { density: 22000, distance: 65.0, wind: Bool.True, canopy: Bool.True, grass: Bool.True, field: Bool.True, casts_shadow: Bool.True }

	Placement : { draw : Vocabulary.Draw, group : U64, kind : [Canopy, Plant, Static] }
	Prepared : { source : List(Placement), field : List(Vocabulary.Draw) }
	empty : Prepared
	empty = { source: [], field: [] }

	assets : List(Str)
	assets = ["shader/VillageCanopy", "shader/VillageGrass", "image/T_Noise_Terrain"]

	prepare : Vocabulary.Manifest -> Prepared
	prepare = |manifest| {
		source = Layout.mesh_info.map(
			|shape| {
				base = mesh_draw(manifest, shape)
				Layout.placements.keep_if(|placement| placement.asset == shape.asset).map(
					|placement| {
						draw: { ..base, id: placement.id, pos: placement.pos, rot: placement.rot, scale: placement.scale },
						group: placement.group,
						kind: shape.kind,
					},
				)
			},
		).join()
		field = Layout.mesh_info.keep_if(|shape| shape.kind == Plant).map(
			|shape| {
				base = mesh_draw(manifest, shape)
				values = VillageGrass.material("village-vegetation", { plant_height: shape.plant_height, vertex_weights: shape.vertex_weights, field_fade: Bool.True })
				field_base = { ..base, material: { ..Material.surface(values), properties: [DoubleSided(Bool.True), Alpha(Mask(0.2))] } }
				Field.placements.keep_if(|placement| placement.asset == shape.asset).map(|placement| { ..field_base, id: placement.id, pos: placement.pos, rot: placement.rot, scale: placement.scale, casts_shadow: Bool.False })
			},
		).join()
		{ source, field }
	}

	draw : Placement, Settings -> Vocabulary.Draw
	draw = |placement, settings| {
		base = placement.draw
		use_shader = match placement.kind {
			Canopy => settings.canopy
			Plant => settings.grass
			Static => Bool.True
		}
		{ ..base, casts_shadow: settings.casts_shadow, material: if use_shader base.material else Material.default, slot_materials: if use_shader base.slot_materials else [] }
	}

	field_nodes : Prepared, { settings : Settings, eye : Vocabulary.Vec3 } -> List(Vocabulary.Node)
	field_nodes = |prepared, { settings, eye }| if !settings.field [] else {
		distance_squared = (settings.distance + 10.0) * (settings.distance + 10.0)
		prepared.field.keep_if(|plant| plant.id - 100000 < settings.density and (plant.pos.x - eye.x) * (plant.pos.x - eye.x) + (plant.pos.z - eye.z) * (plant.pos.z - eye.z) <= distance_squared).map(|plant| Draw({ ..plant, material: if settings.grass plant.material else Material.default }))
	}

	scene_values : Settings, Vocabulary.Vec3 -> List(Shader.Values)
	scene_values = |settings, eye| {
		wind = if settings.wind 1.0 else 0.0
		[VillageCanopy.scene("village-vegetation", { wind: wind }), VillageGrass.scene("village-vegetation", { wind: wind, viewer: eye, visibility_distance: settings.distance })]
	}

	configure : Settings, Str -> Settings
	configure = |settings, message| match message {
		"wind" => { ..settings, wind: !settings.wind }
		"canopy" => { ..settings, canopy: !settings.canopy }
		"grass" => { ..settings, grass: !settings.grass }
		"field" => { ..settings, field: !settings.field }
		"casting" => { ..settings, casts_shadow: !settings.casts_shadow }
		_ => match message.split_on("=") {
			["density", number] => match U64.from_str(number) {
				Ok(density) => { ..settings, density: U64.min(density, 22000) }
				Err(_) => settings
			}
			["distance", number] => match F32.from_str(number) {
				Ok(distance) => if distance >= 0.0 and distance < 1000000.0 { ..settings, distance: F32.max(1.0, F32.min(200.0, distance)) } else settings
				Err(_) => settings
			}
			_ => settings
		}
	}
}

mesh_draw : Vocabulary.Manifest, Layout.MeshInfo -> Vocabulary.Draw
mesh_draw = |manifest, shape| {
	base = { ..Draw.default, mesh: Mesh.resolve(manifest, shape.asset) }
	match shape.kind {
		Static => base
		Plant => {
			values = VillageGrass.material("village-vegetation", { plant_height: shape.plant_height, vertex_weights: shape.vertex_weights, field_fade: Bool.False })
			{ ..base, material: { ..Material.surface(values), properties: [DoubleSided(Bool.True)] } }
		}
		Canopy => {
			values = VillageCanopy.material("village-vegetation", { canopy_center: shape.canopy_center, canopy_radius: shape.canopy_radius, canopy_base: shape.canopy_base, normal_soften: if shape.asset.starts_with("Pine_") 0.6 else 0.85 })
			{ ..base, slot_materials: shape.leaves.map(|slot| { slot: { mesh: { pack: shape.asset, asset: shape.asset }, source_material: slot.index }, material: { ..Material.surface(values), properties: [DoubleSided(Bool.True)] } }) }
		}
	}
}

## Invalid density values preserve the active vegetation settings.
expect Vegetation.configure(Vegetation.default, "density=invalid") == Vegetation.default

## The supplied field remains complete by default.
expect Vegetation.default.density == 22000

## Field casting stays disabled when source casting changes.
expect Vegetation.configure(Vegetation.default, "casting").casts_shadow == Bool.False
