#+build darwin
package engine

import "base:runtime"
import "core:fmt"
import "core:sys/posix"
import "core:time"

IOKIT_FRAMEWORK :: "/System/Library/Frameworks/IOKit.framework/IOKit"
CORE_FOUNDATION_FRAMEWORK :: "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"

// The Windows and Linux readers also look for a new pad once a second.
GIP_SCAN_INTERVAL :: time.Second
// A pad gives a new client the reports that the last client did not read.
// They arrive within a few frames of the open, so the reader lists the pad
// after them.
GIP_SETTLE_TIME :: 100 * time.Millisecond
// Reads queued on each pad, so that the reports of one frame do not wait
// for the next frame.
GIP_READS_IN_FLIGHT :: 4
GIP_READ_SIZE :: 64
// USB devices that are not pads, or pads that failed to start. A device
// that is unplugged leaves the list at the next scan.
GIP_SKIPPED_MAX :: 64
// The completions that one poll takes from the run loop.
GIP_COMPLETIONS_MAX :: 64
// The run loop runs only the GIP reads in this mode, and only inside a
// poll.
GIP_RUN_LOOP_MODE :: "dev.pixelsprout.rocco.gip"

KIO_RETURN_SUCCESS :: 0
KIO_RETURN_NO_DEVICE :: i32(-536870208) // 0xe00002c0
KIO_RETURN_OFFLINE :: i32(-536870185) // 0xe00002d7
KIO_RETURN_ABORTED :: i32(-536870165) // 0xe00002eb
KIO_RETURN_NOT_RESPONDING :: i32(-536870163) // 0xe00002ed
KIO_USB_FIND_INTERFACE_DONT_CARE :: 0xffff
KUSB_IN :: 1
KUSB_OUT :: 0
KUSB_INTERRUPT :: 3
KCF_STRING_ENCODING_UTF8 :: 0x0800_0100
KCF_RUN_LOOP_RUN_HANDLED_SOURCE :: 4

// The UUIDs from IOCFPlugIn.h and IOUSBLib.h.
KIO_CF_PLUGIN_INTERFACE_ID :: Cf_Uuid_Bytes{0xc2, 0x44, 0xe8, 0x58, 0x10, 0x9c, 0x11, 0xd4, 0x91, 0xd4, 0x00, 0x50, 0xe4, 0xc6, 0x42, 0x6f}
KIO_USB_DEVICE_USER_CLIENT_TYPE_ID :: Cf_Uuid_Bytes{0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xd4, 0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61}
KIO_USB_INTERFACE_USER_CLIENT_TYPE_ID :: Cf_Uuid_Bytes{0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xd4, 0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61}
KIO_USB_DEVICE_INTERFACE_ID :: Cf_Uuid_Bytes{0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xd4, 0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61}
KIO_USB_INTERFACE_INTERFACE_ID :: Cf_Uuid_Bytes{0x73, 0xc9, 0x7a, 0xe8, 0x9e, 0xf3, 0x11, 0xd4, 0xb1, 0xd0, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61}

// CFUUIDBytes, which QueryInterface takes by value.
Cf_Uuid_Bytes :: [16]u8

Cf_Uuid_Bytes_Arg :: struct {
	bytes: Cf_Uuid_Bytes,
}

Iokit_Async_Callback :: #type proc "c" (refcon: rawptr, result: i32, arg0: rawptr)

// IOCFPlugInInterface: IUNKNOWN_C_GUTS, then IOCFPLUGINBASE.
Iokit_Plugin :: struct {
	_reserved:       rawptr,
	query_interface: proc "c" (self: rawptr, iid: Cf_Uuid_Bytes_Arg, out: ^rawptr) -> i32,
	add_ref:         proc "c" (self: rawptr) -> u32,
	release:         proc "c" (self: rawptr) -> u32,
	version:         u16,
	revision:        u16,
	probe:           rawptr,
	start:           rawptr,
	stop:            rawptr,
}

