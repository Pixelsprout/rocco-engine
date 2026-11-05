#+test
package engine

import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:testing"

@(test)
test_pairing_finds_the_previous_draw_by_id :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, context.allocator)
	defer pairing_destroy(&p)

	nodes := draw_nodes({{id = 7}, {id = 3}})
	pairing_build(&p, nodes)
	found, _, ok := pairing_draw(&p, 3, {})
	testing.expect(t, ok && found == &nodes[1].payload.draw)
	_, _, missing := pairing_draw(&p, 9, {})
	testing.expect(t, !missing)

	pairing_build(&p, draw_nodes({{id = 9}}))
	_, _, stale := pairing_draw(&p, 7, {})
	testing.expect(t, !stale)
}

@(test)
test_pairing_keeps_the_first_of_a_duplicate_id_and_logs_it_once :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, context.allocator)
	defer pairing_destroy(&p)

	nodes := draw_nodes({{id = 5}, {id = 5}, {id = 5}})
	pairing_build(&p, nodes)
	pairing_build(&p, draw_nodes({{id = 5}, {id = 5}}))
	pairing_build(&p, nodes)
	first, _, _ := pairing_draw(&p, 5, {})
	testing.expect(t, first == &nodes[0].payload.draw)
	testing.expect_value(t, len(p.logged), 1)
}

@(test)
test_pairing_builds_its_capacity_of_draws_and_groups_without_allocating :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, mem.tracking_allocator(&track))
	defer pairing_destroy(&p)

	draws := make([]Draw, SMALL_DRAWS)
	defer delete(draws)
	for &d, i in draws {
		d.id = u64(i)
	}
	groups := make([]Node, SMALL_GROUPS + 1)
	defer delete(groups)
	groups[0] = node_group(100, {}, IDENTITY, draw_nodes(draws))
	for i in 1 ..< len(groups) {
		groups[i] = node_group(u64(100 + i), {}, IDENTITY, nil)
	}
	after_init := track.total_allocation_count
	pairing_build(&p, groups[:SMALL_GROUPS])
	testing.expect_value(t, track.total_allocation_count, after_init)
	testing.expect(t, !p.over_capacity_logged)
	testing.expect_value(t, len(p.groups), SMALL_GROUPS)

	// Past group_capacity the first Groups pair, and the map does not grow.
	pairing_build(&p, groups)
	testing.expect_value(t, track.total_allocation_count, after_init)
	testing.expect_value(t, len(p.groups), SMALL_GROUPS)
	testing.expect(t, pairing_group(&p, 100 + SMALL_GROUPS) == nil)
	testing.expect(t, p.groups_full_logged)
}

@(test)
test_pairing_logs_once_when_a_scene_has_more_draws_than_its_capacity :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, context.allocator)
	defer pairing_destroy(&p)

	draws := make([]Draw, SMALL_DRAWS + 1)
	defer delete(draws)
	for &d, i in draws {
		d.id = u64(i)
	}
	pairing_build(&p, draw_nodes(draws[:SMALL_DRAWS]))
	testing.expect(t, !p.over_capacity_logged)
	nodes := draw_nodes(draws)
	pairing_build(&p, nodes)
	testing.expect(t, p.over_capacity_logged)
	found, _, ok := pairing_draw(&p, SMALL_DRAWS, {})
	testing.expect(t, ok && found == &nodes[SMALL_DRAWS].payload.draw)
}

@(test)
test_pairing_keeps_the_first_of_a_duplicate_group_id_and_logs_once :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, context.allocator)
	defer pairing_destroy(&p)

	inner := []Node{node_group(5, {x = 2}, IDENTITY, nil)}
	nodes := []Node{node_group(5, {x = 1}, IDENTITY, inner), node_group(5, {x = 3}, IDENTITY, nil), node_group(6, {}, IDENTITY, nil), node_group(6, {}, IDENTITY, nil)}
	pairing_build(&p, nodes)
	testing.expect_value(t, pairing_group(&p, 5).local.pos, [3]f32{1, 0, 0})
	testing.expect(t, p.group_duplicate_logged)
}

@(test)
test_a_draw_on_a_turning_group_follows_an_arc_not_a_chord :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	drop := draw_nodes({{id = 10, mesh = 1, pos = {0, 0, 2}, scale = {1, 1, 1}, rot = IDENTITY}})
	prev := []Node{node_group(1, {}, IDENTITY, drop)}
	curr := []Node{node_group(1, {}, quat_yaw(math.PI / 2), drop)}
	got := frame_fixture_draw(&f, scene_nodes(prev), scene_nodes(curr), 0.5)

	testing.expect_value(t, len(got), 1)
	at := got[0].model[3].xyz
	// The chord's midpoint is (1, 0, 1), inside the circle of radius 2.
	expect_v3_near(t, at, {math.SQRT_TWO, 0, math.SQRT_TWO})
	testing.expect(t, abs(linalg.length(at) - 2) < EPS)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = at, scale = {1, 1, 1}, rotation = quat_from_axis_angle(UP, math.PI / 4), scale_rotation = 1}))
}

