package engine

// GIP is the USB protocol of wired Xbox One pads. The parser has no OS calls
// and no build tag, so every runner tests it. The layout comes from a PDP
// Afterglow (0e6f:0139), as SDL's SDL_hidapi_xboxone.c and Linux xpad read it.

GIP_INTERFACE_CLASS :: 0xff
GIP_INTERFACE_SUBCLASS :: 0x47
GIP_INTERFACE_PROTOCOL :: 0xd0

GIP_VENDOR_MICROSOFT :: 0x045e
GIP_VENDOR_PDP :: 0x0e6f

GIP_INPUT_REPORT :: 0x20
GIP_INPUT_REPORT_SIZE :: 18
// Option bit 0x10 of byte 1 asks for an ack.
GIP_OPTION_ACK :: 0x10

// The button bits of an input report: byte 4 is the low byte and byte 5 the
// high byte.
GIP_START :: 0x0004
GIP_BACK :: 0x0008
GIP_A :: 0x0010
GIP_B :: 0x0020
GIP_X :: 0x0040
GIP_Y :: 0x0080
GIP_DPAD_UP :: 0x0100
GIP_DPAD_DOWN :: 0x0200
GIP_DPAD_LEFT :: 0x0400
GIP_DPAD_RIGHT :: 0x0800
GIP_LEFT_SHOULDER :: 0x1000
GIP_RIGHT_SHOULDER :: 0x2000
GIP_LEFT_THUMB :: 0x4000
GIP_RIGHT_THUMB :: 0x8000

GIP_TRIGGER_MAX :: 1023

// GameController ids are object addresses, which never set the top bit, so
// a GIP id cannot equal one.
GIP_ID_TAG :: u64(1) << 63

USB_DESCRIPTOR_INTERFACE :: 0x04

@(rodata)
GIP_BUTTON_BITS := [Gamepad_Button]u16 {
	.South          = GIP_A,
	.East           = GIP_B,
	.West           = GIP_X,
	.North          = GIP_Y,
	.Left_Shoulder  = GIP_LEFT_SHOULDER,
	.Right_Shoulder = GIP_RIGHT_SHOULDER,
	.Left_Stick     = GIP_LEFT_THUMB,
	.Right_Stick    = GIP_RIGHT_THUMB,
	.Start          = GIP_START,
	.Back           = GIP_BACK,
	.Dpad_Up        = GIP_DPAD_UP,
	.Dpad_Down      = GIP_DPAD_DOWN,
	.Dpad_Left      = GIP_DPAD_LEFT,
	.Dpad_Right     = GIP_DPAD_RIGHT,
}

// Power on goes to every pad. xpad and SDL also send the PDP LED and auth
// packets to PDP pads. Byte 2 is the sequence number, which the reader fills.
@(rodata)
GIP_START_PACKETS := [?]Gip_Start_Packet {
	{bytes = {0x05, 0x20, 0x00, 0x01, 0x00, 0, 0}, len = 5},
	{bytes = {0x0a, 0x20, 0x00, 0x03, 0x00, 0x01, 0x14}, len = 7},
	{bytes = {0x06, 0x20, 0x00, 0x02, 0x01, 0x00, 0}, len = 6},
}

Gip_Start_Packet :: struct {
	bytes: [7]u8,
	len:   u8,
}

// The last input report of one pad.
Gip_Input :: struct {
	buttons:       u16,
	left_trigger:  u16,
	right_trigger: u16,
	left_stick:    [2]i16,
	right_stick:   [2]i16,
}

Gip_Gamepad :: struct {
	input:   Gip_Input,
	// The buttons that went down since the last gip_poll, so that a tap
	// shorter than one frame still reads as down in one poll.
	latched: u16,
}

// Reads one packet from the pad. Only the input report changes the pad.
gip_apply :: proc(pad: ^Gip_Gamepad, packet: []u8) {
	if len(packet) < GIP_INPUT_REPORT_SIZE || packet[0] != GIP_INPUT_REPORT {
		return
	}
	pad.input = {
		buttons       = gip_u16(packet, 4),
		left_trigger  = gip_u16(packet, 6),
		right_trigger = gip_u16(packet, 8),
		left_stick    = {i16(gip_u16(packet, 10)), i16(gip_u16(packet, 12))},
		right_stick   = {i16(gip_u16(packet, 14)), i16(gip_u16(packet, 16))},
	}
	pad.latched |= pad.input.buttons
}

// GIP reports +y up, as Gamepad_Raw does.
gip_poll :: proc(pad: ^Gip_Gamepad, id: u64) -> Gamepad_Raw {
	input := pad.input
	raw := Gamepad_Raw {
		id   = id,
		axes = {
			left_stick    = {gip_axis(input.left_stick.x), gip_axis(input.left_stick.y)},
			right_stick   = {gip_axis(input.right_stick.x), gip_axis(input.right_stick.y)},
			left_trigger  = gip_trigger(input.left_trigger),
			right_trigger = gip_trigger(input.right_trigger),
		},
	}
	for bit, button in GIP_BUTTON_BITS {
		if (input.buttons | pad.latched) & bit != 0 {
			raw.buttons += {button}
		}
	}
	pad.latched = 0
	return raw
}

gip_pad_id :: proc(registry_id: u64) -> u64 {
	return registry_id | GIP_ID_TAG
}

gip_start_packets :: proc(vendor: u16) -> []Gip_Start_Packet {
	if vendor == GIP_VENDOR_PDP {
		return GIP_START_PACKETS[:]
	}
	return GIP_START_PACKETS[:1]
}

// GIP sequence numbers run from 1 to 255.
gip_next_sequence :: proc(sequence: ^u8) -> u8 {
	sequence^ += 1
	if sequence^ == 0 {
		sequence^ = 1
	}
	return sequence^
}

// The ack names the packet it answers by its command, sequence and length,
// as xpad's mode report ack does.
gip_ack :: proc(packet: []u8) -> (ack: [13]u8, needed: bool) {
	if len(packet) < 4 || packet[1] & GIP_OPTION_ACK == 0 {
		return {}, false
	}
	return {0x01, 0x20, packet[2], 0x09, 0x00, packet[0], 0x20, packet[3], 0, 0, 0, 0, 0}, true
}

// Walks a USB configuration descriptor for an interface with the GIP class,
// subclass and protocol.
gip_config_has_interface :: proc(config: []u8) -> bool {
	for at := 0; at + 2 <= len(config); {
		length := int(config[at])
		if length < 2 || at + length > len(config) {
			return false
		}
		d := config[at:][:length]
		if d[1] == USB_DESCRIPTOR_INTERFACE &&
		   length >= 8 &&
		   d[5] == GIP_INTERFACE_CLASS &&
		   d[6] == GIP_INTERFACE_SUBCLASS &&
		   d[7] == GIP_INTERFACE_PROTOCOL {
			return true
		}
		at += length
	}
	return false
}

@(private = "file")
gip_u16 :: proc(packet: []u8, offset: int) -> u16 {
	return u16(packet[offset]) | u16(packet[offset + 1]) << 8
}

@(private = "file")
gip_axis :: proc(value: i16) -> f32 {
	return max(f32(value) / 32767, -1)
}

@(private = "file")
gip_trigger :: proc(value: u16) -> f32 {
	return f32(min(value, GIP_TRIGGER_MAX)) / GIP_TRIGGER_MAX
}