// IOUSBDeviceInterface (IOUSBDeviceStruct100). The reader calls only the
// typed entries.
Iousb_Device :: struct {
	_reserved:                        rawptr,
	query_interface:                  rawptr,
	add_ref:                          rawptr,
	release:                          proc "c" (self: rawptr) -> u32,
	create_device_async_event_source: rawptr,
	get_device_async_event_source:    rawptr,
	create_device_async_port:         rawptr,
	get_device_async_port:            rawptr,
	usb_device_open:                  proc "c" (self: rawptr) -> i32,
	usb_device_close:                 proc "c" (self: rawptr) -> i32,
	get_device_class:                 rawptr,
	get_device_sub_class:             rawptr,
	get_device_protocol:              rawptr,
	get_device_vendor:                proc "c" (self: rawptr, vendor: ^u16) -> i32,
	get_device_product:               proc "c" (self: rawptr, product: ^u16) -> i32,
	get_device_release_number:        rawptr,
	get_device_address:               rawptr,
	get_device_bus_power_available:   rawptr,
	get_device_speed:                 rawptr,
	get_number_of_configurations:     rawptr,
	get_location_id:                  rawptr,
	// The device need not be open. The descriptor stays owned by the device.
	get_configuration_descriptor_ptr: proc "c" (self: rawptr, index: u8, desc: ^[^]u8) -> i32,
	get_configuration:                proc "c" (self: rawptr, value: ^u8) -> i32,
	set_configuration:                proc "c" (self: rawptr, value: u8) -> i32,
	get_bus_frame_number:             rawptr,
	reset_device:                     rawptr,
	device_request:                   rawptr,
	device_request_async:             rawptr,
	create_interface_iterator:        proc "c" (self: rawptr, request: ^Iousb_Find_Interface_Request, iterator: ^u32) -> i32,
}

// IOUSBInterfaceInterface (IOUSBInterfaceStruct100), up to ReadPipeAsync.
Iousb_Interface :: struct {
	_reserved:                           rawptr,
	query_interface:                     rawptr,
	add_ref:                             rawptr,
	release:                             proc "c" (self: rawptr) -> u32,
	create_interface_async_event_source: proc "c" (self: rawptr, source: ^rawptr) -> i32,
	get_interface_async_event_source:    rawptr,
	create_interface_async_port:         rawptr,
	get_interface_async_port:            rawptr,
	usb_interface_open:                  proc "c" (self: rawptr) -> i32,
	usb_interface_close:                 proc "c" (self: rawptr) -> i32,
	get_interface_class:                 rawptr,
	get_interface_sub_class:             rawptr,
	get_interface_protocol:              rawptr,
	get_device_vendor:                   rawptr,
	get_device_product:                  rawptr,
	get_device_release_number:           rawptr,
	get_configuration_value:             rawptr,
	get_interface_number:                rawptr,
	get_alternate_setting:               rawptr,
	get_num_endpoints:                   proc "c" (self: rawptr, count: ^u8) -> i32,
	get_location_id:                     rawptr,
	get_device:                          rawptr,
	set_alternate_interface:             rawptr,
	get_bus_frame_number:                rawptr,
	control_request:                     rawptr,
	control_request_async:               rawptr,
	get_pipe_properties:                 proc "c" (self: rawptr, pipe: u8, direction: ^u8, number: ^u8, transfer_type: ^u8, max_packet_size: ^u16, interval: ^u8) -> i32,
	get_pipe_status:                     rawptr,
	abort_pipe:                          rawptr,
	reset_pipe:                          rawptr,
	clear_pipe_stall:                    rawptr,
	read_pipe:                           rawptr,
	write_pipe:                          proc "c" (self: rawptr, pipe: u8, buf: rawptr, size: u32) -> i32,
	read_pipe_async:                     proc "c" (self: rawptr, pipe: u8, buf: rawptr, size: u32, callback: Iokit_Async_Callback, refcon: rawptr) -> i32,
}

