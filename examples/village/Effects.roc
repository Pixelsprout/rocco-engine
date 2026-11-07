import Layout
import VillageColour
import VillageOutline
import linalg.Quat
import linalg.Vec3 as V
import pf.Emitter
import pf.Image
import pf.Post
import pf.Vocabulary

Effects := [].{

	Settings : { outline : Bool, visible_only : Bool, width : F32, pulse : Bool, glow : Bool, colour : Bool, smoke : Bool, dust : Bool, controls : Bool }

	default : Settings
	default = { outline: Bool.True, visible_only: Bool.True, width: 2.0, pulse: Bool.True, glow: Bool.True, colour: Bool.True, smoke: Bool.True, dust: Bool.True, controls: Bool.False }

	assets : List(Str)
	assets = ["shader/VillageOutline", "shader/VillageColour", "image/village_smoke", "image/village_dust"]

	compare : Settings, Str -> Settings
	compare = |settings, name| match name {
		"all" => { ..default, controls: settings.controls }
		"none" => { ..settings, outline: Bool.False, colour: Bool.False, smoke: Bool.False, dust: Bool.False }
		"outline" => { ..settings, outline: !settings.outline }
		"visible" => { ..settings, visible_only: Bool.True }
		"through" => { ..settings, visible_only: Bool.False }
		"occlusion" => { ..settings, visible_only: !settings.visible_only }
		"pulse" => { ..settings, pulse: !settings.pulse }
		"glow" => { ..settings, glow: !settings.glow }
		"width:1" => { ..settings, width: 1.0 }
		"width:2" => { ..settings, width: 2.0 }
		"width:3" => { ..settings, width: 3.0 }
		"width:4" => { ..settings, width: 4.0 }
		"colour" => { ..settings, colour: !settings.colour }
		"smoke" => { ..settings, smoke: !settings.smoke }
		"dust" => { ..settings, dust: !settings.dust }
		"controls" => { ..settings, controls: !settings.controls }
		_ => settings
	}

	post : Settings, U64 -> List(Vocabulary.Post)
	post = |settings, selected| List.join([
		if settings.outline and selected != 0 [
			Post.before_bloom(
				VillageOutline.draw(
					"effects",
					{
						..VillageOutline.draw_default,
						visible_only: settings.visible_only,
						width: settings.width,
						pulse: if settings.pulse 0.18 else 0.0,
						glow: if settings.glow 0.2 else 0.0,
					},
				),
			),
		] else [],
		if settings.colour [Post.after_tone_map(VillageColour.draw("effects", VillageColour.draw_default))] else [],
	])

	emitters : Vocabulary.Manifest, U64, Settings -> List(Vocabulary.Emitter)
	emitters = |manifest, seed, settings| {
		smoke = if settings.smoke match Layout.placements.find_first(|p| p.name == "HouseA/Prop_Chimney2") {
			Err(_) => []
			Ok(chimney) => [
				{
					..Emitter.default,
					id: 70001,
					position: V.add(chimney.pos, Quat.rotate({ x: 0.0, y: 3.20 * chimney.scale.y, z: 0.0 }, chimney.rot)),
					rate: 5.0,
					lifetime: 7.0,
					start_size: 0.38,
					end_size: 2.4,
					start_colour: { r: 0.55, g: 0.57, b: 0.60, a: 0.22 },
					end_colour: { r: 0.66, g: 0.68, b: 0.71, a: 0.0 },
					velocity: { x: 0.19, y: 0.57, z: 0.05 },
					velocity_spread: { x: 0.10, y: 0.11, z: 0.10 },
					drag: 0.08,
					seed: (seed % 104729) + 731,
					image: Image.resolve(manifest, "image/village_smoke"),
				},
			]
		} else []
		dust_image = Image.resolve(manifest, "image/village_dust")
		dust = if settings.dust List.repeat({}, 40).map_with_index(
			|_cell, i| {
				x = (i % 5).to_f32()
				z = (i // 5).to_f32()
				stream = ((seed % 104729) + 4242 + i * 97) % 104729
				jitter = ((stream * 48271) % 104729).to_f32() / 104729.0
				{
					..Emitter.default,
					id: 70002 + i,
					position: { x: -5.0 + (x + 0.25 + jitter * 0.5) * 2.0, y: 0.3 + jitter * 2.6, z: -10.0 + (z + 0.25 + jitter * 0.5) * 3.5 },
					rate: 160.0 / 14.0 / 40.0,
					lifetime: 14.0,
					start_size: 0.014,
					end_size: 0.018,
					start_colour: { r: 1.0, g: 0.86, b: 0.62, a: 0.30 },
					end_colour: { r: 1.0, g: 0.86, b: 0.62, a: 0.0 },
					velocity: { x: 0.02, y: 0.025, z: 0.01 },
					velocity_spread: { x: 0.035, y: 0.035, z: 0.035 },
					seed: stream,
					image: dust_image,
					blend: Add,
				}
			},
		) else []
		List.join([smoke, dust])
	}
}
