#+test
package engine

import "core:strings"
import "core:testing"

// Slot 0 and two skies.
SMALL_SKIES :: 3

@(test)
test_sky_table_holds_its_capacity_and_refuses_the_next_sky :: proc(t: ^testing.T) {
	table: Sky_Table
	sky_table_init(&table, SMALL_SKIES, context.allocator, context.allocator)
	defer sky_table_destroy(&table)

	for name in ([]string{"sky/a", "sky/b"}) {
		_, ok := sky_table_add(&table, strings.clone(name), 1, nil)
		testing.expectf(t, ok, "expected %v to fit", name)
	}
	testing.expect(t, sky_table_full(&table))
	_, ok := sky_table_add(&table, "sky/c", 1, nil)
	testing.expect(t, !ok)
	_, reason, loaded := sky_load_dir(&table, NO_ASSETS_DIR, "sky/c")
	testing.expect(t, !loaded)
	testing.expect_value(t, reason, "the sky table is full at 2 skies")
	testing.expect_value(t, table.count, SMALL_SKIES)

	sky_table_remove(&table, SMALL_SKIES - 1)
	slot, refilled := sky_table_add(&table, strings.clone("sky/d"), 1, nil)
	testing.expect(t, refilled)
	testing.expect_value(t, slot, SMALL_SKIES - 1)
}

@(test)
test_sky_table_draws_no_sky_for_an_id_past_its_capacity :: proc(t: ^testing.T) {
	table: Sky_Table
	sky_table_init(&table, SMALL_SKIES, context.allocator, context.allocator)
	defer sky_table_destroy(&table)

	_, ok := sky_resolve(&table, SMALL_SKIES)
	testing.expect(t, !ok)
	testing.expect_value(t, len(table.logged), 1)
}

// Two skies, a and b, with no pixels.
sky_view_fixture :: proc(table: ^Sky_Table) -> (a, b: u32) {
	sky_table_init(table, SMALL_SKIES, context.allocator, context.allocator)
	slot_a, _ := sky_table_add(table, strings.clone("sky/a"), 1, nil)
	slot_b, _ := sky_table_add(table, strings.clone("sky/b"), 1, nil)
	return sky_id(table, slot_a), sky_id(table, slot_b)
}

@(test)
test_sky_view_draws_the_sky_alone_with_no_blend :: proc(t: ^testing.T) {
	table: Sky_Table
	a, b := sky_view_fixture(&table)
	defer sky_table_destroy(&table)
	sky_a, _ := sky_resolve(&table, a)

	for blend in ([]Sky_Blend{{}, {to = b, amount = 0}, {to = 0, amount = 0.5}}) {
		view, has_sky := sky_view(&table, a, blend)
		testing.expect(t, has_sky)
		testing.expect_value(t, view, Sky_View{from = sky_a})
	}
}

@(test)
test_sky_view_blends_toward_the_second_sky_and_draws_it_alone_at_1 :: proc(t: ^testing.T) {
	table: Sky_Table
	a, b := sky_view_fixture(&table)
	defer sky_table_destroy(&table)
	sky_a, _ := sky_resolve(&table, a)
	sky_b, _ := sky_resolve(&table, b)

	view, _ := sky_view(&table, a, {to = b, amount = 0.25})
	testing.expect_value(t, view, Sky_View{from = sky_a, to = sky_b, amount = 0.25})
	view, _ = sky_view(&table, a, {to = b, amount = 1})
	testing.expect_value(t, view, Sky_View{from = sky_b})
}

@(test)
test_sky_view_blends_from_no_sky_and_drops_an_unknown_second_sky :: proc(t: ^testing.T) {
	table: Sky_Table
	a, b := sky_view_fixture(&table)
	defer sky_table_destroy(&table)
	sky_b, _ := sky_resolve(&table, b)

	view, has_sky := sky_view(&table, 0, {to = b, amount = 0.5})
	testing.expect(t, has_sky)
	testing.expect_value(t, view, Sky_View{to = sky_b, amount = 0.5})

	_, has_sky = sky_view(&table, 0, {})
	testing.expect(t, !has_sky)
	view, has_sky = sky_view(&table, a, {to = SMALL_SKIES, amount = 0.5})
	testing.expect(t, has_sky)
	testing.expect(t, view.to == nil)
}
