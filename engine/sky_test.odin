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
