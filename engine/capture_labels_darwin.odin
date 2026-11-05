#+build darwin
package engine

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import sg "../sokol-odin/sokol/gfx"

capture_metal_label :: proc(label: cstring) {
	encoder := (^MTL.RenderCommandEncoder)(sg.mtl_render_command_encoder())
	if encoder == nil { g_state.capture.failed = "Metal pass has no native encoder"; return }
	// Release Sokol archives omit pass labels, so the diagnostic sets the native label directly.
	name := NS.String.alloc()->initWithCString(label, .UTF8)
	defer name->release()
	encoder->setLabel(name)
}
