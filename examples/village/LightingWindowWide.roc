import pf.Shader

LightingWindowWide := [].{

	## Source material "MI_WoodTrim_Wear"; independent of Mesh part order.
	slot_mi_wood_trim_wear : Str -> Shader.Slot
	slot_mi_wood_trim_wear = |pack| { mesh: { pack, asset: "Window_Wide_Round1" }, source_material: 0 }

	## Assign this source material's Surface values.
	mi_wood_trim_wear : Str, Shader.Values -> Shader.SlotAssignment
	mi_wood_trim_wear = |pack, values| { slot: slot_mi_wood_trim_wear(pack), values }

	## Source material "MI_WindowGlass"; independent of Mesh part order.
	slot_mi_window_glass : Str -> Shader.Slot
	slot_mi_window_glass = |pack| { mesh: { pack, asset: "Window_Wide_Round1" }, source_material: 1 }

	## Assign this source material's Surface values.
	mi_window_glass : Str, Shader.Values -> Shader.SlotAssignment
	mi_window_glass = |pack, values| { slot: slot_mi_window_glass(pack), values }
}
