package engine

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

// Writes Vocabulary values as JSON for the Bridge, with the Vocabulary's tag
// and field names. A tag with a payload is an object with one key, such as
// {"Unload":"pip"}. A tag with no payload is a string, such as "Quit".

json_write_string :: proc(b: ^strings.Builder, s: string) {
	_ = json.marshal_to_builder(b, s, {})
}

json_write_roc_str :: proc(b: ^strings.Builder, s: ^Roc_Str) {
	json_write_string(b, roc_str_string(s))
}

json_write_command :: proc(b: ^strings.Builder, command: ^Command) {
	switch command.tag {
	case .Quit:
		strings.write_string(b, `"Quit"`)
	case .Load:
		load := &command.payload.load
		strings.write_string(b, `{"Load":{"pack":`)
		json_write_roc_str(b, &load.pack)
		strings.write_string(b, `,"assets":[`)
		for &asset, i in load.assets.elements[:load.assets.length] {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			json_write_roc_str(b, &asset)
		}
		strings.write_string(b, `]}}`)
	case .Unload:
		strings.write_string(b, `{"Unload":`)
		json_write_roc_str(b, &command.payload.unload)
		strings.write_byte(b, '}')
	case .Log:
		strings.write_string(b, `{"Log":`)
		json_write_roc_str(b, &command.payload.log)
		strings.write_byte(b, '}')
	case .Play:
		play := &command.payload.play
		json_key(b, "Play", first = true)
		json_key(b, "sound", first = true)
		strings.write_u64(b, u64(play.sound))
		json_key(b, "gain")
		json_write_f32(b, play.gain)
		json_key(b, "pitch")
		json_write_f32(b, play.pitch)
		json_key(b, "at")
		json_write_place(b, &play.at)
		strings.write_string(b, "}}")
	case .Burst:
		json_key(b, "Burst", first = true)
		json_key(b, "emitter", first = true)
		strings.write_u64(b, command.payload.burst.emitter)
		json_key(b, "count")
		strings.write_u64(b, u64(command.payload.burst.count))
		strings.write_string(b, "}}")
	case .Tell:
		tell := &command.payload.tell
		json_key(b, "Tell", first = true)
		json_key(b, "port", first = true)
		json_write_roc_str(b, &tell.port)
		json_key(b, "msg")
		json_write_roc_str(b, &tell.msg)
		strings.write_string(b, "}}")
	}
}

// b holds the elements of a JSON array with no brackets, so the Commands of
// many steps join into one array.
json_write_commands :: proc(b: ^strings.Builder, commands: Roc_List(Command)) {
	for &command in commands.elements[:commands.length] {
		if strings.builder_len(b^) > 0 {
			strings.write_byte(b, ',')
		}
		json_write_command(b, &command)
	}
}

json_write_scene :: proc(b: ^strings.Builder, scene: ^Scene) {
	json_key(b, "camera", first = true)
	json_write_camera(b, &scene.camera)
	json_key(b, "emitters")
	json_write_list(b, scene.emitters, json_write_emitter)
	json_key(b, "nodes")
	json_write_list(b, scene.nodes, json_write_node)
	json_key(b, "cursor")
	json_write_tag(b, scene.cursor)
	json_key(b, "environment")
	json_write_environment(b, &scene.environment)
	json_key(b, "shadow")
	json_write_shadow(b, &scene.shadow)
	json_key(b, "ui")
	json_write_list(b, scene.ui, json_write_element)
	json_key(b, "queries")
	json_write_list(b, scene.queries, json_write_query)
	strings.write_byte(b, '}')
}

