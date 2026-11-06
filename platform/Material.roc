import Shader

## Partial changes to an imported material.
Material := [].{

	## Imported properties remain unchanged when the list omits them.
	Property : [BaseColour(Shader.Colour), Roughness(F32), Metallic(F32), Emission(Shader.Vec3), Unlit(Bool), NormalScale(F32), OcclusionStrength(F32), Alpha([Opaque, Mask(F32), Blend]), DoubleSided(Bool)]

	## Replace one imported map with a Pack image.
	Texture : { semantic : [BaseColour, MetallicRoughness, Emission, Normal, Occlusion], image : Shader.Asset }

	## A Surface and partial imported material changes.
	Override : { surface : [Imported, Surface(Shader.Values)], properties : List(Property), textures : List(Texture) }

	## Partial material changes for one source material identity.
	SlotOverride : { slot : Shader.Slot, material : Override }

	## Preserve every imported property and map.
	default : Override
	default = { surface: Imported, properties: [], textures: [] }

	## Use generated Material values on a whole Draw.
	surface : Shader.Values -> Override
	surface = |values| { ..default, surface: Surface(values) }
}