Iousb_Find_Interface_Request :: struct {
	class:             u16,
	sub_class:         u16,
	protocol:          u16,
	alternate_setting: u16,
}

// The IOKit and CoreFoundation calls, from dlsym, so the macOS catalog
// needs no entry for them.
Gip_Api :: struct {
	io_service_matching:                      proc "c" (name: cstring) -> rawptr,
	io_service_get_matching_services:         proc "c" (main_port: u32, matching: rawptr, iterator: ^u32) -> i32,
	io_iterator_next:                         proc "c" (iterator: u32) -> u32,
	io_object_release:                        proc "c" (object: u32) -> i32,
	io_registry_entry_get_registry_entry_id:  proc "c" (entry: u32, id: ^u64) -> i32,
	io_create_plug_in_interface_for_service:  proc "c" (service: u32, plugin_type: rawptr, interface_type: rawptr, plugin: ^^^Iokit_Plugin, score: ^i32) -> i32,
	cf_uuid_get_constant_uuid_with_bytes:     proc "c" (allocator: rawptr, b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15: u8) -> rawptr,
	cf_run_loop_get_current:                  proc "c" () -> rawptr,
	cf_run_loop_add_source:                   proc "c" (run_loop: rawptr, source: rawptr, mode: rawptr),
	cf_run_loop_remove_source:                proc "c" (run_loop: rawptr, source: rawptr, mode: rawptr),
	cf_run_loop_run_in_mode:                  proc "c" (mode: rawptr, seconds: f64, return_after_source_handled: b8) -> i32,
	cf_string_create_with_c_string:           proc "c" (allocator: rawptr, text: cstring, encoding: u32) -> rawptr,
	cf_release:                               proc "c" (object: rawptr),
}

// One queued read. The callback finds its pad through it.
Gip_Read :: struct {
	pad:    ^Gip_Pad,
	buffer: [GIP_READ_SIZE]u8,
}

// A pad keeps its place in Gip_Reader.pads while it is open, because the
// queued reads point at it.
Gip_Pad :: struct {
	open:        bool,
	registry_id: u64,
	vendor:      u16,
	product:     u16,
	device:      ^^Iousb_Device,
	device_open: bool,
	interface:   ^^Iousb_Interface,
	source:      rawptr,
	pipe_in:     u8,
	pipe_out:    u8,
	sequence:    u8,
	// Set by a read that failed. The next poll closes the pad.
	error:       i32,
	// The packets read since the pad opened.
	packets:     u64,
	opened:      time.Tick,
	state:       Gip_Gamepad,
	reads:       [GIP_READS_IN_FLIGHT]Gip_Read,
}

// Reads wired Xbox One pads, which macOS has no driver for. It skips
// Microsoft pads, which GameController reads.
Gip_Reader :: struct {
	api:            Gip_Api,
	loaded:         bool,
	run_loop:       rawptr,
	mode:           rawptr,
	device_type:    rawptr,
	interface_type: rawptr,
	plugin_type:    rawptr,
	pads:           [GAMEPAD_RAW_MAX]Gip_Pad,
	skipped:        [GIP_SKIPPED_MAX]u64,
	skipped_count:  int,
	next_scan:      time.Tick,
}

