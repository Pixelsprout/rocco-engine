#+test
package engine

import "core:testing"

@(test)
test_mask_example_mips_keep_nonzero_coverage :: proc(t: ^testing.T) {
	for bytes in ([][]byte{#load("../examples/mask/assets/meshes/fence.glb"), #load("../examples/mask/assets/meshes/leaf.glb"), #load("../examples/mask/assets/meshes/pip_holes.glb")}) {
		data, _, err := glb_parse(bytes, context.temp_allocator)
		testing.expect_value(t, err, Glb_Error.None)
		tex := data.textures[data.parts[0].texture.? or_else -1]
		base := tex.levels[0]
		plain := texture_build(base.width, base.height, base.pixels, tex.sampler, tex.srgb, context.temp_allocator)
		for level, i in tex.levels {
			before, after := 0, 0
			for j := 3; j < len(level.pixels); j += 4 {
				if f32(plain.levels[i].pixels[j])/255 >= 0.5 { before += 1 }
				if f32(level.pixels[j])/255 >= 0.5 { after += 1 }
			}
			testing.expectf(t, after > 0, "mip %v lost all cutout coverage", i)
			if i == 0 { testing.expect_value(t, before, after) }
		}
	}
}