json_write_environment :: proc(b: ^strings.Builder, env: ^Environment) {
	json_key(b, "sky", first = true)
	strings.write_u64(b, u64(env.sky))
	json_key(b, "sky_blend")
	json_key(b, "to", first = true)
	strings.write_u64(b, u64(env.sky_blend.to))
	json_key(b, "amount")
	json_write_f32(b, env.sky_blend.amount)
	strings.write_byte(b, '}')
	json_key(b, "clear")
	json_write_rgb(b, env.clear)
	json_key(b, "tone_map")
	json_write_tag(b, env.tone_map)
	json_key(b, "exposure")
	json_write_f32(b, env.exposure)
	json_key(b, "fog")
	json_write_fog(b, &env.fog)
	json_key(b, "bloom")
	json_write_bloom(b, &env.bloom)
	strings.write_byte(b, '}')
}

json_write_fog :: proc(b: ^strings.Builder, fog: ^Fog) {
	json_key(b, "color", first = true)
	json_write_rgb(b, fog.color)
	json_key(b, "start")
	json_write_f32(b, fog.start)
	json_key(b, "end")
	json_write_f32(b, fog.end)
	json_key(b, "amount")
	json_write_f32(b, fog.amount)
	json_key(b, "sky")
	json_write_f32(b, fog.sky)
	strings.write_byte(b, '}')
}

json_write_bloom :: proc(b: ^strings.Builder, bloom: ^Bloom) {
	json_key(b, "strength", first = true)
	json_write_f32(b, bloom.strength)
	json_key(b, "threshold")
	json_write_f32(b, bloom.threshold)
	json_key(b, "knee")
	json_write_f32(b, bloom.knee)
	strings.write_byte(b, '}')
}

json_write_query_results :: proc(b: ^strings.Builder, results: ^Query_Results) {
	json_key(b, "contacts", first = true)
	json_write_list(b, results.contacts, json_write_contact)
	json_key(b, "rays")
	json_write_list(b, results.rays, json_write_ray_hit)
	json_key(b, "overlaps")
	json_write_list(b, results.overlaps, json_write_overlap_hit)
	json_key(b, "ports")
	json_write_list(b, results.ports, json_write_port_message)
	json_key(b, "ui")
	json_write_ui_results(b, &results.ui)
	strings.write_byte(b, '}')
}

json_write_ui_results :: proc(b: ^strings.Builder, ui: ^Ui_Results) {
	json_key(b, "over", first = true)
	json_write_ids(b, ui.over)
	json_key(b, "scroll")
	json_write_list(b, ui.scroll, json_write_scroll_size)
	strings.write_byte(b, '}')
}

json_write_scroll_size :: proc(b: ^strings.Builder, s: ^Scroll_Size) {
	json_key(b, "id", first = true)
	strings.write_u64(b, s.id)
	json_key(b, "view")
	json_key(b, "width", first = true)
	json_write_f32(b, s.view.width)
	json_key(b, "height")
	json_write_f32(b, s.view.height)
	strings.write_byte(b, '}')
	json_key(b, "content")
	json_key(b, "width", first = true)
	json_write_f32(b, s.content.width)
	json_key(b, "height")
	json_write_f32(b, s.content.height)
	strings.write_string(b, "}}")
}

json_write_camera :: proc(b: ^strings.Builder, camera: ^Scene_Camera) {
	json_key(b, "eye", first = true)
	json_write_vec3(b, camera.eye)
	json_key(b, "target")
	json_write_vec3(b, camera.target)
	json_key(b, "up")
	json_write_vec3(b, camera.up)
	json_key(b, "fov_y")
	json_write_f32(b, camera.fov_y)
	strings.write_byte(b, '}')
}