// dlerror is not in the macOS catalog, so the log gives no reason.
gip_reader_init :: proc(reader: ^Gip_Reader) {
	reader^ = {}
	iokit := posix.dlopen(IOKIT_FRAMEWORK, posix.RTLD_LOCAL + {.LAZY})
	cf := posix.dlopen(CORE_FOUNDATION_FRAMEWORK, posix.RTLD_LOCAL + {.LAZY})
	if iokit == nil || cf == nil {
		fmt.eprintln("IOKit did not load. The run reads no wired Xbox One pads.")
		return
	}
	api := &reader.api
	ok := true
	ok &= gip_symbol(iokit, "IOServiceMatching", &api.io_service_matching)
	ok &= gip_symbol(iokit, "IOServiceGetMatchingServices", &api.io_service_get_matching_services)
	ok &= gip_symbol(iokit, "IOIteratorNext", &api.io_iterator_next)
	ok &= gip_symbol(iokit, "IOObjectRelease", &api.io_object_release)
	ok &= gip_symbol(iokit, "IORegistryEntryGetRegistryEntryID", &api.io_registry_entry_get_registry_entry_id)
	ok &= gip_symbol(iokit, "IOCreatePlugInInterfaceForService", &api.io_create_plug_in_interface_for_service)
	ok &= gip_symbol(cf, "CFUUIDGetConstantUUIDWithBytes", &api.cf_uuid_get_constant_uuid_with_bytes)
	ok &= gip_symbol(cf, "CFRunLoopGetCurrent", &api.cf_run_loop_get_current)
	ok &= gip_symbol(cf, "CFRunLoopAddSource", &api.cf_run_loop_add_source)
	ok &= gip_symbol(cf, "CFRunLoopRemoveSource", &api.cf_run_loop_remove_source)
	ok &= gip_symbol(cf, "CFRunLoopRunInMode", &api.cf_run_loop_run_in_mode)
	ok &= gip_symbol(cf, "CFStringCreateWithCString", &api.cf_string_create_with_c_string)
	ok &= gip_symbol(cf, "CFRelease", &api.cf_release)
	if !ok {
		fmt.eprintln("IOKit lacks a USB call. The run reads no wired Xbox One pads.")
		return
	}
	reader.device_type = gip_uuid(api, KIO_USB_DEVICE_USER_CLIENT_TYPE_ID)
	reader.interface_type = gip_uuid(api, KIO_USB_INTERFACE_USER_CLIENT_TYPE_ID)
	reader.plugin_type = gip_uuid(api, KIO_CF_PLUGIN_INTERFACE_ID)
	reader.mode = api.cf_string_create_with_c_string(nil, GIP_RUN_LOOP_MODE, KCF_STRING_ENCODING_UTF8)
	reader.run_loop = api.cf_run_loop_get_current()
	reader.loaded = reader.mode != nil && reader.run_loop != nil
}

gip_reader_poll :: proc(reader: ^Gip_Reader, out: []Gamepad_Raw) -> int {
	if !reader.loaded {
		return 0
	}
	api := &reader.api
	for _ in 0 ..< GIP_COMPLETIONS_MAX {
		if api.cf_run_loop_run_in_mode(reader.mode, 0, true) != KCF_RUN_LOOP_RUN_HANDLED_SOURCE {
			break
		}
	}
	for &pad in reader.pads {
		if pad.open && pad.error != KIO_RETURN_SUCCESS {
			if !gip_error_is_unplug(pad.error) {
				gip_log(&pad, "read", pad.error)
			}
			gip_skip(reader, pad.registry_id)
			gip_close(reader, &pad)
		}
	}
	now := time.tick_now()
	if time.tick_diff(reader.next_scan, now) >= 0 {
		reader.next_scan = time.tick_add(now, GIP_SCAN_INTERVAL)
		gip_scan(reader)
	}
	n := 0
	for &pad in reader.pads {
		if pad.open && n < len(out) && time.tick_diff(pad.opened, now) >= GIP_SETTLE_TIME {
			out[n] = gip_poll(&pad.state, gip_pad_id(pad.registry_id))
			n += 1
		}
	}
	return n
}

gip_reader_shutdown :: proc(reader: ^Gip_Reader) {
	if reader.loaded {
		for &pad in reader.pads {
			if pad.open {
				gip_close(reader, &pad)
			}
		}
		reader.api.cf_release(reader.mode)
	}
	reader^ = {}
}

@(private = "file")
gip_symbol :: proc(lib: posix.Symbol_Table, name: cstring, out: ^$T) -> bool {
	symbol := posix.dlsym(lib, name)
	(^rawptr)(out)^ = symbol
	return symbol != nil
}

