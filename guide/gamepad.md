---
title: Gamepads
summary: Buttons named by their place on the pad, sticks and triggers with the dead zone applied, slots for more than one player, the limits on each OS, and gamepads through the Bridge.
order: 7
---

# Gamepads

A gamepad is harder to read than a keyboard. The bottom face button is A on
an Xbox pad, Cross on a PlayStation pad and B on a Switch pad, and each OS
has its own way to read them. A stick at rest does not read exactly 0: it
wobbles a little around its centre, and an old pad drifts. Pads connect and
disconnect while the game runs, and two players can each hold one.

rocco takes care of these things in the host, so your game sees one simple
value. The [Input] that `step` gets has a list, `gamepads`, with one
[Gamepad] for each connected pad. The host:

- names each button by its place on the pad, not by its label, so `South`
  is the bottom face button on every pad,
- reads the pad through the OS, so you link nothing and install nothing,
- ignores the wobble of a stick near its centre, so a stick at rest is 0,
- gives each pad a slot, which stays the same while the pad stays
  connected.

As with keys, the host never decides what a button means. That is up to
your game.

[Tutorial chapter 9](tutorial/09-gamepad.md) walks Pip with the left stick
and quits with Start.

## Read the buttons

Use the [Button] module to read the buttons. It has the same two answers as
`Key`: held, while a button is down, and pressed, in the first step after
it went down.

- [`Button.held_any`][Button.held_any] and
  [`Button.pressed_any`][Button.pressed_any] ask every connected pad. Use
  them in a game for one player.
- [`Button.held`][Button.held] and [`Button.pressed`][Button.pressed] ask
  one Gamepad. Use them when it matters which pad it was.

Tutorial chapter 9 quits on Escape or on Start from any pad:

<!-- region: examples/tutorial/09-gamepad/main.roc#quit -->
```roc
# Escape on the keyboard or Start on any pad quits.
quit : Vocabulary.Input -> List(Command)
quit = |input| if Key.pressed(input, Escape) or Button.pressed_any(input, Start) [Quit] else []
```
<!-- endregion -->