@(test)
test_a_node_that_changes_parent_interpolates_in_world_space :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	in_a := draw_nodes({{id = 10, mesh = 1, pos = {1, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}})
	in_b := draw_nodes({{id = 10, mesh = 1, pos = {0, 0, 4}, scale = {1, 1, 1}, rot = IDENTITY}})
	prev := []Node{node_group(1, {x = 10}, IDENTITY, in_a), node_group(2, {}, quat_yaw(math.PI / 2), nil)}
	curr := []Node{node_group(1, {x = 10}, IDENTITY, nil), node_group(2, {}, quat_yaw(math.PI / 2), in_b)}
	got := frame_fixture_draw(&f, scene_nodes(prev), scene_nodes(curr), 0.5)

	testing.expect_value(t, len(got), 1)
	// World (11, 0, 0) before and (4, 0, 0) after. Interpolating the local
	// Poses under Group 2 would give (2, 0, -0.5).
	expect_v3_near(t, got[0].model[3].xyz, {7.5, 0, 0})
	expect_quat_near(t, linalg.quaternion_from_matrix4(got[0].model), quat_from_axis_angle(UP, math.PI / 4))
}

@(test)
test_a_node_that_leaves_the_root_for_a_group_interpolates_in_world_space :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := draw_nodes({{id = 10, mesh = 1, pos = {2, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}})
	curr := []Node{node_group(1, {x = 4}, IDENTITY, draw_nodes({{id = 10, mesh = 1, pos = {2, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}}))}
	got := frame_fixture_draw(&f, scene_nodes(prev), scene_nodes(curr), 0.5)

	expect_v3_near(t, got[0].model[3].xyz, {4, 0, 0})
}

@(test)
test_a_draw_that_leaves_a_duplicate_group_draws_at_its_current_pose :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	in_duplicate := draw_nodes({{id = 10, mesh = 1, pos = {1, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}})
	prev := []Node{node_group(1, {x = 10}, IDENTITY, nil), node_group(1, {x = 20}, IDENTITY, in_duplicate)}
	curr := []Node{node_group(2, {}, IDENTITY, draw_nodes({{id = 10, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY}}))}
	got := frame_fixture_draw(&f, scene_nodes(prev), scene_nodes(curr), 0.5)

	// Pairing with the first Group 1 would start the Draw at (11, 0, 0).
	expect_v3_near(t, got[0].model[3].xyz, {0, 0, 0})
}

@(test)
test_a_draw_that_leaves_a_group_past_the_capacity_draws_at_its_current_pose :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := make([]Node, SMALL_GROUPS + 1, context.temp_allocator)
	for i in 0 ..< SMALL_GROUPS {
		prev[i] = node_group(u64(i), {}, IDENTITY, nil)
	}
	prev[SMALL_GROUPS] = node_group(100, {x = 20}, IDENTITY, draw_nodes({{id = 10, mesh = 1, pos = {1, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}}))
	curr := draw_nodes({{id = 10, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY}})
	got := frame_fixture_draw(&f, scene_nodes(prev), scene_nodes(curr), 0.5)

	expect_v3_near(t, got[0].model[3].xyz, {0, 0, 0})
}

@(test)
test_a_group_with_no_partner_places_its_children_at_its_pose :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	child := draw_nodes({{id = 10, mesh = 1, pos = {0, 0, 1}, scale = {1, 1, 1}, rot = IDENTITY}})
	prev := []Node{node_group(7, {}, IDENTITY, child)}
	curr := []Node{node_group(8, {x = 3}, quat_yaw(math.PI / 2), child)}
	got := frame_fixture_draw(&f, scene_nodes(prev), scene_nodes(curr), 0.5)

	// Draw 10 changed parent, from Group 7 at the origin to Group 8.
	expect_v3_near(t, got[0].model[3].xyz, {2, 0, 0.5})
}