@(private = "file")
gip_uuid :: proc(api: ^Gip_Api, b: Cf_Uuid_Bytes) -> rawptr {
	return api.cf_uuid_get_constant_uuid_with_bytes(
		nil,
		b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
		b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15],
	)
}

// Opens the new USB devices, and closes the pads that are gone.
@(private = "file")
gip_scan :: proc(reader: ^Gip_Reader) {
	api := &reader.api
	iterator: u32
	if api.io_service_get_matching_services(0, api.io_service_matching("IOUSBHostDevice"), &iterator) != KIO_RETURN_SUCCESS {
		return
	}
	present: [GIP_SKIPPED_MAX + GAMEPAD_RAW_MAX]u64
	present_count := 0
	complete := true
	for service := api.io_iterator_next(iterator); service != 0; service = api.io_iterator_next(iterator) {
		id: u64
		if api.io_registry_entry_get_registry_entry_id(service, &id) == KIO_RETURN_SUCCESS {
			if present_count < len(present) {
				present[present_count] = id
				present_count += 1
			} else {
				complete = false
			}
			if !gip_known(reader, id) {
				gip_open(reader, service, id)
			}
		}
		api.io_object_release(service)
	}
	api.io_object_release(iterator)
	// A device past the end of present may be an open pad, so it is not gone.
	if !complete {
		return
	}
	still := present[:present_count]
	for &pad in reader.pads {
		if pad.open && !gip_ids_have(still, pad.registry_id) {
			gip_close(reader, &pad)
		}
	}
	kept := 0
	for id in reader.skipped[:reader.skipped_count] {
		if gip_ids_have(still, id) {
			reader.skipped[kept] = id
			kept += 1
		}
	}
	reader.skipped_count = kept
}

@(private = "file")
gip_known :: proc(reader: ^Gip_Reader, id: u64) -> bool {
	for pad in reader.pads {
		if pad.open && pad.registry_id == id {
			return true
		}
	}
	return gip_ids_have(reader.skipped[:reader.skipped_count], id)
}

@(private = "file")
gip_ids_have :: proc(ids: []u64, id: u64) -> bool {
	for have in ids {
		if have == id {
			return true
		}
	}
	return false
}

// A full list only means that the device is checked again at the next scan.
@(private = "file")
gip_skip :: proc(reader: ^Gip_Reader, id: u64) {
	if reader.skipped_count < GIP_SKIPPED_MAX && !gip_ids_have(reader.skipped[:reader.skipped_count], id) {
		reader.skipped[reader.skipped_count] = id
		reader.skipped_count += 1
	}
}

// Checks one new USB device. A device that is not a GIP pad, and a pad that
// fails to open, configure or start, is skipped until it reconnects.
@(private = "file")
gip_open :: proc(reader: ^Gip_Reader, service: u32, registry_id: u64) {
	slot: ^Gip_Pad
	for &pad in reader.pads {
		if !pad.open {
			slot = &pad
			break
		}
	}
	if slot == nil {
		return
	}
	device := (^^Iousb_Device)(gip_query(reader, service, reader.device_type, KIO_USB_DEVICE_INTERFACE_ID))
	if device == nil {
		gip_skip(reader, registry_id)
		return
	}
	pad := Gip_Pad {
		registry_id = registry_id,
		device      = device,
	}
	device^.get_device_vendor(device, &pad.vendor)
	device^.get_device_product(device, &pad.product)
	config: [^]u8
	is_pad :=
		pad.vendor != GIP_VENDOR_MICROSOFT &&
		device^.get_configuration_descriptor_ptr(device, 0, &config) == KIO_RETURN_SUCCESS &&
		config != nil &&
		gip_config_has_interface(config[:u16(config[2]) | u16(config[3]) << 8])
	if !is_pad {
		device^.release(device)
		gip_skip(reader, registry_id)
		return
	}
	slot^ = pad
	if !gip_start(reader, slot, config[5]) {
		gip_close(reader, slot)
		gip_skip(reader, registry_id)
		return
	}
	slot.open = true
	slot.opened = time.tick_now()
}