// Each Pose is local to its Group, as the game wrote it.
json_write_node :: proc(b: ^strings.Builder, node: ^Node) {
	switch node.tag {
	case .Group:
		pose, children := &node.payload.group._0, node.payload.group._1
		json_key(b, "Group", first = true)
		json_key(b, "id", first = true)
		strings.write_u64(b, pose.id)
		json_key(b, "selected")
		strings.write_string(b, "true" if pose.selected else "false")
		json_key(b, "pose")
		json_key(b, "pos", first = true)
		json_write_vec3(b, pose.pos)
		json_key(b, "rot")
		json_write_quat(b, pose.rot)
		strings.write_byte(b, '}')
		json_key(b, "children")
		json_write_list(b, children, json_write_node)
		strings.write_byte(b, '}')
	case .Attach:
		config, children := &node.payload.attach._0, node.payload.attach._1
		json_key(b, "Attach", first = true)
		json_key(b, "draw", first = true)
		strings.write_u64(b, config.draw)
		json_key(b, "joint")
		json_write_roc_str(b, &config.joint)
		json_key(b, "children")
		json_write_list(b, children, json_write_node)
		strings.write_byte(b, '}')
	case .Draw:
		json_key(b, "Draw", first = true)
		json_write_draw(b, &node.payload.draw)
	case .Light:
		json_key(b, "Light", first = true)
		json_write_light(b, &node.payload.light)
	case .Collider:
		json_key(b, "Collider", first = true)
		json_write_collider(b, &node.payload.collider)
	case .Speaker:
		json_key(b, "Speaker", first = true)
		json_write_speaker(b, &node.payload.speaker)
	}
	strings.write_byte(b, '}')
}

json_write_draw :: proc(b: ^strings.Builder, draw: ^Draw) {
	json_key(b, "id", first = true)
	strings.write_u64(b, draw.id)
	json_key(b, "mesh")
	strings.write_u64(b, u64(draw.mesh))
	json_key(b, "pos")
	json_write_vec3(b, draw.pos)
	json_key(b, "scale")
	json_write_vec3(b, draw.scale)
	json_key(b, "rot")
	json_write_quat(b, draw.rot)
	json_key(b, "scale_rot")
	json_write_quat(b, draw.scale_rot)
	json_key(b, "tint")
	json_write_rgb(b, draw.tint)
	json_key(b, "glow")
	json_write_rgb(b, draw.glow)
	json_key(b, "casts_shadow")
	strings.write_string(b, "true" if draw.casts_shadow else "false")
	json_key(b, "pose")
	json_key(b, "clip", first = true)
	strings.write_u64(b, u64(draw.pose.clip))
	json_key(b, "time")
	json_write_f32(b, draw.pose.time)
	json_key(b, "fade_clip")
	strings.write_u64(b, u64(draw.pose.fade_clip))
	json_key(b, "fade_time")
	json_write_f32(b, draw.pose.fade_time)
	json_key(b, "fade")
	json_write_f32(b, draw.pose.fade)
	strings.write_byte(b, '}')
	json_key(b, "ground")
	json_key(b, "feet", first = true)
	json_write_list(b, draw.ground.feet, json_write_roc_str)
	strings.write_byte(b, '}')
	strings.write_byte(b, '}')
}

json_write_collider :: proc(b: ^strings.Builder, collider: ^Collider) {
	json_key(b, "id", first = true)
	strings.write_u64(b, collider.id)
	json_key(b, "pos")
	json_write_vec3(b, collider.pos)
	json_key(b, "rot")
	json_write_quat(b, collider.rot)
	json_key(b, "shape")
	shape := &collider.shape
	switch shape.tag {
	case .Box:
		json_key(b, "Box", first = true)
		json_write_vec3(b, shape.payload.box)
	case .Sphere:
		json_key(b, "Sphere", first = true)
		json_write_f32(b, shape.payload.sphere)
	case .Capsule:
		json_key(b, "Capsule", first = true)
		json_key(b, "radius", first = true)
		json_write_f32(b, shape.payload.capsule.radius)
		json_key(b, "half_height")
		json_write_f32(b, shape.payload.capsule.half_height)
		strings.write_byte(b, '}')
	}
	strings.write_string(b, "}}")
}

json_write_contact :: proc(b: ^strings.Builder, contact: ^Contact) {
	json_key(b, "a", first = true)
	strings.write_u64(b, contact.a)
	json_key(b, "b")
	strings.write_u64(b, contact.b)
	json_key(b, "normal")
	json_write_vec3(b, contact.normal)
	json_key(b, "depth")
	json_write_f32(b, contact.depth)
	strings.write_byte(b, '}')
}

