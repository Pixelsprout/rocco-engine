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

	Placement : { draw : Vocabulary.Draw, asset : Str, group : U64, kind : [Canopy, Plant, Static] }
	Visibility : { id : U64, pos : Vocabulary.Vec3 }
	FieldChunk : { shaded : List(Vocabulary.Node), plain : List(Vocabulary.Node), visibility : List(Visibility) }
	Prepared : { source : List(Placement), field : List(Vocabulary.Node), field_plain : List(Vocabulary.Node), field_visibility : List(Visibility) }
	empty : Prepared
	empty = { source: [], field: [], field_plain: [], field_visibility: [] }
	field_chunk_size : U64
	field_chunk_size = 128

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
						asset: placement.asset,
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
		{ shaded, plain } = prepare_field(field)
		{ source, field: shaded, field_plain: plain, field_visibility: field.map(|plant| { id: plant.id, pos: plant.pos }) }
	}

	chunks : Prepared -> List(FieldChunk)
	chunks = |prepared| List.repeat({}, (prepared.field.len() + field_chunk_size - 1) // field_chunk_size).map_with_index(
		|_, i| {
			start = i * field_chunk_size
			len = U64.min(field_chunk_size, prepared.field.len() - start)
			{ shaded: prepared.field.sublist({ start, len }), plain: prepared.field_plain.sublist({ start, len }), visibility: prepared.field_visibility.sublist({ start, len }) }
		},
	)

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

	field_nodes_from : List(Vocabulary.Node), { settings : Settings, eye : Vocabulary.Vec3 } -> List(Vocabulary.Node)
	field_nodes_from = |field, { settings, eye }| if !settings.field [] else {
		distance_squared = (settings.distance + 10.0) * (settings.distance + 10.0)
		field.keep_if(
			|node| match node {
				Draw(plant) => plant.id - 100000 < settings.density and (plant.pos.x - eye.x) * (plant.pos.x - eye.x) + (plant.pos.z - eye.z) * (plant.pos.z - eye.z) <= distance_squared
				_ => Bool.False
			},
		)
	}

	field_nodes : Prepared, { settings : Settings, eye : Vocabulary.Vec3 } -> List(Vocabulary.Node)
	field_nodes = |prepared, { settings, eye }| field_nodes_from(if settings.grass prepared.field else prepared.field_plain, { settings, eye })

	visibility_changed_from : List(Visibility), { settings : Settings, from : Vocabulary.Vec3, to : Vocabulary.Vec3 } -> Bool
	visibility_changed_from = |visibility, { settings, from, to }| if !settings.field or from == to Bool.False else {
		distance_squared = (settings.distance + 10.0) * (settings.distance + 10.0)
		visibility.any(
			|plant| {
				before = plant.id - 100000 < settings.density and (plant.pos.x - from.x) * (plant.pos.x - from.x) + (plant.pos.z - from.z) * (plant.pos.z - from.z) <= distance_squared
				after = plant.id - 100000 < settings.density and (plant.pos.x - to.x) * (plant.pos.x - to.x) + (plant.pos.z - to.z) * (plant.pos.z - to.z) <= distance_squared
				before != after
			},
		)
	}

	visibility_changed : Prepared, { settings : Settings, from : Vocabulary.Vec3, to : Vocabulary.Vec3 } -> Bool
	visibility_changed = |prepared, args| visibility_changed_from(prepared.field_visibility, args)

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

