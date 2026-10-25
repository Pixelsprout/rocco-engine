#+build linux
package engine

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:sys/linux"
import "core:time"

GAMEPAD_INPUT_DIR :: "/dev/input"
// The ioctl numbers from linux/input.h, worked out for x86_64.
EVIOCGBIT_KEY :: 0x80604521
EVIOCGKEY :: 0x80604518
// Add the ABS code to get EVIOCGABS(code).
EVIOCGABS :: 0x80184540
// udev gives a new node its group a moment after the node appears, so an
// open can fail with EACCES until then.
EVDEV_RETRY_TIME :: time.Second
EVDEV_RETRIES_MAX :: 8

Evdev_Device :: struct {
	fd:     linux.Fd,
	// N in /dev/input/eventN.
	number: u32,
	id:     u64,
	pad:    Evdev_Pad,
}

Evdev_Retry :: struct {
	number: u32,
	since:  time.Tick,
}

Gamepad_Backend :: struct {
	devices:     [GAMEPAD_RAW_MAX]Evdev_Device,
	count:       int,
	retries:     [EVDEV_RETRIES_MAX]Evdev_Retry,
	retry_count: int,
	// A zero backend has inotify == 0, which is stdin, so only close it
	// when watching is set.
	watching:    bool,
	inotify:     linux.Fd,
	// The id of the next pad that opens. A node number or an fd can come
	// back for another pad.
	next_id:     u64,
}

gamepad_backend_init :: proc(backend: ^Gamepad_Backend) {
	// Watch before the scan, so that a pad that connects during the scan is
	// not missed.
	fd, err := linux.inotify_init1({.NONBLOCK, .CLOEXEC})
	if err != .NONE {
		fmt.eprintln("gamepad: inotify_init1 failed, so pads that connect later are not seen:", err)
	} else if _, watch_err := linux.inotify_add_watch(fd, GAMEPAD_INPUT_DIR, {.CREATE, .ATTRIB, .MOVED_TO}); watch_err != .NONE {
		if watch_err != .ENOENT {
			fmt.eprintln("gamepad: cannot watch", GAMEPAD_INPUT_DIR, "so pads that connect later are not seen:", watch_err)
		}
		linux.close(fd)
	} else {
		backend.inotify = fd
		backend.watching = true
	}
	evdev_scan(backend)
}

gamepad_backend_poll :: proc(backend: ^Gamepad_Backend, out: []Gamepad_Raw) -> int {
	// Read the pads first. A pad that left frees its node number only after
	// its reads fail, and a new pad can take that number.
	for i := 0; i < backend.count; {
		if evdev_read(&backend.devices[i]) {
			i += 1
		} else {
			evdev_remove(backend, i)
		}
	}
	evdev_watch(backend)
	evdev_retry(backend)
	n := min(backend.count, len(out))
	for i in 0 ..< n {
		device := &backend.devices[i]
		out[i] = evdev_map(device.pad, device.id)
	}
	return n
}

gamepad_backend_shutdown :: proc(backend: ^Gamepad_Backend) {
	for device in backend.devices[:backend.count] {
		linux.close(device.fd)
	}
	if backend.watching {
		linux.close(backend.inotify)
	}
	backend^ = {}
}

// A missing /dev/input, as in a container, means no pads.
@(private = "file")
evdev_scan :: proc(backend: ^Gamepad_Backend) {
	dir, err := linux.open(GAMEPAD_INPUT_DIR, {.DIRECTORY, .CLOEXEC})
	if err != .NONE {
		if err != .ENOENT {
			fmt.eprintln("gamepad: cannot read", GAMEPAD_INPUT_DIR, err)
		}
		return
	}
	defer linux.close(dir)
	buf: [512]u64
	bytes := slice.to_bytes(buf[:])
	for {
		n, read_err := linux.getdents(dir, bytes)
		if read_err != .NONE || n <= 0 {
			return
		}
		offset := 0
		for d in linux.dirent_iterate_buf(bytes[:n], &offset) {
			if number, ok := evdev_node_number(linux.dirent_name(d)); ok {
				evdev_open(backend, number)
			}
		}
	}
}

// Opens /dev/input/eventN and keeps it if it is a gamepad.
@(private = "file")
evdev_open :: proc(backend: ^Gamepad_Backend, number: u32) -> linux.Errno {
	for device in backend.devices[:backend.count] {
		if device.number == number {
			return .NONE
		}
	}
	if backend.count == len(backend.devices) {
		return .NONE
	}
	path_buf: [64]u8
	fd, err := linux.open(evdev_path(path_buf[:], "/dev/input/event%d", number), {.NONBLOCK, .CLOEXEC})
	if err != .NONE {
		return err
	}
	bits: [EVDEV_KEY_BYTES]u8
	if !evdev_ioctl(fd, EVIOCGBIT_KEY, &bits) || !evdev_has_key(bits[:], BTN_GAMEPAD) {
		linux.close(fd)
		return .NONE
	}
	device := Evdev_Device {
		fd     = fd,
		number = number,
		id     = backend.next_id,
		pad    = {xpad = evdev_driver_is_xpad(number)},
	}
	backend.next_id += 1
	evdev_load_state(fd, &device.pad)
	backend.devices[backend.count] = device
	backend.count += 1
	return .NONE
}