json_write_ray_hit :: proc(b: ^strings.Builder, hit: ^Ray_Hit) {
	json_key(b, "owner", first = true)
	strings.write_u64(b, hit.owner)
	json_key(b, "slot")
	strings.write_u64(b, u64(hit.slot))
	json_key(b, "id")
	strings.write_u64(b, hit.id)
	json_key(b, "point")
	json_write_vec3(b, hit.point)
	json_key(b, "normal")
	json_write_vec3(b, hit.normal)
	json_key(b, "distance")
	json_write_f32(b, hit.distance)
	strings.write_byte(b, '}')
}

json_write_overlap_hit :: proc(b: ^strings.Builder, hit: ^Overlap_Hit) {
	json_key(b, "owner", first = true)
	strings.write_u64(b, hit.owner)
	json_key(b, "slot")
	strings.write_u64(b, u64(hit.slot))
	json_key(b, "id")
	strings.write_u64(b, hit.id)
	strings.write_byte(b, '}')
}

json_write_port_message :: proc(b: ^strings.Builder, m: ^Port_Message) {
	json_key(b, "port", first = true)
	json_write_roc_str(b, &m.port)
	json_key(b, "msg")
	json_write_roc_str(b, &m.msg)
	strings.write_byte(b, '}')
}

json_write_query :: proc(b: ^strings.Builder, query: ^Query) {
	switch query.tag {
	case .ContactsOf:
		json_key(b, "ContactsOf", first = true)
		strings.write_u64(b, query.payload.contacts_of)
	case .Listen:
		json_key(b, "Listen", first = true)
		json_write_roc_str(b, &query.payload.listen)
	case .Raycast:
		ray := &query.payload.raycast
		json_key(b, "Raycast", first = true)
		json_key(b, "owner", first = true)
		strings.write_u64(b, ray.owner)
		json_key(b, "slot")
		strings.write_u64(b, u64(ray.slot))
		json_key(b, "origin")
		json_write_vec3(b, ray.origin)
		json_key(b, "dir")
		json_write_vec3(b, ray.dir)
		json_key(b, "max_distance")
		json_write_f32(b, ray.max_distance)
		json_key(b, "exclude")
		json_write_ids(b, ray.exclude)
		strings.write_byte(b, '}')
	case .Overlap:
		overlap := &query.payload.overlap
		json_key(b, "Overlap", first = true)
		json_key(b, "owner", first = true)
		strings.write_u64(b, overlap.owner)
		json_key(b, "slot")
		strings.write_u64(b, u64(overlap.slot))
		json_key(b, "shape")
		switch overlap.shape.tag {
		case .Box:
			json_key(b, "Box", first = true)
			json_write_vec3(b, overlap.shape.payload.box)
		case .Sphere:
			json_key(b, "Sphere", first = true)
			json_write_f32(b, overlap.shape.payload.sphere)
		}
		strings.write_byte(b, '}')
		json_key(b, "pos")
		json_write_vec3(b, overlap.pos)
		json_key(b, "exclude")
		json_write_ids(b, overlap.exclude)
		strings.write_byte(b, '}')
	}
	strings.write_byte(b, '}')
}

json_write_light :: proc(b: ^strings.Builder, light: ^Light) {
	switch light.tag {
	case .Ambient:
		json_key(b, "Ambient", first = true)
		json_write_rgb(b, light.payload.ambient)
	case .Directional:
		directional := &light.payload.directional
		json_key(b, "Directional", first = true)
		json_key(b, "dir", first = true)
		json_write_vec3(b, directional.dir)
		json_key(b, "color")
		json_write_rgb(b, directional.color)
		json_key(b, "shadow")
		strings.write_string(b, "true" if directional.shadow else "false")
		strings.write_byte(b, '}')
	case .Point:
		point := &light.payload.point
		json_key(b, "Point", first = true)
		json_key(b, "pos", first = true)
		json_write_vec3(b, point.pos)
		json_key(b, "color")
		json_write_rgb(b, point.color)
		json_key(b, "range")
		json_write_f32(b, point.range)
		strings.write_byte(b, '}')
	}
	strings.write_byte(b, '}')
}

