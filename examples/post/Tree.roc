import pf.Shader

Tree := [].{

	## Source material "Bark"; independent of Mesh part order.
	slot_bark : Str -> Shader.Slot
	slot_bark = |pack| { mesh: { pack, asset: "tree" }, source_material: 0 }

	## Assign this source material's Surface values.
	bark : Str, Shader.Values -> Shader.SlotAssignment
	bark = |pack, values| { slot: slot_bark(pack), values }

	## Source material "Leaves"; independent of Mesh part order.
	slot_leaves : Str -> Shader.Slot
	slot_leaves = |pack| { mesh: { pack, asset: "tree" }, source_material: 1 }

	## Assign this source material's Surface values.
	leaves : Str, Shader.Values -> Shader.SlotAssignment
	leaves = |pack, values| { slot: slot_leaves(pack), values }
}
