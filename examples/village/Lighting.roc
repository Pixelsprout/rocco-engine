import VillageGround
import LightingWindowThin
import LightingWindowWide
import mesh.Mesh as Mesh
import pf.Draw
import pf.Environment
import pf.Light
import pf.Material
import pf.Vocabulary

Lighting := [].{

	Settings : { sun : Bool, sky : Bool, exposure : Bool, bloom : Bool, haze : Bool, lamps : Bool, ground : Bool }

	default : Settings
	default = { sun: Bool.True, sky: Bool.True, exposure: Bool.True, bloom: Bool.True, haze: Bool.True, lamps: Bool.True, ground: Bool.True }

	assets : List(Str)
	assets = ["sky/village", "image/ground_mask", "image/T_Noise_Terrain", "shader/VillageGround"]

	compare : Settings, Str -> Settings
	compare = |settings, name| match name {
		"all" => default
		"none" => { sun: Bool.False, sky: Bool.False, exposure: Bool.False, bloom: Bool.False, haze: Bool.False, lamps: Bool.False, ground: Bool.False }
		"sun" => { ..settings, sun: !settings.sun }
		"sky" => { ..settings, sky: !settings.sky }
		"exposure" => { ..settings, exposure: !settings.exposure }
		"bloom" => { ..settings, bloom: !settings.bloom }
		"haze" => { ..settings, haze: !settings.haze }
		"lamps" => { ..settings, lamps: !settings.lamps }
		"ground" => { ..settings, ground: !settings.ground }
		_ => settings
	}

	ground : Settings -> Vocabulary.Node
	ground = |settings| Draw({
		..Draw.default,
		id: 1,
		mesh: Mesh.primitive(Plane),
		scale: { x: 200.0, y: 1.0, z: 200.0 },
		tint: if settings.ground { r: 1.0, g: 1.0, b: 1.0 } else { r: 0.33, g: 0.52, b: 0.22 },
		material: if settings.ground Material.surface(VillageGround.material("lighting", VillageGround.material_default)) else Material.default,
	})

	windows : Vocabulary.Draw, { asset : Str, settings : Settings } -> Vocabulary.Draw
	windows = |draw, { asset, settings }| {
		slots = if asset == "Window_Thin_Round1" [LightingWindowThin.slot_mi_window_glass(asset)] else if asset == "Window_Wide_Round1" [LightingWindowWide.slot_mi_window_glass(asset)] else []
		if !settings.lamps draw else {
			material = {
				..Material.default,
				properties: [BaseColour({ r: 0.2632734, g: 0.1328683, b: 0.0637238, a: 0.9 }), Emission({ x: 0.55, y: 0.1626357, z: 0.03023445 })],
			}
			{ ..draw, slot_materials: List.join([draw.slot_materials, slots.map(|slot| { slot, material })]) }
		}
	}

	nodes : Settings -> List(Vocabulary.Node)
	nodes = |settings| {
		sun = if settings.sun [Light(Light.sun({ x: 0.84, y: -0.52, z: 0.16 }, { r: 2.6, g: 1.847474, b: 1.164769 }))] else []
		lamps = if settings.lamps lamp_positions.map(|pos| Light(Light.point(pos, { r: 2.2, g: 0.8648709, b: 0.2343863 }, 6.0))) else []
		List.join([sun, lamps])
	}

	environment : Vocabulary.Manifest, Settings -> Vocabulary.Environment
	environment = |manifest, settings| {
		..Environment.default,
		sky: if settings.sky Mesh.resolve(manifest, "sky/village") else 0,
		clear: { r: 0.32, g: 0.48, b: 0.65 },
		tone_map: AgX,
		exposure: if settings.exposure 1.12 else 1.0,
		fog: { color: { r: 0.393123, g: 0.477, b: 0.603827 }, start: 14.0, end: 120.0, amount: if settings.haze 0.38 else 0.0 },
		bloom: { strength: if settings.bloom 0.18 else 0.0, threshold: 1.2, knee: 0.5 },
	}
}

lamp_positions : List(Vocabulary.Vec3)
lamp_positions = [
	{ x: -3.2800002, y: 3.1, z: 2.0499997 },
	{ x: -3.2800002, y: 3.1, z: -0.050000116 },
	{ x: -1.05, y: 3.1, z: -16.279999 },
	{ x: 1.05, y: 3.1, z: -16.279999 },
	{ x: 3.48, y: 3.1, z: 3.9499998 },
	{ x: 3.48, y: 3.1, z: 6.0499997 },
]