prepare_field : List(Vocabulary.Draw) -> { shaded : List(Vocabulary.Node), plain : List(Vocabulary.Node) }
prepare_field = |field| {
	shaded = field.map(|plant| Draw(plant))
	plain = field.map(|plant| Draw({ ..plant, material: Material.default }))
	{ shaded, plain }
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

field_reference : List(Vocabulary.Draw), { settings : Vegetation.Settings, eye : Vocabulary.Vec3 } -> List(Vocabulary.Node)
field_reference = |field, { settings, eye }| if !settings.field [] else {
	distance_squared = (settings.distance + 10.0) * (settings.distance + 10.0)
	field.keep_if(|plant| plant.id - 100000 < settings.density and (plant.pos.x - eye.x) * (plant.pos.x - eye.x) + (plant.pos.z - eye.z) * (plant.pos.z - eye.z) <= distance_squared).map(|plant| Draw({ ..plant, material: if settings.grass plant.material else Material.default }))
}

expect {
	material = { ..Material.default, properties: [DoubleSided(Bool.True), Alpha(Mask(0.2))] }
	base = { ..Draw.default, mesh: 9, material, casts_shadow: Bool.False, tint: { r: 0.2, g: 0.4, b: 0.6 }, glow: { r: 0.1, g: 0.0, b: 0.0 }, scale: { x: 0.8, y: 1.2, z: 0.9 } }
	field = [
		{ ..base, id: 100003, pos: { x: 11.0, y: 7.0, z: 0.0 } },
		{ ..base, id: 100000, pos: { x: 10.999, y: -3.0, z: 0.0 } },
		{ ..base, id: 100002, pos: { x: 11.001, y: 0.0, z: 0.0 } },
		{ ..base, id: 100001, pos: { x: 0.0, y: 0.0, z: -11.0 } },
	]
	{ shaded, plain } = prepare_field(field)
	prepared = { ..Vegetation.empty, field: shaded, field_plain: plain }
	[0, 1, 2, 3, 4, 22000].all(
		|density| [Bool.True, Bool.False].all(
			|grass| [Bool.True, Bool.False].all(
				|enabled| [1.0, 65.0, 200.0].all(
					|distance| [{ x: 0.0, y: 0.0, z: 0.0 }, { x: -95.0, y: 80.0, z: 95.0 }, { x: 11.0, y: -9.0, z: 0.0 }].all(
						|eye| {
							settings = { ..Vegetation.default, density, grass, field: enabled, distance }
							Vegetation.field_nodes(prepared, { settings, eye }) == field_reference(field, { settings, eye })
						},
					),
				),
			),
		),
	)
}

expect Vegetation.field_nodes(Vegetation.empty, { settings: Vegetation.default, eye: { x: 0.0, y: 0.0, z: 0.0 } }).is_empty()

expect {
	manifest = Layout.assets.map(|name| { name, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	prepared = Vegetation.prepare(manifest)
	field = Layout.mesh_info.keep_if(|shape| shape.kind == Plant).map(
		|shape| {
			base = mesh_draw(manifest, shape)
			values = VillageGrass.material("village-vegetation", { plant_height: shape.plant_height, vertex_weights: shape.vertex_weights, field_fade: Bool.True })
			field_base = { ..base, material: { ..Material.surface(values), properties: [DoubleSided(Bool.True), Alpha(Mask(0.2))] } }
			Field.placements.keep_if(|placement| placement.asset == shape.asset).map(|placement| { ..field_base, id: placement.id, pos: placement.pos, rot: placement.rot, scale: placement.scale, casts_shadow: Bool.False })
		},
	).join()
	eyes = [
		{ x: 3.6, y: 1.9, z: 21.5 },
		{ x: 2.4, y: 1.75, z: 15.5 },
		{ x: 5.8143424, y: 8.0, z: 13.974774 },
		{ x: 10.5, y: 1.1, z: 14.5 },
		{ x: -13.0, y: 4.0, z: 12.0 },
		{ x: 0.0, y: 1.7, z: 17.0 },
		{ x: 0.3, y: 1.7, z: 12.0 },
		{ x: -0.5, y: 1.7, z: 6.0 },
		{ x: 0.4, y: 1.7, z: 0.0 },
		{ x: -0.2, y: 1.7, z: -5.0 },
		{ x: -1.2, y: 1.7, z: -9.5 },
		{ x: -2.4, y: 1.7, z: -12.6 },
		{ x: -95.0, y: 80.0, z: 95.0 },
		{ x: 95.0, y: 0.2, z: -95.0 },
	]
	field.len() == 22000 and prepared.field.len() == 22000 and prepared.field_plain.len() == 22000 and prepared.field_visibility == field.map(|plant| { id: plant.id, pos: plant.pos }) and eyes.all(
		|eye| [0, 1, 12345, 22000].all(
			|density| [1.0, 65.0, 200.0].all(
				|distance| [Bool.True, Bool.False].all(
					|grass| {
						settings = { ..Vegetation.default, density, distance, grass }
						Vegetation.field_nodes(prepared, { settings, eye }) == field_reference(field, { settings, eye })
					},
				),
			),
		),
	)
}

expect {
	manifest = Layout.assets.map(|name| { name, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	original = Vegetation.prepare(manifest)
	reloaded = Vegetation.prepare(manifest.map(|asset| { ..asset, id: 9 }))
	[original.field, original.field_plain].all(
		|nodes| nodes.all(
			|node| match node {
				Draw(plant) => plant.mesh == 4
				_ => Bool.False
			},
		),
	) and [reloaded.field, reloaded.field_plain].all(
		|nodes| nodes.all(
			|node| match node {
				Draw(plant) => plant.mesh == 9
				_ => Bool.False
			},
		),
	)
}

expect {
	field = [
		{ ..Draw.default, id: 100001, pos: { x: -11.0, y: 0.0, z: 0.0 } },
		{ ..Draw.default, id: 100000, pos: { x: 11.0, y: 0.0, z: 0.0 } },
	]
	{ shaded, plain } = prepare_field(field)
	prepared = { ..Vegetation.empty, field: shaded, field_plain: plain, field_visibility: field.map(|plant| { id: plant.id, pos: plant.pos }) }
	from = { x: -1.0, y: 0.0, z: 0.0 }
	to = { x: 1.0, y: 80.0, z: 0.0 }
	settings = { ..Vegetation.default, distance: 1.0 }
	before = field_reference(field, { settings, eye: from })
	after = field_reference(field, { settings, eye: to })
	before.len() == after.len() and before != after and Vegetation.visibility_changed(prepared, { settings, from, to }) and !Vegetation.visibility_changed(prepared, { settings, from, to: { ..from, y: 80.0 } }) and [0, 1, 2, 22000].all(
		|density| [1.0, 65.0].all(
			|distance| [Bool.True, Bool.False].all(
				|enabled| {
					changed_settings = { ..settings, density, distance, field: enabled }
					Vegetation.visibility_changed(prepared, { settings: changed_settings, from, to }) == (field_reference(field, { settings: changed_settings, eye: from }) != field_reference(field, { settings: changed_settings, eye: to }))
				},
			),
		),
	)
}