// The rule of Pose.compose in packages/linalg: a child turns by its own rot,
// then by its parent's.
@(test)
test_nested_groups_compose_as_pose_compose_does :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	leaf := draw_nodes({{id = 10, mesh = 1, pos = {0, 0, 1}, scale = {1, 1, 1}, rot = quat_yaw(0.25)}})
	inner := []Node{node_group(2, {z = 1}, quat_yaw(0.5), leaf)}
	scene := scene_nodes({node_group(1, {x = 1}, quat_yaw(math.PI / 2), inner)})
	got := frame_fixture_draw(&f, scene, scene, 0)

	inner_world := Pose{pos = {2, 0, 0}, rot = quat_from_axis_angle(UP, math.PI / 2 + 0.5)}
	want := pose_compose(inner_world, pose_of({z = 1}, quat_yaw(0.25)))
	expect_v3_near(t, got[0].model[3].xyz, want.pos)
	expect_quat_near(t, linalg.quaternion_from_matrix4(got[0].model), quat_from_axis_angle(UP, math.PI / 2 + 0.75))
}

@(test)
test_a_group_moves_a_point_turns_a_directional_and_leaves_an_ambient :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights := light_nodes({light_ambient({r = 0.5}), light_directional({z = -1}, {g = 1}), light_point({z = 1}, {b = 1}, 4)})
	near := node_draw({id = 1, mesh = 1, pos = {1, 5, 0}, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY})
	scene := scene_nodes({node_group(1, {y = 5}, quat_yaw(math.PI / 2), lights), near})
	got := frame_fixture_draw(&f, scene, scene, 0)

	testing.expect_value(t, f.rec.lights.ambient, [4]f32{0.5, 0, 0, 1})
	lit := got[0]
	// The light travels along -x, so the direction to it is +x.
	expect_v3_near(t, lit.light_pos[0].xyz, {1, 0, 0})
	testing.expect_value(t, lit.light_pos[0].w, 0)
	expect_v3_near(t, f.rec.clusters.points[0].pos.xyz, {1, 5, 0})
	testing.expect_value(t, f.rec.clusters.points[0].pos.w, 1)
	testing.expect_value(t, f.rec.clusters.points[0].color, [4]f32{0, 0, 1, 4})
}

@(test)
test_a_light_takes_the_interpolated_pose_of_its_group :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	centre := node_draw({id = 1, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY})
	prev := []Node{node_group(1, {}, IDENTITY, light_nodes({light_point({z = 9}, {r = 1}, 4)})), centre}
	curr := []Node{node_group(1, {}, quat_yaw(math.PI / 2), light_nodes({light_point({z = 2}, {r = 1}, 4)})), centre}
	frame_fixture_draw(&f, scene_nodes(prev), scene_nodes(curr), 0.5)

	// The Light's own pos comes from the current Scene.
	expect_v3_near(t, f.rec.clusters.points[0].pos.xyz, {math.SQRT_TWO, 0, math.SQRT_TWO})
}

@(test)
test_the_sun_follows_a_depth_first_walk_and_takes_slot_0 :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	grouped := light_nodes({light_point({}, {r = 1}, 1), light_sun({y = -1}, {g = 1})})
	nodes := make([dynamic]Node, context.temp_allocator)
	// The shadow pass runs only with a Draw to cast a shadow.
	append(&nodes, node_draw({id = 1, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}))
	append(&nodes, node_group(1, {}, IDENTITY, grouped))
	append(&nodes, ..light_nodes({light_sun({x = -1}, {b = 1})}))
	scene := scene_nodes(nodes[:])
	got := frame_fixture_draw(&f, scene, scene, 0)

	testing.expect_value(t, f.rec.lights.shadow.y, 0)
	// The first Sun in walk order is inside the Group. The second lights as a plain Directional.
	testing.expect_value(t, got[0].light_color[0], [4]f32{0, 1, 0, 0})
	testing.expect_value(t, got[0].light_color[1], [4]f32{0, 0, 1, 0})
	testing.expect_value(t, f.rec.clusters.points[0].pos, [4]f32{0, 0, 0, 1})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Second_Sun})
}

@(test)
test_a_group_draws_its_children_after_the_draw_capacity_counts_them :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := make([]Draw, f.fr.draw_capacity + 1, context.temp_allocator)
	for &d, i in draws {
		d.id = u64(i)
		d.mesh = 1
	}
	scene := scene_nodes({node_group(1, {}, IDENTITY, draw_nodes(draws)), node_light(light_ambient({r = 1}))})
	got := frame_fixture_draw(&f, scene, scene, 0)

	testing.expect_value(t, len(got), f.fr.draw_capacity)
	testing.expect(t, f.fr.draws_logged)
	testing.expect_value(t, f.rec.lights.ambient, [4]f32{1, 0, 0, 0})
}

