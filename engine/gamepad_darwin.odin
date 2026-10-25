#+build darwin
package engine

import "base:intrinsics"
import "core:fmt"
import NS "core:sys/darwin/Foundation"
import "core:sys/posix"

GC_FRAMEWORK :: "/System/Library/Frameworks/GameController.framework/GameController"

// Odin looks up a named class once, before main and so before the dlopen.
// Never send to these types as class receivers: that lookup stays nil.
// Send class messages to the Class that objc_lookUpClass gives after the
// dlopen.
@(objc_class = "GCController")
Gc_Controller :: struct {
	using _: NS.Object,
}

@(objc_class = "GCExtendedGamepad")
Gc_Extended_Gamepad :: struct {
	using _: NS.Object,
}

@(objc_class = "GCControllerButtonInput")
Gc_Button :: struct {
	using _: NS.Object,
}

@(objc_class = "GCControllerDirectionPad")
Gc_Direction_Pad :: struct {
	using _: NS.Object,
}

@(objc_class = "GCControllerAxisInput")
Gc_Axis :: struct {
	using _: NS.Object,
}

// The GCController class. It is nil when GameController did not load, and
// then each poll reports no pads.
Gamepad_Backend :: struct {
	controller_class: NS.Class,
}

// dlerror is not in the macOS catalog, so the log gives no reason.
gamepad_backend_init :: proc(backend: ^Gamepad_Backend) {
	if posix.dlopen(GC_FRAMEWORK, posix.RTLD_LOCAL + {.LAZY}) == nil {
		fmt.eprintln("rocco: GameController did not load, so no gamepads are read")
		return
	}
	backend.controller_class = NS.objc_lookUpClass("GCController")
	if backend.controller_class == nil {
		fmt.eprintln("rocco: GameController has no GCController class, so no gamepads are read")
	}
}

// The list can stay empty for the first frames, because AppKit connects the
// pads on the main run loop.
gamepad_backend_poll :: proc(backend: ^Gamepad_Backend, out: []Gamepad_Raw) -> int {
	if backend.controller_class == nil {
		return 0
	}
	NS.scoped_autoreleasepool()
	controllers := intrinsics.objc_send(^NS.Array, (^Gc_Controller)(backend.controller_class), "controllers")
	if controllers == nil {
		return 0
	}
	n := 0
	for i in 0 ..< controllers->count() {
		if n == len(out) {
			break
		}
		controller := (^Gc_Controller)(controllers->object(i))
		pad := intrinsics.objc_send(^Gc_Extended_Gamepad, controller, "extendedGamepad")
		if pad == nil {
			continue
		}
		// The controllers array keeps the object alive while the pad is
		// connected, so its address stays the same.
		out[n] = gc_map(gc_read(pad), u64(uintptr(controller)))
		n += 1
	}
	return n
}

// dyld does not unload an image that holds Objective-C classes, so the
// backend does not dlclose GameController.
gamepad_backend_shutdown :: proc(backend: ^Gamepad_Backend) {
	backend^ = {}
}

@(private = "file")
gc_read :: proc(pad: ^Gc_Extended_Gamepad) -> Gc_Snapshot {
	dpad := intrinsics.objc_send(^Gc_Direction_Pad, pad, "dpad")
	return {
		button_a = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonA")),
		button_b = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonB")),
		button_x = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonX")),
		button_y = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonY")),
		left_shoulder = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "leftShoulder")),
		right_shoulder = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "rightShoulder")),
		left_thumbstick_button = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "leftThumbstickButton")),
		right_thumbstick_button = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "rightThumbstickButton")),
		button_menu = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonMenu")),
		button_options = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonOptions")),
		dpad_up = gc_pressed(intrinsics.objc_send(^Gc_Button, dpad, "up")),
		dpad_down = gc_pressed(intrinsics.objc_send(^Gc_Button, dpad, "down")),
		dpad_left = gc_pressed(intrinsics.objc_send(^Gc_Button, dpad, "left")),
		dpad_right = gc_pressed(intrinsics.objc_send(^Gc_Button, dpad, "right")),
		left_thumbstick = gc_stick(intrinsics.objc_send(^Gc_Direction_Pad, pad, "leftThumbstick")),
		right_thumbstick = gc_stick(intrinsics.objc_send(^Gc_Direction_Pad, pad, "rightThumbstick")),
		left_trigger = gc_value(intrinsics.objc_send(^Gc_Button, pad, "leftTrigger")),
		right_trigger = gc_value(intrinsics.objc_send(^Gc_Button, pad, "rightTrigger")),
	}
}

// Some pads have no buttonOptions or thumbstick buttons, and then the
// selector gives nil.
@(private = "file")
gc_pressed :: proc(button: ^Gc_Button) -> bool {
	if button == nil {
		return false
	}
	return intrinsics.objc_send(NS.BOOL, button, "isPressed")
}

@(private = "file")
gc_value :: proc(button: ^Gc_Button) -> f32 {
	if button == nil {
		return 0
	}
	return intrinsics.objc_send(f32, button, "value")
}

@(private = "file")
gc_stick :: proc(stick: ^Gc_Direction_Pad) -> [2]f32 {
	if stick == nil {
		return {}
	}
	x := intrinsics.objc_send(^Gc_Axis, stick, "xAxis")
	y := intrinsics.objc_send(^Gc_Axis, stick, "yAxis")
	return {intrinsics.objc_send(f32, x, "value"), intrinsics.objc_send(f32, y, "value")}
}