// Reads every pending event. Returns false when the pad is gone.
@(private = "file")
evdev_read :: proc(device: ^Evdev_Device) -> bool {
	events: [64]Evdev_Event
	for {
		n, err := linux.read(device.fd, slice.to_bytes(events[:]))
		#partial switch err {
		case .NONE:
		case .EAGAIN:
			return true
		case .EINTR:
			continue
		case:
			// ENODEV when the pad disconnects.
			return false
		}
		count := n / size_of(Evdev_Event)
		evdev_apply(&device.pad, events[:count])
		if device.pad.resync {
			evdev_load_state(device.fd, &device.pad)
			device.pad.resync = false
		}
		if count < len(events) {
			return true
		}
	}
}

// Reads the buttons down now and the axis ranges and values.
@(private = "file")
evdev_load_state :: proc(fd: linux.Fd, pad: ^Evdev_Pad) {
	bits: [EVDEV_KEY_BYTES]u8
	if evdev_ioctl(fd, EVIOCGKEY, &bits) {
		evdev_set_keys(pad, bits[:])
	}
	for code, axis in EVDEV_AXIS_CODES {
		info: Evdev_Absinfo
		if evdev_ioctl(fd, EVIOCGABS + u32(code), &info) {
			pad.axes[axis] = info
		}
	}
}

@(private = "file")
evdev_watch :: proc(backend: ^Gamepad_Backend) {
	if !backend.watching {
		return
	}
	// u32 keeps each linux.Inotify_Event aligned.
	buf: [1024]u32
	bytes := slice.to_bytes(buf[:])
	for {
		n, err := linux.read(backend.inotify, bytes)
		if err == .EINTR {
			continue
		}
		if err != .NONE || n <= 0 {
			return
		}
		offset := 0
		for offset + size_of(linux.Inotify_Event) <= n {
			event := (^linux.Inotify_Event)(&bytes[offset])
			name_start := offset + size_of(linux.Inotify_Event)
			offset = name_start + int(event.len)
			if .Q_OVERFLOW in event.mask {
				evdev_scan(backend)
				continue
			}
			name := strings.truncate_to_byte(string(bytes[name_start:offset]), 0)
			if number, ok := evdev_node_number(name); ok && evdev_open(backend, number) == .EACCES {
				evdev_add_retry(backend, number)
			}
		}
	}
}

@(private = "file")
evdev_add_retry :: proc(backend: ^Gamepad_Backend, number: u32) {
	for r in backend.retries[:backend.retry_count] {
		if r.number == number {
			return
		}
	}
	if backend.retry_count < len(backend.retries) {
		backend.retries[backend.retry_count] = {number, time.tick_now()}
		backend.retry_count += 1
	}
}

@(private = "file")
evdev_retry :: proc(backend: ^Gamepad_Backend) {
	for i := 0; i < backend.retry_count; {
		r := backend.retries[i]
		if evdev_open(backend, r.number) == .EACCES && time.tick_since(r.since) < EVDEV_RETRY_TIME {
			i += 1
			continue
		}
		backend.retry_count -= 1
		backend.retries[i] = backend.retries[backend.retry_count]
	}
}

@(private = "file")
evdev_remove :: proc(backend: ^Gamepad_Backend, i: int) {
	linux.close(backend.devices[i].fd)
	copy(backend.devices[i:backend.count], backend.devices[i + 1:backend.count])
	backend.count -= 1
}

// xpad's driver link ends in .../drivers/xpad.
@(private = "file")
evdev_driver_is_xpad :: proc(number: u32) -> bool {
	path_buf: [96]u8
	path := evdev_path(path_buf[:], "/sys/class/input/event%d/device/device/driver", number)
	link: [256]u8
	n, err := linux.readlink(path, link[:])
	if err != .NONE {
		return false
	}
	target := string(link[:n])
	return target[strings.last_index_byte(target, '/') + 1:] == "xpad"
}

@(private = "file")
evdev_node_number :: proc(name: string) -> (number: u32, ok: bool) {
	digits := strings.trim_prefix(name, "event")
	if len(digits) == len(name) || len(digits) == 0 {
		return 0, false
	}
	for c in transmute([]u8)digits {
		if c < '0' || c > '9' {
			return 0, false
		}
		number = number * 10 + u32(c - '0')
	}
	return number, true
}

@(private = "file")
evdev_path :: proc(buf: []u8, format: string, number: u32) -> cstring {
	s := fmt.bprintf(buf[:len(buf) - 1], format, number)
	buf[len(s)] = 0
	return cstring(raw_data(buf))
}

@(private = "file")
evdev_ioctl :: proc(fd: linux.Fd, request: u32, arg: rawptr) -> bool {
	return int(linux.ioctl(fd, request, uintptr(arg))) >= 0
}
