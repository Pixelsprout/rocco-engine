# 0015: Gamepads are polled in the host

Status: accepted, 2026-10-26.

## Context

Milestone 23 gives `Input` the gamepads. sokol_app reads no gamepad, and
sokol has no gamepad module, so the host must call the OS. Each native
dependency costs entries in the link catalogs: the macOS sysroot, the
Linux stubs and the Windows import libraries. ADR 0011 found that a
library opened at run time costs no catalog entry.

## Decision

- The host polls the pads once per frame, before the steps of that frame,
  through one Gamepad reader per OS, each in its own file:
  `engine/gamepad_darwin.odin`, `engine/gamepad_windows.odin` and
  `engine/gamepad_linux.odin`. A shared file, `engine/gamepad.odin`, owns
  the slots, the latch, the dead zones and the focus clear. It has no OS
  calls.
- Each Gamepad reader reports every connected pad, up to 8, with an id
  that stays the same while the pad stays connected. The id is a device
  key, not the slot. The shared slot table gives a new pad the lowest free
  slot of 4 on every OS. A pad past the 4 slots takes the first slot that
  frees.
- macOS: `GameController.framework`, opened with `dlopen`, through our own
  thin bindings with the Odin objc intrinsics. The host finds the
  `GCController` class with `objc_lookUpClass` after the `dlopen`, because
  Odin resolves the classes that the code names before `main`. The host
  polls `GCController.controllers` and reads `extendedGamepad`.
- Windows: XInput. The host opens `xinput1_4.dll` with `LoadLibraryA` and
  gets `XInputGetState` with `GetProcAddress`. It uses the types from
  `core:sys/windows`, but not its foreign procs, which link `xinput.lib`.
  `core:sys/windows` binds no `LoadLibraryA`, so the engine declares it.
  The XInput index, 0 to 3, is the pad's id. The host checks an empty
  index once a second, as Microsoft advises.
- Linux: evdev through `core:sys/linux` syscalls. The host scans
  `/dev/input/event*` at startup for nodes with `BTN_GAMEPAD`, and watches
  `/dev/input` with `inotify`. An open that fails with `EACCES` is tried
  again for 1 s, and an `IN_ATTRIB` event tries it again too, because udev
  sets the access rights after it makes the node. `xpad` reports X as
  0x133 (`BTN_NORTH`) and Y as 0x134 (`BTN_WEST`), so the host reads each
  pad's driver name from sysfs and swaps the two codes for `xpad` only.
- No Gamepad reader adds a catalog entry. `dlopen`, `objc_lookUpClass`,
  `LoadLibraryA`, `GetProcAddress` and `FreeLibrary` are already in the
  catalogs, and `core:sys/linux` makes raw syscalls.
- Each Gamepad reader copies the OS state into a plain value and maps it
  with a pure procedure in a file with no OS suffix, so Odin tests cover
  the mapping on every runner: `gc_map` in `engine/gamepad_gc.odin`,
  `xinput_map` in `engine/gamepad_xinput.odin`, and `evdev_apply` and
  `evdev_map` in `engine/gamepad_evdev.odin`.
- While the Bridge is on, its pads replace the real pads, so CI tests
  gamepad Input with no pad.

## Considered options

- IOKit HID on macOS, raw HID input on Windows, or a mapping database such
  as SDL's. Rejected: each needs a mapping table for each pad model.
- `vendor:darwin/GameController`. Rejected: the pinned Odin (dev-2026-08)
  does not have it. A newer Odin has it, but it links the framework, which
  adds an entry to the macOS catalog. Our bindings need about ten
  selectors.
- `Windows.Gaming.Input`. Rejected: it needs WinRT and COM from Odin and
  `combase` in the catalog.
- GameInput. Rejected: the player must install a runtime.
- `libudev` for hot-plug on Linux, as Karl2D uses. Rejected: a new library
  opened at run time, with no hot-plug when it is missing. `inotify` gives
  the same events through a syscall.

## Consequences

- macOS reads only the pads that GameController knows: Xbox, PlayStation,
  Switch Pro and MFi. GameController sends no input while the game window
  is not in front, and the host keeps that default.
- Windows reads only Xbox-compatible pads. A PlayStation pad works through
  Steam Input or DS4Windows. A pad that connects can take up to 1 s to
  appear.
- Linux reads only pads whose kernel driver uses the standard gamepad
  layout, such as `xpad`, `hid-playstation` and `hid-nintendo`. The player
  needs read access to the event node; logind gives it on most desktops.
  Bluetooth Xbox pads use other drivers, which the host does not map
  specially.
- The macOS and Windows readers poll the state of each pad, so a tap
  shorter than one frame can be lost there. The Linux reader reads every
  evdev event and keeps each button that went down until the next poll,
  so it keeps such a tap.
- Rumble later needs a write path in each Gamepad reader:
  `XInputSetState`, `GCDeviceHaptics` and evdev `EV_FF`.