json_write_speaker :: proc(b: ^strings.Builder, speaker: ^Speaker) {
	json_key(b, "id", first = true)
	strings.write_u64(b, speaker.id)
	json_key(b, "sound")
	strings.write_u64(b, u64(speaker.sound))
	json_key(b, "gain")
	json_write_f32(b, speaker.gain)
	json_key(b, "pitch")
	json_write_f32(b, speaker.pitch)
	json_key(b, "at")
	json_write_place(b, &speaker.at)
	json_key(b, "repeat")
	json_write_tag(b, speaker.repeat)
	strings.write_byte(b, '}')
}

json_write_place :: proc(b: ^strings.Builder, place: ^Place) {
	switch place.tag {
	case .Here:
		json_write_tag(b, place.tag)
	case .At:
		json_key(b, "At", first = true)
		json_key(b, "pos", first = true)
		json_write_vec3(b, place.payload.at.pos)
		json_key(b, "range")
		json_write_f32(b, place.payload.at.range)
		strings.write_string(b, "}}")
	}
}

json_write_element :: proc(b: ^strings.Builder, element: ^Element) {
	switch element.tag {
	case .Panel:
		config, children := &element.payload.panel._0, element.payload.panel._1
		json_key(b, "Panel", first = true)
		json_key(b, "config", first = true)
		json_write_panel_config(b, config)
		json_key(b, "children")
		json_write_list(b, children, json_write_element)
		strings.write_byte(b, '}')
	case .Text:
		text := &element.payload.text
		json_key(b, "Text", first = true)
		json_key(b, "str", first = true)
		json_write_roc_str(b, &text.str)
		json_key(b, "size")
		json_write_f32(b, text.size)
		json_key(b, "color")
		json_write_rgba(b, text.color)
		json_key(b, "wrap")
		json_write_tag(b, text.wrap)
		strings.write_byte(b, '}')
	}
	strings.write_byte(b, '}')
}

json_write_panel_config :: proc(b: ^strings.Builder, config: ^Panel_Config) {
	json_key(b, "id", first = true)
	strings.write_u64(b, config.id)
	json_key(b, "width")
	json_write_sizing(b, config.width)
	json_key(b, "height")
	json_write_sizing(b, config.height)
	json_key(b, "pad")
	json_key(b, "left", first = true)
	json_write_f32(b, config.pad.left)
	json_key(b, "right")
	json_write_f32(b, config.pad.right)
	json_key(b, "top")
	json_write_f32(b, config.pad.top)
	json_key(b, "bottom")
	json_write_f32(b, config.pad.bottom)
	strings.write_byte(b, '}')
	json_key(b, "gap")
	json_write_f32(b, config.gap)
	json_key(b, "direction")
	json_write_tag(b, config.direction)
	json_key(b, "child_align")
	json_key(b, "x", first = true)
	json_write_tag(b, config.child_align.x)
	json_key(b, "y")
	json_write_tag(b, config.child_align.y)
	strings.write_byte(b, '}')
	json_key(b, "background")
	json_write_rgba(b, config.background)
	json_key(b, "radius")
	json_write_f32(b, config.radius)
	json_key(b, "overflow")
	switch config.overflow.tag {
	case .Visible, .Clip:
		json_write_tag(b, config.overflow.tag)
	case .Scroll:
		json_key(b, "Scroll", first = true)
		json_key(b, "x", first = true)
		json_write_f32(b, config.overflow.payload.scroll.x)
		json_key(b, "y")
		json_write_f32(b, config.overflow.payload.scroll.y)
		strings.write_string(b, "}}")
	}
	json_key(b, "floating")
	switch config.floating.tag {
	case .NoFloat:
		json_write_tag(b, config.floating.tag)
	case .Float:
		float := &config.floating.payload.float
		json_key(b, "Float", first = true)
		json_key(b, "to", first = true)
		json_write_tag(b, float.to)
		json_key(b, "attach")
		json_write_tag(b, float.attach)
		json_key(b, "on")
		json_write_tag(b, float.on)
		json_key(b, "offset")
		json_key(b, "x", first = true)
		json_write_f32(b, float.offset.x)
		json_key(b, "y")
		json_write_f32(b, float.offset.y)
		strings.write_string(b, "}}}")
	}
	json_key(b, "image")
	switch config.image.tag {
	case .NoImage:
		json_write_tag(b, config.image.tag)
	case .Show:
		show := &config.image.payload.show
		json_key(b, "Show", first = true)
		json_key(b, "image", first = true)
		json_write_image(b, &show._0)
		json_key(b, "fit")
		json_write_tag(b, show._1)
		strings.write_string(b, "}}")
	}
	strings.write_byte(b, '}')
}

