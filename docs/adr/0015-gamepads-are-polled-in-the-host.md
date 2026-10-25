# 0015: Gamepads are polled in the host

Status: proposed, 2026-10-26.

## Context

Milestone 23 gives `Input` the gamepads. sokol_app reads no gamepad, and
sokol has no gamepad module, so the host must call the OS. Each native
dependency costs entries in the link catalogs: the macOS sysroot, the
Linux stubs and the Windows import libraries. ADR 0011 found that a
library opened at run time costs no catalog entry.

## Decision

- The host polls the pads once per frame through one file per OS, beside
  sokol. A shared file, `engine/gamepad.odin`, owns the slots, the latch,
  the dead zones and the focus clear. It has no OS calls.
- macOS: `GameController.framework`, opened with `dlopen`, through our own
  thin bindings with the Odin objc intrinsics. The host polls
  `GCController.controllers` and reads `extendedGamepad`.
- Windows: XInput. The host opens `xinput1_4.dll` with `LoadLibraryA` and
  gets `XInputGetState` with `GetProcAddress`. It uses the types from
  `core:sys/windows`, but not its foreign procs.
- Linux: evdev through `core:sys/linux` syscalls. The host scans
  `/dev/input/event*` at startup and watches `/dev/input` with `inotify`.
- No backend adds a catalog entry. `dlopen`, `objc_lookUpClass`,
  `LoadLibraryA` and `GetProcAddress` are already in the catalogs, and
  `core:sys/linux` makes raw syscalls.
- Each backend copies the OS state into a plain value and maps it with a
  pure procedure, so Odin tests cover the mapping on every runner.

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
  Switch Pro and MFi.
- Windows reads only Xbox-compatible pads. A PlayStation pad works through
  Steam Input or DS4Windows.
- Linux reads only pads whose kernel driver uses the standard gamepad
  layout, such as `xpad`, `hid-playstation` and `hid-nintendo`. The player
  needs read access to the event node; logind gives it on most desktops.
- XInput polls only, so a tap shorter than one frame can be lost on
  Windows.
- Rumble later needs a write path in each backend: `XInputSetState`,
  `GCDeviceHaptics` and evdev `EV_FF`.