@(test)
test_scene_colliders_compose_each_world_pose_from_the_scene :: proc(t: ^testing.T) {
	box := Collider {
		id = 5,
		pos = {z = 1},
		rot = quat_yaw(0.25),
		shape = {tag = .Box, payload = {box = {x = 1, y = 1, z = 1}}},
	}
	ball := Collider {
		id = 6,
		pos = {x = 9},
		rot = IDENTITY,
		shape = {tag = .Sphere, payload = {sphere = 1}},
	}
	inner := []Node{node_collider(box)}
	nodes := []Node{node_group(1, {x = 2}, quat_yaw(math.PI / 2), inner), node_collider(ball)}
	got := scene_colliders(nodes, context.temp_allocator)

	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0].id, 5)
	expect_v3_near(t, vec3_array(got[0].pos), {3, 0, 0})
	expect_quat_near(t, quat_of(got[0].rot), quat_from_axis_angle(UP, math.PI / 2 + 0.25))
	testing.expect_value(t, got[0].shape.tag, Collider_Shape_Tag.Box)
	testing.expect_value(t, got[0].shape.payload.box, box.shape.payload.box)
	testing.expect_value(t, got[1].id, 6)
	testing.expect_value(t, got[1].pos, ball.pos)
	testing.expect_value(t, got[1].rot, ball.rot)
}

@(test)
test_scene_colliders_keep_tree_order_past_the_root_count :: proc(t: ^testing.T) {
	ball :: proc(id: u64) -> Node {
		return node_collider({id = id, rot = IDENTITY, shape = {tag = .Sphere, payload = {sphere = 1}}})
	}
	// The Group holds more Colliders than the Scene has root Nodes.
	inner := []Node{ball(1), ball(2), ball(3)}
	nodes := []Node{node_group(9, {}, IDENTITY, inner), ball(4), ball(5)}
	got := scene_colliders(nodes, context.temp_allocator)

	testing.expect_value(t, len(got), 5)
	for c, i in got {
		testing.expect_value(t, c.id, u64(i + 1))
	}
}

@(test)
test_the_queries_see_a_grouped_collider_at_its_world_pose :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	half := Collider_Shape {
		tag = .Box,
		payload = {box = {x = 0.5, y = 0.5, z = 0.5}},
	}
	// At local (0, 0, 2) under a quarter turn, the box sits at (2, 0, 0).
	inner := []Node{node_collider({id = 1, pos = {z = 2}, rot = IDENTITY, shape = half})}
	nodes := []Node{node_group(9, {}, quat_yaw(math.PI / 2), inner), node_collider({id = 2, pos = {x = 2.5}, rot = IDENTITY, shape = half})}
	queries := []Query{{tag = .ContactsOf, payload = {contacts_of = 1}}}
	answers := queries_answer(&search, scene_colliders(nodes, context.temp_allocator), queries, context.temp_allocator)

	testing.expect_value(t, len(answers.contacts), 1)
	testing.expect_value(t, answers.contacts[0].a, 1)
	testing.expect_value(t, answers.contacts[0].b, 2)
}

expect_v3_near :: proc(t: ^testing.T, got, want: [3]f32, loc := #caller_location) {
	testing.expectf(t, linalg.length(got - want) < EPS, "got %v, want %v", got, want, loc = loc)
}

// A Roc_List over a slice that roc_alloc never saw. The host only reads it.
roc_list_view :: proc(s: []$T) -> Roc_List(T) {
	return {elements = raw_data(s), length = uint(len(s))}
}

scene_nodes :: proc(nodes: []Node) -> Scene {
	return {nodes = roc_list_view(nodes)}
}

node_group :: proc(id: u64, pos: Vec3, rot: Quat, children: []Node) -> Node {
	return {tag = .Group, payload = {group = {_0 = {id = id, pos = pos, rot = rot}, _1 = roc_list_view(children)}}}
}

node_draw :: proc(d: Draw) -> Node {
	return {tag = .Draw, payload = {draw = d}}
}

node_light :: proc(l: Light) -> Node {
	return {tag = .Light, payload = {light = l}}
}

node_collider :: proc(c: Collider) -> Node {
	return {tag = .Collider, payload = {collider = c}}
}

node_speaker :: proc(speaker: Speaker) -> Node {
	return {tag = .Speaker, payload = {speaker = speaker}}
}

// In the temp allocator, so a test can return the slice from a helper.
draw_nodes :: proc(draws: []Draw) -> []Node {
	nodes := make([]Node, len(draws), context.temp_allocator)
	for d, i in draws {
		nodes[i] = node_draw(d)
	}
	return nodes
}

light_nodes :: proc(lights: []Light) -> []Node {
	nodes := make([]Node, len(lights), context.temp_allocator)
	for l, i in lights {
		nodes[i] = node_light(l)
	}
	return nodes
}