The buttons follow the rules of the keys in [Input](input.md#held-and-pressed):

- A button is pressed in exactly one step for each press. A button tapped
  between two steps is pressed but not held.
- The host keeps a press until a step takes it. The first step of a frame
  gets the presses, and the later steps of that frame get none.
- A button that is already down when its pad connects is held, but not
  pressed. So a player who connects a pad with Start down does not quit.
- When the window loses focus, the host lets go of every button and sets
  the sticks and triggers to 0.

The triggers are not buttons. Read them as numbers, below. The Guide button,
such as the Xbox button in the middle of the pad, is not read at all.

## The sticks and the triggers

Each Gamepad has a `left_stick` and a `right_stick`, each a record with an
`x` and a `y`:

- `+x` is right and `+y` is up, on every OS.
- The stick is always inside the unit disc: its length is at most 1. Pushed
  all the way in any direction, its length is 1. Many pads let the stick
  reach the corners of a square, and the host pulls those back to the edge
  of the disc.
- The host applies a dead zone of 0.2. A stick nearer the centre than that
  reads 0, and the rest of the travel is scaled up, so the length still
  goes all the way from 0 to 1.

So you can use a stick as a direction and a speed at once. Tutorial chapter
9 adds the left stick to the keys, and clamps the result to the unit disc,
so that two inputs together walk no faster than one:

<!-- region: examples/tutorial/09-gamepad/main.roc#walk -->
```roc
# Units each second.
speed : F32
speed = 2.5

# Pip stops this far from the centre, inside the edge of the ground.
edge : F32
edge = 2.7

# The left sticks of all the pads, added up.
left_stick : Vocabulary.Input -> { x : F32, y : F32 }
left_stick = |input| List.fold(input.gamepads, { x: 0.0, y: 0.0 }, |sum, pad| { x: sum.x + pad.left_stick.x, y: sum.y + pad.left_stick.y })

# A vector longer than 1 shrinks to length 1. A shorter one stays as it is.
clamp_to_disc : Vec3 -> Vec3
clamp_to_disc = |v|
	if V.length(v) > 1.0 {
		V.normalize(v)
	} else {
		v
	}

# W and the stick pushed up move away from the camera, toward -z.
walk : Model, Vocabulary.Input, F32 -> Model
walk = |model, input, dt| {
	stick = left_stick(input)
	dir = clamp_to_disc({ x: Key.axis(input, A, D) + stick.x, y: 0.0, z: Key.axis(input, W, S) - stick.y })
	if dir == V.zero {
		model
	} else {
		moved = V.add(model.pos, V.scale(dir, speed * dt))
		{ ..model, pos: { x: keep_on_ground(moved.x), y: 0.0, z: keep_on_ground(moved.z) }, yaw: F32.atan2({ x: dir.z, y: dir.x }) }
	}
}
```
<!-- endregion -->

In a 3D game, up on the stick usually means away from the camera, which is
`-z` in the tutorial. That is why `walk` subtracts `stick.y` from z.

`left_trigger` and `right_trigger` go from 0.0, at rest, to 1.0, pulled all
the way. The host applies a small dead zone of 0.05, so a trigger at rest
reads 0.

The host polls the pads once in each frame, before the steps of that frame.
Every step of a frame gets the same sticks and triggers.

## Slots and more than one player

Each Gamepad has a `slot`, from 0 to 3:

- The first pad that connects takes slot 0. A new pad takes the lowest free
  slot.
- A pad keeps its slot while it stays connected.
- When a pad disconnects, its Gamepad leaves the list, and its slot is
  free.
- The host reports at most 4 pads. A fifth pad waits, and takes the first
  slot that frees.

The list is in slot order, but it has gaps: if the pad in slot 0
disconnects, the list holds only the pad in slot 1. So find a player's pad
by its slot, not by its place in the list. In a game for two players, the
pad in slot 0 is player one, and the pad in slot 1 is player two:

```roc
pad_in : Vocabulary.Input, U8 -> Try(Vocabulary.Gamepad, [NotFound])
pad_in = |input, slot| List.find_first(input.gamepads, |pad| pad.slot == slot)
```

`Button.held(pad, South)` then asks that player's pad only.

A slot is not the same on every run. It depends on the order in which the
pads connected, so a game for two can show the player which pad is theirs.

## Test the gamepad

A Gamepad is a record, so you test it without a pad. Start from
`Input.empty` and put your Gamepads in `gamepads`. Make each Gamepad from
`Input.idle_gamepad`, a pad in slot 0 with no button down and the sticks at
rest, and change only the fields the test needs. Make the button codes with
[`Button.code`][Button.code]. These are the tests of tutorial chapter 9:

<!-- region: examples/tutorial/09-gamepad/main.roc#tests -->
```roc
with_pads : List(Vocabulary.Gamepad) -> Vocabulary.Input
with_pads = |pads| { ..Input.empty, gamepads: pads }

# The stick halfway up walks Pip toward -z at half speed.
expect {
	half_up = { ..Input.idle_gamepad, left_stick: { x: 0.0, y: 0.5 } }
	moved = step(start, with_pads([half_up]), QueryResults.empty, 0.1).model
	near(moved.pos.z, -0.125) and near(moved.pos.x, 0.0) and near(moved.yaw, pi)
}

# The stick all the way right walks Pip toward +x at full speed.
expect {
	right = { ..Input.idle_gamepad, left_stick: { x: 1.0, y: 0.0 } }
	moved = step(start, with_pads([right]), QueryResults.empty, 0.1).model
	near(moved.pos.x, 0.25) and near(moved.pos.z, 0.0)
}

# W and the stick up together walk Pip no faster than W alone.
expect {
	up = { ..Input.idle_gamepad, left_stick: { x: 0.0, y: 1.0 } }
	both = { ..with_pads([up]), held: [Key.code(W)] }
	moved = step(start, both, QueryResults.empty, 0.1).model
	near(V.length(moved.pos), 0.25)
}

# A pad at rest leaves Pip where it is.
expect step(start, with_pads([Input.idle_gamepad]), QueryResults.empty, 0.1).model == start

# Start pressed on any pad quits, here on the pad in slot 2.
expect {
	start_pressed = { ..Input.idle_gamepad, slot: 2, pressed: [Button.code(Start)] }
	step(start, with_pads([Input.idle_gamepad, start_pressed]), QueryResults.empty, 0.1).commands == [Quit]
}

# Start held from an earlier step does not quit again.
expect {
	start_held = { ..Input.idle_gamepad, held: [Button.code(Start)] }
	step(start, with_pads([start_held]), QueryResults.empty, 0.1).commands == []
}
```
<!-- endregion -->

A test gives the Gamepad values as `step` gets them, after the dead zone.
Put a stick at `y: 0.5`, and `step` sees 0.5.

## Gamepads and the Bridge

The [Bridge](bridge.md) can connect pads with the `gamepads` field of a
`step` request, so a script or CI can play with a pad that does not exist.
While the Bridge is on, its pads replace the real ones. This request walks
Pip in chapter 9 with the left stick halfway up:

```
{"op":"step","n":30,"gamepads":[{"slot":0,"left_stick":[0,0.5]}]}
{"ok":true,"steps":30,"commands":[],"alloc":{"step":30,"allocs":15,"deallocs":15,"reallocs":6,"live":12,"step_us":23.1,"view_us":24.0}}
```

After it, the `scene` reply has Pip at z `-0.31249997`: half of the
`-0.625` that W gives in 30 steps.

A Bridge pad differs from a real pad in three ways:

- A pad that was not in the step before held nothing, so its held buttons
  are pressed in its first step. A real pad that connects with a button
  down holds it but does not press it.
- The Bridge applies no dead zone. `step` gets the sticks and the triggers
  as the request gives them, so `[0, 0.5]` is 0.5. A real stick pushed
  halfway reads less, because the dead zone takes the first 0.2 of its
  travel.
- A stick outside the unit disc fails the request. A real stick there is
  pulled back to the edge of the disc.

[The Bridge](bridge.md#step) lists every field and error.

## Reference

### The buttons

Each Button is named by its place on the pad. The code is the number that a
Gamepad holds in `held` and `pressed`.

| Button | Code | Xbox | PlayStation | Nintendo Switch |
|---|---|---|---|---|
| `South` | 0 | A | Cross | B |
| `East` | 1 | B | Circle | A |
| `West` | 2 | X | Square | Y |
| `North` | 3 | Y | Triangle | X |
| `LeftShoulder` | 4 | LB | L1 | L |
| `RightShoulder` | 5 | RB | R1 | R |
| `LeftStick` | 6 | Left stick press | L3 | Left stick press |
| `RightStick` | 7 | Right stick press | R3 | Right stick press |
| `Start` | 8 | Menu | Options | + |
| `Back` | 9 | View | Share or Create | − |
| `DpadUp` | 10 | D-pad up | D-pad up | D-pad up |
| `DpadDown` | 11 | D-pad down | D-pad down | D-pad down |
| `DpadLeft` | 12 | D-pad left | D-pad left | D-pad left |
| `DpadRight` | 13 | D-pad right | D-pad right | D-pad right |

The triggers are `left_trigger` and `right_trigger`: LT and RT on Xbox, L2
and R2 on PlayStation, and ZL and ZR on Switch. The Switch triggers have no
travel, so they read 0 or 1.

A Switch pad has its A and B, and its X and Y, in the places where an Xbox
pad has B and A, and Y and X. So a prompt such as "press A" is right for
one kind of pad only, and rocco does not tell your game which kind it is.
Name the action in your prompts, such as "jump", or show the place of the
button.

rocco has been checked with Xbox pads only. The PlayStation and Switch
columns give the label at each place. An OS driver that reports a pad by
its labels, not by their places, swaps `South` with `East` and `West` with
`North` on a Switch pad.

### The limits on each OS

**macOS** reads the pads that Apple's GameController knows: Xbox,
PlayStation, Switch Pro and MFi pads, on a cable or over Bluetooth.

- GameController sends nothing while the game window is not in front.
- GameController applies its own small dead zone before the host's.
- A pad that is connected at start can take a few frames to appear.

**Windows** reads pads through XInput.

- XInput reads Xbox pads and pads that act like one. A PlayStation or
  Switch pad needs a tool such as Steam Input or DS4Windows, which makes it
  look like an Xbox pad.
- A pad that you plug in can take up to 1 s to appear. The host checks for
  a new pad once a second, as Microsoft advises.
- XInput can only poll, so a tap shorter than one frame can be lost.
- The host needs `xinput1_4.dll`, which is part of Windows 8 and later. If
  it is missing, the host logs one line and reports no pads.

**Linux** reads pads through evdev, from `/dev/input`.

- The pad needs a kernel driver that uses the standard gamepad layout, such
  as `xpad` for Xbox pads, `hid-playstation` and `hid-nintendo`.
- The player needs read access to the pad's node in `/dev/input`. Most
  desktops give it to the user at the screen. If no pad appears, add the
  user to the `input` group, or add a udev rule.
- The `xpad` driver swaps X and Y. The host reads the driver's name and
  swaps them back, so `West` is X on an Xbox pad on Linux too.
- Bluetooth Xbox pads use other drivers, which the host does not map
  specially. Use a cable.
- rocco has not been checked with a real pad on Linux yet.

On every OS, a Headless run reads no pads, and while the Bridge is on, only
the Bridge pads reach the game.

### The Bridge fields

Each entry of `gamepads` in a `step` request is an object. A field that you
leave out is 0 or empty.

| Field | Means |
|---|---|
| `slot` | The pad's slot, a whole number from 0 to 3. The default is 0. Two pads cannot share a slot. |
| `held` | A list of Button names, such as `"South"` and `"DpadUp"`, held for every step. |
| `tap` | A list of Button names, pressed but not held, in the first step only. |
| `left_stick`, `right_stick` | `[x, y]`, for every step. `+y` is up. It must be inside the unit disc. |
| `left_trigger`, `right_trigger` | A number from 0 to 1, for every step. |

A request with no `gamepads` has no pad connected.

### Limits

- No rumble, lights, gyro or touchpad.
- No Guide button, and no button pictures for the prompts in your UI.
- At most 4 pads.
- The dead zones are fixed. A game cannot change them.

[Input]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Input
[Gamepad]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Gamepad
[Button]: https://pixelsprout.dev/projects/rocco/api/platform/Button/
[Button.held]: https://pixelsprout.dev/projects/rocco/api/platform/Button/#Button.held
[Button.pressed]: https://pixelsprout.dev/projects/rocco/api/platform/Button/#Button.pressed
[Button.held_any]: https://pixelsprout.dev/projects/rocco/api/platform/Button/#Button.held_any
[Button.pressed_any]: https://pixelsprout.dev/projects/rocco/api/platform/Button/#Button.pressed_any
[Button.code]: https://pixelsprout.dev/projects/rocco/api/platform/Button/#Button.code