// Logs the step that failed.
@(private = "file")
gip_start :: proc(reader: ^Gip_Reader, pad: ^Gip_Pad, configuration: u8) -> bool {
	api := &reader.api
	device := pad.device
	// Another client can hold the device open. A device that is already
	// configured still lets the reader open its interface.
	pad.device_open = device^.usb_device_open(device) == KIO_RETURN_SUCCESS
	current: u8
	device^.get_configuration(device, &current)
	if current == 0 {
		if !pad.device_open {
			gip_log(pad, "open", 0)
			return false
		}
		if result := device^.set_configuration(device, configuration); result != KIO_RETURN_SUCCESS {
			gip_log(pad, "configure", result)
			return false
		}
	}
	if !gip_open_interface(reader, pad) {
		gip_log(pad, "open its GIP interface", 0)
		return false
	}
	intf := pad.interface
	if result := intf^.create_interface_async_event_source(intf, &pad.source); result != KIO_RETURN_SUCCESS {
		gip_log(pad, "start", result)
		return false
	}
	api.cf_run_loop_add_source(reader.run_loop, pad.source, reader.mode)
	for packet in gip_start_packets(pad.vendor) {
		bytes := packet.bytes
		bytes[2] = gip_next_sequence(&pad.sequence)
		if result := intf^.write_pipe(intf, pad.pipe_out, &bytes, u32(packet.len)); result != KIO_RETURN_SUCCESS {
			gip_log(pad, "start", result)
			return false
		}
	}
	for &read in pad.reads {
		read.pad = pad
		if result := gip_read(pad, &read); result != KIO_RETURN_SUCCESS {
			gip_log(pad, "start", result)
			return false
		}
	}
	return true
}

// Opens the first GIP interface that has an interrupt pipe each way. The
// second GIP interface of a PDP pad has no interrupt pipes.
@(private = "file")
gip_open_interface :: proc(reader: ^Gip_Reader, pad: ^Gip_Pad) -> bool {
	api := &reader.api
	request := Iousb_Find_Interface_Request {
		class             = GIP_INTERFACE_CLASS,
		sub_class         = GIP_INTERFACE_SUBCLASS,
		protocol          = GIP_INTERFACE_PROTOCOL,
		alternate_setting = KIO_USB_FIND_INTERFACE_DONT_CARE,
	}
	iterator: u32
	if pad.device^.create_interface_iterator(pad.device, &request, &iterator) != KIO_RETURN_SUCCESS {
		return false
	}
	defer api.io_object_release(iterator)
	for service := api.io_iterator_next(iterator); service != 0; service = api.io_iterator_next(iterator) {
		intf := (^^Iousb_Interface)(gip_query(reader, service, reader.interface_type, KIO_USB_INTERFACE_INTERFACE_ID))
		api.io_object_release(service)
		if intf == nil {
			continue
		}
		if intf^.usb_interface_open(intf) != KIO_RETURN_SUCCESS {
			intf^.release(intf)
			continue
		}
		pipe_in, pipe_out: u8
		endpoints: u8
		intf^.get_num_endpoints(intf, &endpoints)
		for pipe in 1 ..= endpoints {
			direction, number, transfer_type, interval: u8
			max_packet_size: u16
			if intf^.get_pipe_properties(intf, pipe, &direction, &number, &transfer_type, &max_packet_size, &interval) != KIO_RETURN_SUCCESS {
				continue
			}
			if transfer_type == KUSB_INTERRUPT && direction == KUSB_IN && pipe_in == 0 {
				pipe_in = pipe
			} else if transfer_type == KUSB_INTERRUPT && direction == KUSB_OUT && pipe_out == 0 {
				pipe_out = pipe
			}
		}
		if pipe_in != 0 && pipe_out != 0 {
			pad.interface = intf
			pad.pipe_in = pipe_in
			pad.pipe_out = pipe_out
			return true
		}
		intf^.usb_interface_close(intf)
		intf^.release(intf)
	}
	return false
}

