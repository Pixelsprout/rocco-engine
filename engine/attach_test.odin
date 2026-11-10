#+test
package engine

import "core:testing"

node_attach :: proc(draw: u64, joint: string, children: []Node) -> Node {
	return {tag = .Attach, payload = {attach = {_0 = {draw = draw, joint = roc_str_from_slice(joint)}, _1 = roc_list_view(children)}}}
}

// The chain Skin on the Sphere slot, with the Joints named root and tip.
attach_fixture_chain :: proc(f: ^Frame_Fixture) -> u32 {
	id := frame_fixture_skinned(f)
	joints := f.meshes.meshes[Primitive.Sphere].skin.joints
	joints[0].name = "root"
	joints[1].name = "tip"
	return id
}

attach_placed :: proc(f: ^Frame_Fixture, id: u64) -> ^Placed {
	for &p in f.fr.placed {
		if p.draw_id == id {
			return &p
		}
	}
	return nil
}

@(test)
test_attach_places_its_children_at_the_joint_of_the_interpolated_clip_time :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := attach_fixture_chain(&f)

	orb := Draw{id = 2, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}
	scene :: proc(chain: u32, time: f32, orb: Draw) -> Scene {
		nodes := make([]Node, 2, context.temp_allocator)
		nodes[0] = node_attach(1, "tip", draw_nodes({orb}))
		nodes[1] = node_draw({id = 1, mesh = chain, pos = {5, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY, pose = {clip = LIFT, time = time}})
		return scene_nodes(nodes)
	}
	frame_fixture_draw(&f, scene(chain, 0.25, orb), scene(chain, 0.75, orb), 0.5)

	got := attach_placed(&f, 2)
	testing.expect(t, got != nil)
	expect_v3_near(t, got.transform.position, {5, 2, 0})
}

@(test)
test_attach_children_take_the_joint_position_and_rot_but_not_its_scale :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := attach_fixture_chain(&f)
	f.meshes.meshes[Primitive.Sphere].skin.joints[0].rest.scale = 2

	orb := Draw{id = 2, mesh = 1, pos = {1, 0, 0}, scale = {0.5, 0.5, 0.5}, rot = IDENTITY, scale_rot = IDENTITY}
	nodes := []Node{node_draw({id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY, pose = {clip = LIFT}}), node_attach(1, "tip", draw_nodes({orb}))}
	frame_fixture_draw(&f, scene_nodes(nodes), scene_nodes(nodes), 1)

	got := attach_placed(&f, 2)
	testing.expect(t, got != nil)
	// The orb keeps its own offset and scale.
	expect_v3_near(t, got.transform.position, {1, 2, 0})
	testing.expect_value(t, got.transform.scale, [3]f32{0.5, 0.5, 0.5})
	expect_quat_near(t, got.transform.rotation, 1)
}

@(test)
test_attach_ignores_the_pose_of_its_parent_group :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := attach_fixture_chain(&f)

	orb := Draw{id = 2, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}
	attach := []Node{node_attach(1, "tip", draw_nodes({orb}))}
	nodes := []Node{node_group(9, {x = 100}, quat_yaw(1), attach), node_draw({id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY})}
	frame_fixture_draw(&f, scene_nodes(nodes), scene_nodes(nodes), 1)

	got := attach_placed(&f, 2)
	testing.expect(t, got != nil)
	expect_v3_near(t, got.transform.position, {0, 1, 0})
}

@(test)
test_attach_omits_its_children_and_logs_once_for_an_unknown_joint :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := attach_fixture_chain(&f)

	orb := Draw{id = 2, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}
	nodes := []Node{node_draw({id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}), node_attach(1, "hand", draw_nodes({orb}))}
	frame_fixture_draw(&f, scene_nodes(nodes), scene_nodes(nodes), 1)
	frame_fixture_draw(&f, scene_nodes(nodes), scene_nodes(nodes), 1)

	testing.expect(t, attach_placed(&f, 2) == nil)
	testing.expect_value(t, len(f.fr.attach_logged), 1)
	config := &nodes[1].payload.attach._0
	testing.expect_value(
		t,
		attach_message(config, &f.meshes.meshes[Primitive.Sphere], .No_Joint),
		`an Attach names joint "hand" of draw id 1, but mesh "primitive/sphere" has no such Joint; its Joints are "root", "tip"`,
	)
}

@(test)
test_attach_omits_its_children_for_a_missing_draw_or_a_rigid_mesh :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	orb := Draw{id = 2, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}
	nodes := []Node{node_draw({id = 1, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}), node_attach(1, "tip", draw_nodes({orb})), node_attach(3, "tip", draw_nodes({orb}))}
	frame_fixture_draw(&f, scene_nodes(nodes), scene_nodes(nodes), 1)

	testing.expect(t, attach_placed(&f, 2) == nil)
	testing.expect_value(t, len(f.fr.attach_logged), 2)
}

@(test)
test_attach_moves_its_colliders_with_the_joint :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := attach_fixture_chain(&f)

	collider := []Node{node_collider({id = 4, pos = {1, 0, 0}, rot = IDENTITY})}
	nodes := []Node{node_attach(1, "tip", collider), node_draw({id = 1, mesh = chain, pos = {0, 0, 3}, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY})}

	got := scene_colliders(nodes, &f.meshes, context.temp_allocator)
	testing.expect_value(t, len(got), 1)
	expect_v3_near(t, vec3_array(got[0].pos), {1, 1, 3})
	testing.expect_value(t, len(scene_colliders(nodes, nil, context.temp_allocator)), 0)
}

@(test)
test_attach_interpolates_the_local_pose_of_a_group_under_it :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := attach_fixture_chain(&f)

	scene :: proc(chain: u32, x: f32) -> Scene {
		orb := draw_nodes({{id = 2, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}})
		group := make([]Node, 1, context.temp_allocator)
		group[0] = node_group(9, {x = x}, IDENTITY, orb)
		nodes := make([]Node, 2, context.temp_allocator)
		nodes[0] = node_draw({id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY})
		nodes[1] = node_attach(1, "tip", group)
		return scene_nodes(nodes)
	}
	frame_fixture_draw(&f, scene(chain, 0), scene(chain, 2), 0.5)

	got := attach_placed(&f, 2)
	testing.expect(t, got != nil)
	expect_v3_near(t, got.transform.position, {1, 1, 0})
}
