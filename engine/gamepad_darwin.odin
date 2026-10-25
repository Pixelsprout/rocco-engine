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
Gamepad_Reader :: struct {
	controller_class: NS.Class,
}

// dlerror is not in the macOS catalog, so the log gives no reason.
gamepad_reader_init :: proc(reader: ^Gamepad_Reader) {
	if posix.dlopen(GC_FRAMEWORK, posix.RTLD_LOCAL + {.LAZY}) == nil {
		fmt.eprintln("the GameController framework did not load. The run reads no gamepads.")
		return
	}
	reader.controller_class = NS.objc_lookUpClass("GCController")
	if reader.controller_class == nil {
		fmt.eprintln("GameController has no GCController class. The run reads no gamepads.")
	}
}

// The list can stay empty for the first frames, because AppKit connects the
// pads on the main run loop.
gamepad_reader_poll :: proc(reader: ^Gamepad_Reader, out: []Gamepad_Raw) -> int {
	if reader.controller_class == nil {
		return 0
	}
	NS.scoped_autoreleasepool()
	controllers := intrinsics.objc_send(^NS.Array, (^Gc_Controller)(reader.controller_class), "controllers")
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
// reader does not dlclose GameController.
gamepad_reader_shutdown :: proc(reader: ^Gamepad_Reader) {
	reader^ = {}
}

@(private = "file")
gc_read :: proc(pad: ^Gc_Extended_Gamepad) -> Gc_Snapshot {
	dpad := intrinsics.objc_send(^Gc_Direction_Pad, pad, "dpad")
	return {
		pressed = {
			.Button_A = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonA")),
			.Button_B = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonB")),
			.Button_X = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonX")),
			.Button_Y = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonY")),
			.Left_Shoulder = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "leftShoulder")),
			.Right_Shoulder = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "rightShoulder")),
			.Left_Thumbstick_Button = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "leftThumbstickButton")),
			.Right_Thumbstick_Button = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "rightThumbstickButton")),
			.Button_Menu = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonMenu")),
			.Button_Options = gc_pressed(intrinsics.objc_send(^Gc_Button, pad, "buttonOptions")),
			.Dpad_Up = gc_pressed(intrinsics.objc_send(^Gc_Button, dpad, "up")),
			.Dpad_Down = gc_pressed(intrinsics.objc_send(^Gc_Button, dpad, "down")),
			.Dpad_Left = gc_pressed(intrinsics.objc_send(^Gc_Button, dpad, "left")),
			.Dpad_Right = gc_pressed(intrinsics.objc_send(^Gc_Button, dpad, "right")),
		},
		left_thumbstick =gc_stick(intrinsics.objc_send(^Gc_Direction_Pad, pad, "leftThumbstick")),
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
