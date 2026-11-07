#+build windows
#+test
package engine

import "core:testing"
import d3d11 "vendor:directx/d3d11"

Gpu_Test_Context :: struct {
	device: d3d11.IDeviceContext,
	calls, bad_flags: int,
	not_ready, stamp_not_ready, disjoint, failed: bool,
}

Gpu_Test_Query :: struct { query: d3d11.IQuery, releases: int }
Gpu_Test_Device :: struct {
	device: d3d11.IDevice,
	queries: [3]Gpu_Test_Query,
	query_vtable: d3d11.IQuery_VTable,
	created: int,
}

gpu_test_get_data :: proc "system" (this: ^d3d11.IDeviceContext, query: ^d3d11.IAsynchronous, data: rawptr, size, flags: u32) -> d3d11.HRESULT {
	fake := (^Gpu_Test_Context)(this)
	fake.calls += 1
	if flags != 1 { fake.bad_flags += 1 }
	if fake.failed { return -1 }
	if fake.not_ready { return 1 }
	if size == size_of(d3d11.QUERY_DATA_TIMESTAMP_DISJOINT) {
		(^d3d11.QUERY_DATA_TIMESTAMP_DISJOINT)(data)^ = {Frequency = 1000, Disjoint = d3d11.BOOL(fake.disjoint)}
	} else {
		if fake.stamp_not_ready { return 1 }
		(^u64)(data)^ = 100
	}
	return 0
}

@(test)
test_gpu_queries_poll_once_without_flushing_or_reading_the_current_frame :: proc(t: ^testing.T) {
	vtable := d3d11.IDeviceContext_VTable{GetData = gpu_test_get_data}
	fake := Gpu_Test_Context{device = {id3d11devicecontext_vtable = &vtable}, not_ready = true}
	timer := Gpu_Timing_Native{active = true, device_context = &fake.device}
	gpu_timing_protocol_init(&timer.protocol, 4, context.allocator)
	defer delete(timer.protocol.rows)
	gpu_timing_protocol_begin(&timer.protocol, 1)
	gpu_timing_native_poll(&timer)
	testing.expect_value(t, fake.calls, 0)
	timer.protocol.current = -1
	gpu_timing_native_poll(&timer)
	testing.expect_value(t, fake.calls, 1)
	testing.expect_value(t, timer.protocol.slots[0], 1)
	fake.not_ready = false
	fake.stamp_not_ready = true
	gpu_timing_native_poll(&timer)
	testing.expect_value(t, fake.calls, 4)
	testing.expect_value(t, timer.protocol.slots[0], 1)
	fake.stamp_not_ready = false
	gpu_timing_native_poll(&timer)
	testing.expect_value(t, fake.calls, 7)
	testing.expect_value(t, fake.bad_flags, 0)
	testing.expect_value(t, timer.protocol.slots[0], 0)
	testing.expect_value(t, timer.protocol.rows[0].status, Gpu_Timing_Status.Valid)
}

@(test)
test_gpu_queries_reject_disjoint_and_keep_failed_queries_owned :: proc(t: ^testing.T) {
	vtable := d3d11.IDeviceContext_VTable{GetData = gpu_test_get_data}
	fake := Gpu_Test_Context{device = {id3d11devicecontext_vtable = &vtable}, disjoint = true}
	timer := Gpu_Timing_Native{active = true, device_context = &fake.device}
	gpu_timing_protocol_init(&timer.protocol, 4, context.allocator)
	defer delete(timer.protocol.rows)
	gpu_timing_protocol_begin(&timer.protocol, 1)
	timer.protocol.current = -1
	gpu_timing_native_poll(&timer)
	testing.expect_value(t, timer.protocol.rows[0].status, Gpu_Timing_Status.Disjoint)
	testing.expect_value(t, timer.protocol.slots[0], 0)
	gpu_timing_protocol_begin(&timer.protocol, 2)
	timer.protocol.current = -1
	fake.failed = true
	gpu_timing_native_poll(&timer)
	testing.expect(t, timer.failed)
	testing.expect_value(t, timer.protocol.rows[1].status, Gpu_Timing_Status.Query_Error)
	testing.expect_value(t, timer.protocol.slots[0], 2)
	fake.failed = false
	gpu_timing_native_poll(&timer)
	testing.expect_value(t, timer.protocol.slots[0], 2)
	gpu_timing_protocol_shutdown(&timer.protocol)
	testing.expect_value(t, timer.protocol.rows[1].status, Gpu_Timing_Status.Query_Error)
}

gpu_test_release :: proc "system" (this: ^d3d11.IUnknown) -> u32 {
	query := (^Gpu_Test_Query)(this)
	query.releases += 1
	return 0
}

gpu_test_create_query :: proc "system" (this: ^d3d11.IDevice, desc: ^d3d11.QUERY_DESC, output: ^^d3d11.IQuery) -> d3d11.HRESULT {
	device := (^Gpu_Test_Device)(this)
	if device.created == len(device.queries) { return -1 }
	query := &device.queries[device.created]
	query.query.id3d11query_vtable = &device.query_vtable
	output^ = &query.query
	device.created += 1
	return 0
}

@(test)
test_gpu_query_creation_failure_releases_each_created_query_once :: proc(t: ^testing.T) {
	vtable := d3d11.IDevice_VTable{CreateQuery = gpu_test_create_query}
	device := Gpu_Test_Device{device = {id3d11device_vtable = &vtable}}
	device.query_vtable.Release = gpu_test_release
	device_context: d3d11.IDeviceContext
	timer: Gpu_Timing_Native
	ok := gpu_timing_native_open(&timer, "unused.csv", 2, &device.device, &device_context, context.allocator)
	testing.expect(t, !ok && !timer.active)
	testing.expect_value(t, timer.created, 3)
	testing.expect_value(t, timer.released, 3)
	testing.expect(t, timer.path == "" && timer.protocol.rows == nil && timer.device_context == nil)
	gpu_timing_native_release(&timer)
	for query in device.queries { testing.expect_value(t, query.releases, 1) }
}