json_write_image :: proc(b: ^strings.Builder, image: ^Image_Ref) {
	json_key(b, "id", first = true)
	strings.write_uint(b, uint(image.id))
	json_key(b, "region")
	switch image.region.tag {
	case .Whole:
		json_write_tag(b, image.region.tag)
	case .Px:
		px := image.region.payload.px
		json_key(b, "Px", first = true)
		json_key(b, "x", first = true)
		strings.write_uint(b, uint(px.x))
		json_key(b, "y")
		strings.write_uint(b, uint(px.y))
		json_key(b, "w")
		strings.write_uint(b, uint(px.w))
		json_key(b, "h")
		strings.write_uint(b, uint(px.h))
		strings.write_string(b, "}}")
	}
	json_key(b, "tint")
	json_write_rgba(b, image.tint)
	json_key(b, "filter")
	json_write_tag(b, image.filter)
	strings.write_byte(b, '}')
}

json_write_sizing :: proc(b: ^strings.Builder, sizing: Sizing) {
	switch sizing.tag {
	case .Fit:
		json_key(b, "Fit", first = true)
		json_write_sizing_range(b, sizing.payload.fit)
	case .Grow:
		json_key(b, "Grow", first = true)
		json_write_sizing_range(b, sizing.payload.grow)
	case .Fixed:
		json_key(b, "Fixed", first = true)
		json_write_f32(b, sizing.payload.fixed)
	case .Percent:
		json_key(b, "Percent", first = true)
		json_write_f32(b, sizing.payload.percent)
	}
	strings.write_byte(b, '}')
}

json_write_sizing_range :: proc(b: ^strings.Builder, r: Sizing_Range) {
	json_key(b, "min", first = true)
	json_write_f32(b, r.min)
	json_key(b, "max")
	json_write_f32(b, r.max)
	strings.write_byte(b, '}')
}

json_write_vec3 :: proc(b: ^strings.Builder, v: Vec3) {
	json_key(b, "x", first = true)
	json_write_f32(b, v.x)
	json_key(b, "y")
	json_write_f32(b, v.y)
	json_key(b, "z")
	json_write_f32(b, v.z)
	strings.write_byte(b, '}')
}

json_write_quat :: proc(b: ^strings.Builder, q: Quat) {
	json_key(b, "x", first = true)
	json_write_f32(b, q.x)
	json_key(b, "y")
	json_write_f32(b, q.y)
	json_key(b, "z")
	json_write_f32(b, q.z)
	json_key(b, "w")
	json_write_f32(b, q.w)
	strings.write_byte(b, '}')
}

json_write_rgb :: proc(b: ^strings.Builder, c: Rgb) {
	json_key(b, "r", first = true)
	json_write_f32(b, c.r)
	json_key(b, "g")
	json_write_f32(b, c.g)
	json_key(b, "b")
	json_write_f32(b, c.b)
	strings.write_byte(b, '}')
}

