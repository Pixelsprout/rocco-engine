#+test
package engine

import "core:math"
import "core:math/linalg"
import "core:testing"

CLUSTER_TEST_VIEW :: Frame_View{camera = {eye = {0, 0, 0}, target = {0, 0, -1}, up = {0, 1, 0}, fov_y = math.PI / 2}, aspect = 16.0 / 9.0}

point_at :: proc(p: [3]f32, range: f32) -> Packed_Light {
	return {pos = {p.x, p.y, p.z, 1}, color = {1, 1, 1, range}}
}

@(test)
test_clusters_cover_every_sample_inside_each_point_sphere :: proc(t: ^testing.T) {
	points := []Packed_Light{
		point_at({0, 0, -0.1}, 0.2), point_at({-3, 2, -8}, 3),
		point_at({4, -2, -15}, 4), point_at({0, 0, 5}, 6),
		point_at({0, 0, 6}, 1), point_at({120, 0, -5}, 1),
		point_at({0, 0, -200}, 20),
	}
	view := CLUSTER_TEST_VIEW
	frame := cluster_build(points, view, {1920, 1080})
	for p, id in points {
		for dx in -3 ..= 3 {
			for dy in -3 ..= 3 {
				for dz in -3 ..= 3 {
					offset := [3]f32{f32(dx), f32(dy), f32(dz)} * p.color.w / 4
					if linalg.dot(offset, offset) >= p.color.w * p.color.w { continue }
					world := p.pos.xyz + offset
					if index, visible := cluster_test_index(frame, view, world); visible {
						testing.expectf(t, cluster_test_contains(frame, index, u32(id)), "light %v missing at %v in cluster %v", id, world, index)
					}
				}
			}
		}
	}
	testing.expect(t, !frame.overflow)
	for range in frame.ranges {
		testing.expect(t, int(range.offset + range.count) <= len(frame.indices))
		for id in frame.indices[range.offset:range.offset + range.count] {
			testing.expect(t, id != 4 && id != 5)
		}
	}
}

@(test)
test_clusters_keep_the_nearest_64_and_keep_walk_order_on_a_tie :: proc(t: ^testing.T) {
	points: [65]Packed_Light
	for &p in points { p = point_at({0, 0, -10}, 100) }
	view := CLUSTER_TEST_VIEW
	first := cluster_build(points[:], view, {960, 540})
	index, visible := cluster_test_index(first, view, {0, 0, -10})
	testing.expect(t, visible && first.overflow)
	for id in 0 ..< 64 { testing.expect(t, cluster_test_contains(first, index, u32(id))) }
	testing.expect(t, !cluster_test_contains(first, index, 64))
	points[0].pos.x = 20
	second := cluster_build(points[:], view, {960, 540})
	index, _ = cluster_test_index(second, view, {0, 0, -10})
	testing.expect_value(t, second.ranges[index].count, 64)
	testing.expect(t, !cluster_test_contains(second, index, 0))
	for id in 1 ..= 64 { testing.expect(t, cluster_test_contains(second, index, u32(id))) }
}

@(test)
test_clusters_pack_scalar_offsets_across_vector_boundaries :: proc(t: ^testing.T) {
	frame := cluster_build({point_at({-3, 0, -10}, 2), point_at({3, 0, -10}, 2)}, CLUSTER_TEST_VIEW, {960, 540})
	used := u32(0)
	for range in frame.ranges {
		testing.expect_value(t, range.offset, used)
		used += range.count
	}
	testing.expect_value(t, len(frame.indices) % 4, 0)
	testing.expect(t, len(frame.indices) <= CLUSTER_INDEX_LIMIT)
	testing.expect_value(t, CLUSTER_BUFFER_BYTES, 972800)
}

@(test)
test_clusters_use_the_current_camera_and_physical_pixel_size :: proc(t: ^testing.T) {
	view := CLUSTER_TEST_VIEW
	view.camera.eye = {4, 5, 6}
	view.camera.target = {5, 5, 6}
	points := []Packed_Light{point_at({14, 5, 6}, 1)}
	frame := cluster_build(points, view, {1920, 1080})
	index, visible := cluster_test_index(frame, view, {14, 5, 6})
	testing.expect(t, visible && cluster_test_contains(frame, index, 0))
	testing.expect_value(t, frame.grid.xy, [2]f32{16.0 / 1920, 9.0 / 1080})
}

@(test)
test_clusters_have_empty_ranges_without_points :: proc(t: ^testing.T) {
	frame := cluster_build(nil, CLUSTER_TEST_VIEW, {0, 0})
	testing.expect_value(t, len(frame.indices), 4)
	for range in frame.ranges { testing.expect_value(t, range.count, 0) }
	testing.expect(t, !frame.overflow)
}

cluster_test_index :: proc(frame: Cluster_Frame, view: Frame_View, world: [3]f32) -> (index: int, visible: bool) {
	c := cluster_camera(view, frame.points)
	rel := world - c.eye
	depth := linalg.dot(rel, c.forward)
	if depth < SCENE_NEAR { return 0, false }
	x := linalg.dot(rel, c.right) / (depth * c.tan_x)
	y := linalg.dot(rel, c.up) / (depth * c.tan_y)
	if abs(x) > 1 || abs(y) > 1 { return 0, false }
	xi := clamp(int((x + 1) * 0.5 * CLUSTER_X), 0, CLUSTER_X - 1)
	yi := clamp(int((y + 1) * 0.5 * CLUSTER_Y), 0, CLUSTER_Y - 1)
	z := cluster_depth_slice(depth, frame.grid.z)
	return (z * CLUSTER_Y + yi) * CLUSTER_X + xi, true
}

cluster_test_contains :: proc(frame: Cluster_Frame, index: int, id: u32) -> bool {
	range := frame.ranges[index]
	for value in frame.indices[range.offset:range.offset + range.count] {
		if value == id { return true }
	}
	return false
}
