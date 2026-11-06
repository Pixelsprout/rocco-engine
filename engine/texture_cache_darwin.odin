#+build darwin
package engine

import sg "../sokol-odin/sokol/gfx"
import MTL "vendor:darwin/Metal"

texture_cache_native_bytes :: proc(c: ^Texture_Cache) -> (total: u64) {
	for _, entry in c.entries {
		info := sg.mtl_query_image_info(entry.image)
		if native := info.tex[info.active_slot]; native != nil {
			total += u64((^MTL.Resource)(native)->allocatedSize())
		}
	}
	return
}
