#+build !windows
package engine

import "core:time"

capture_tick :: proc() -> i64 { return i64(time.tick_diff({}, time.tick_now())) }

capture_frequency :: proc() -> i64 { return 1_000_000_000 }

capture_clock_name :: proc() -> string { return "monotonic_nanoseconds" }