// Makes the IOCFPlugIn for a service, then asks it for one interface.
@(private = "file")
gip_query :: proc(reader: ^Gip_Reader, service: u32, client_type: rawptr, interface_id: Cf_Uuid_Bytes) -> rawptr {
	plugin: ^^Iokit_Plugin
	score: i32
	if reader.api.io_create_plug_in_interface_for_service(service, client_type, reader.plugin_type, &plugin, &score) != KIO_RETURN_SUCCESS || plugin == nil {
		return nil
	}
	out: rawptr
	result := plugin^.query_interface(plugin, {interface_id}, &out)
	plugin^.release(plugin)
	if result != KIO_RETURN_SUCCESS {
		return nil
	}
	return out
}

@(private = "file")
gip_read :: proc(pad: ^Gip_Pad, read: ^Gip_Read) -> i32 {
	return pad.interface^.read_pipe_async(pad.interface, pad.pipe_in, &read.buffer, GIP_READ_SIZE, gip_read_done, read)
}

// The run loop calls this only inside the CFRunLoopRunInMode of a poll, on
// the thread that polls.
@(private = "file")
gip_read_done :: proc "c" (refcon: rawptr, result: i32, arg0: rawptr) {
	context = runtime.default_context()
	read := (^Gip_Read)(refcon)
	pad := read.pad
	if result != KIO_RETURN_SUCCESS {
		if pad.error == KIO_RETURN_SUCCESS {
			pad.error = result
		}
		return
	}
	packet := read.buffer[:min(int(uintptr(arg0)), GIP_READ_SIZE)]
	pad.packets += 1
	gip_apply(&pad.state, packet)
	if ack, needed := gip_ack(packet); needed {
		pad.interface^.write_pipe(pad.interface, pad.pipe_out, &ack, len(ack))
	}
	if again := gip_read(pad, read); again != KIO_RETURN_SUCCESS && pad.error == KIO_RETURN_SUCCESS {
		pad.error = again
	}
}

// Removing the source first means that no read of this pad completes after
// the close.
@(private = "file")
gip_close :: proc(reader: ^Gip_Reader, pad: ^Gip_Pad) {
	api := &reader.api
	if pad.source != nil {
		api.cf_run_loop_remove_source(reader.run_loop, pad.source, reader.mode)
		api.cf_release(pad.source)
	}
	if pad.interface != nil {
		pad.interface^.usb_interface_close(pad.interface)
		pad.interface^.release(pad.interface)
	}
	if pad.device != nil {
		if pad.device_open {
			pad.device^.usb_device_close(pad.device)
		}
		pad.device^.release(pad.device)
	}
	pad^ = {}
}

@(private = "file")
gip_error_is_unplug :: proc(result: i32) -> bool {
	switch result {
	case KIO_RETURN_NO_DEVICE, KIO_RETURN_OFFLINE, KIO_RETURN_ABORTED, KIO_RETURN_NOT_RESPONDING:
		return true
	}
	return false
}

// A result of 0 means that the step found nothing to use, such as no GIP
// interface with two interrupt pipes.
@(private = "file")
gip_log :: proc(pad: ^Gip_Pad, step: string, result: i32) {
	if result == KIO_RETURN_SUCCESS {
		fmt.eprintfln("the gamepad %04x:%04x did not %v. The run skips it until it reconnects.", pad.vendor, pad.product, step)
		return
	}
	fmt.eprintfln(
		"the gamepad %04x:%04x did not %v (IOReturn 0x%08x). The run skips it until it reconnects.",
		pad.vendor,
		pad.product,
		step,
		u32(result),
	)
}