json_write_rgba :: proc(b: ^strings.Builder, c: Rgba) {
	json_key(b, "r", first = true)
	json_write_f32(b, c.r)
	json_key(b, "g")
	json_write_f32(b, c.g)
	json_key(b, "b")
	json_write_f32(b, c.b)
	json_key(b, "a")
	json_write_f32(b, c.a)
	strings.write_byte(b, '}')
}

// The shortest text that reads back as the same f32. NaN and Inf are not
// JSON numbers, so they are null.
json_write_f32 :: proc(b: ^strings.Builder, v: f32) {
	if math.is_nan(v) || math.is_inf(v) {
		strings.write_string(b, "null")
		return
	}
	buf: [32]u8
	text := string(strconv.write_float(buf[:], f64(v), 'g', -1, 32))
	strings.write_string(b, strings.trim_prefix(text, "+"))
}

json_write_ids :: proc(b: ^strings.Builder, ids: Roc_List(u64)) {
	strings.write_byte(b, '[')
	for id, i in ids.elements[:ids.length] {
		if i > 0 {
			strings.write_byte(b, ',')
		}
		strings.write_u64(b, id)
	}
	strings.write_byte(b, ']')
}

json_write_list :: proc(b: ^strings.Builder, list: Roc_List($T), write: proc(b: ^strings.Builder, value: ^T)) {
	strings.write_byte(b, '[')
	for &value, i in list.elements[:list.length] {
		if i > 0 {
			strings.write_byte(b, ',')
		}
		write(b, &value)
	}
	strings.write_byte(b, ']')
}

// A payload-free tag. The glue enum names are the Vocabulary's tag names.
json_write_tag :: proc(b: ^strings.Builder, tag: $E) {
	strings.write_byte(b, '"')
	fmt.sbprint(b, tag)
	strings.write_byte(b, '"')
}

// The first key opens the object. A tag with a payload is an object with one
// key, so it starts with this too.
@(private = "file")
json_key :: proc(b: ^strings.Builder, key: string, first := false) {
	strings.write_byte(b, '{' if first else ',')
	strings.write_byte(b, '"')
	strings.write_string(b, key)
	strings.write_string(b, `":`)
}

json_write_shadow :: proc(b: ^strings.Builder, shadow: ^Shadow) {
	json_key(b, "distance", first = true)
	json_write_f32(b, shadow.distance)
	json_key(b, "normal_bias")
	json_write_f32(b, shadow.normal_bias)
	json_key(b, "depth_bias")
	json_write_f32(b, shadow.depth_bias)
	json_key(b, "distribution")
	json_write_f32(b, shadow.distribution)
	json_key(b, "blend")
	json_write_f32(b, shadow.blend)
	json_key(b, "filter")
	json_write_tag(b, shadow.filter)
	strings.write_byte(b, '}')
}

json_write_emitter :: proc(b: ^strings.Builder, e: ^Emitter) {
	json_key(b, "id", first = true)
	strings.write_u64(b, e.id)
	json_key(b, "seed")
	strings.write_u64(b, e.seed)
	json_key(b, "position")
	json_write_vec3(b, e.position)
	json_key(b, "velocity")
	json_write_vec3(b, e.velocity)
	json_key(b, "velocity_spread")
	json_write_vec3(b, e.velocity_spread)
	json_key(b, "rate")
	json_write_f32(b, e.rate)
	json_key(b, "lifetime")
	json_write_f32(b, e.lifetime)
	json_key(b, "start_size")
	json_write_f32(b, e.start_size)
	json_key(b, "end_size")
	json_write_f32(b, e.end_size)
	json_key(b, "drag")
	json_write_f32(b, e.drag)
	json_key(b, "start_colour")
	json_write_rgba(b, e.start_colour)
	json_key(b, "end_colour")
	json_write_rgba(b, e.end_colour)
	json_key(b, "image")
	strings.write_u64(b, u64(e.image))
	json_key(b, "blend")
	json_write_tag(b, e.blend)
	strings.write_byte(b, '}')
}
