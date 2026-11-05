#+test
package engine

import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

@(test)
test_sky_filter_preserves_constant_linear_radiance :: proc(t: ^testing.T) {
	pixels := make([]byte, 6 * 8 * 8 * 4, context.temp_allocator)
	for i in 0 ..< len(pixels) / 4 {
		copy(pixels[i * 4:], []byte{64, 128, 192, 255})
	}
	lighting := sky_lighting_build(8, pixels, context.allocator)
	defer sky_lighting_delete(lighting, context.allocator)
	for tex in ([2]Sky_Lighting_Texture{lighting.diffuse, lighting.specular}) {
		for level in tex.levels {
			values := ([^]f16)(raw_data(level.pixels))[:len(level.pixels) / 2]
			for i in 0 ..< len(values) / 4 {
				for k in 0 ..< 3 {
					testing.expect(t, abs(f32(values[i * 4 + k]) - srgb_to_linear(f32(pixels[k]) / 255)) < 0.0005)
				}
			}
		}
	}
}

@(test)
test_sky_roughness_spreads_a_bright_face_and_keeps_orientation :: proc(t: ^testing.T) {
	pixels := make([]byte, 6 * 32 * 32 * 4, context.temp_allocator)
	for i in 0 ..< 32 * 32 { copy(pixels[i * 4:], []byte{255, 255, 255, 255}) }
	lighting := sky_lighting_build(32, pixels, context.allocator)
	defer sky_lighting_delete(lighting, context.allocator)
	sharp := ([^]f16)(raw_data(lighting.specular.levels[0].pixels))[:len(lighting.specular.levels[0].pixels) / 2]
	rough := ([^]f16)(raw_data(lighting.specular.levels[len(lighting.specular.levels) - 1].pixels))[:len(lighting.specular.levels[len(lighting.specular.levels) - 1].pixels) / 2]
	testing.expect_value(t, sharp[(16 * 32 + 16) * 4], f16(1))
	testing.expect_value(t, sharp[(2 * 32 * 32 + 16 * 32 + 16) * 4], f16(0))
	testing.expect(t, rough[0] > 0.3 && rough[0] < 0.8)
	testing.expect(t, rough[2 * 4] > 0.01)
	for face in 0 ..< 6 {
		for xy in ([3][2]f32{{0, 0}, {-0.7, 0.4}, {0.6, -0.8}}) {
			f, u, v := sky_direction_face(sky_face_direction(face, xy.x, xy.y))
			testing.expect_value(t, f, face)
			testing.expect(t, abs(u - xy.x) < 1e-5 && abs(v - xy.y) < 1e-5)
		}
	}
}

@(test)
test_sky_and_image_loads_release_scratch_and_owned_pixels :: proc(t: ^testing.T) {
	pixels := make([]byte, 64 * 64 * 4, context.temp_allocator)
	for &p in pixels { p = 128 }
	png := png_make(64, 64, PNG_RGBA, pixels)
	files := make(map[string][]byte, context.temp_allocator)
	for face in SKY_FACES { files[strings.concatenate({"sky/valid/", face, ".png"}, context.temp_allocator)] = png }
	files["image/valid.png"] = png
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	frame: vmem.Arena
	defer vmem.arena_destroy(&frame)
	context.temp_allocator = vmem.arena_allocator(&frame)
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	skies: Sky_Table
	sky_table_init(&skies, SMALL_SKIES, allocator, allocator)
	images: Image_Table
	image_table_init(&images, SMALL_IMAGES, allocator, allocator)
	baseline := tracking.current_memory_allocated
	for _ in 0 ..< 3 {
		before := frame.total_used
		id, _, ok := sky_load_dir(&skies, strings.concatenate({dir, "/sky"}, context.temp_allocator), "sky/valid")
		testing.expect(t, ok)
		sky, found := sky_resolve(&skies, id)
		testing.expect(t, found)
		testing.expect_value(t, sky.side, 64)
		testing.expect_value(t, len(sky.pixels), 6 * 64 * 64 * 4)
		testing.expect_value(t, sky.specular_max_lod, f32(6))
		sky_table_remove(&skies, sky_slot(id))
		image_id, _, image_ok := image_load_file(&images, strings.concatenate({dir, "/image"}, context.temp_allocator), "image/valid")
		testing.expect(t, image_ok)
		image_table_remove(&images, image_slot(image_id))
		testing.expect(t, frame.total_used - before < 1024)
		testing.expect_value(t, tracking.current_memory_allocated, baseline)
	}
	sky_table_destroy(&skies)
	image_table_destroy(&images)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(test)
test_sky_preparation_cost :: proc(t: ^testing.T) {
	pixels := make([]byte, 6 * 256 * 256 * 4, context.temp_allocator)
	for &p, i in pixels { p = byte(i % 256) }
	start := time.now()
	lighting := sky_lighting_build(256, pixels, context.allocator)
	elapsed := time.since(start)
	fmt.printf("sky preparation: source=256 samples=%v elapsed_ms=%.3f lighting_bytes=%v\n", SKY_FILTER_SAMPLES, time.duration_seconds(elapsed) * 1000, len(lighting.diffuse.pixels) + len(lighting.specular.pixels))
	sky_lighting_delete(lighting, context.allocator)
}

@(test)
test_source_resolution_sky_exceeds_frame_scratch_without_reduction :: proc(t: ^testing.T) {
	pixels := make([]byte, 1024 * 1024 * 4, context.temp_allocator)
	for &p in pixels { p = 128 }
	png := png_make(1024, 1024, PNG_RGBA, pixels)
	files := make(map[string][]byte, context.temp_allocator)
	for face in SKY_FACES { files[strings.concatenate({"valid/", face, ".png"}, context.temp_allocator)] = png }
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	frame: vmem.Arena
	vmem.arena_init_static(&frame, FRAME_ARENA_RESERVE) or_else panic("cannot reserve frame arena")
	defer vmem.arena_destroy(&frame)
	context.temp_allocator = vmem.arena_allocator(&frame)
	skies: Sky_Table
	sky_table_init(&skies, SMALL_SKIES, context.allocator, context.allocator)
	defer sky_table_destroy(&skies)
	id, _, ok := sky_load_dir(&skies, dir, "sky/valid")
	testing.expect(t, ok)
	sky, _ := sky_resolve(&skies, id)
	testing.expect_value(t, sky.side, 1024)
	testing.expect_value(t, len(sky.pixels), 6 * 1024 * 1024 * 4)
	testing.expect_value(t, sky_lighting_params(sky), [4]f32{1, 7, 0, 0})
	testing.expect_value(t, sky_lighting_params(nil), [4]f32{})
	testing.expect_value(t, frame.total_used, uint(0))
}
