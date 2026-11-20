# 0015: Gamepads are polled in the host

Status: accepted, 2026-10-26.

## Context

sokol reads no gamepad, so the host must call the OS. Each native library
linked at build time costs entries in the link catalogs. ADR 0011 found
that a library opened at run time costs none.

## Decision

- The host polls the pads once per frame through its own Gamepad reader
  per OS: GameController on macOS, XInput on Windows, evdev on Linux. macOS
  also reads wired Xbox One pads, which GameController never lists,
  through GIP over IOKit USB.
- Every OS library is opened at run time, so no reader adds a catalog
  entry. Shared code with no OS calls owns the Gamepad slots and dead
  zones, and tests cover each reader's mapping on every runner.

## Considered options

- SDL, or HID with a mapping database. Rejected: each pad model needs a
  mapping table. GIP is one protocol for every Xbox One pad, so it needs
  none.
- libusb for GIP, `Windows.Gaming.Input`, GameInput or `libudev`. Rejected:
  each needs a player install, COM from Odin, or a new library.

## Consequences

- Windows reads only Xbox-compatible pads. Linux reads only pads whose
  driver uses the standard gamepad layout. The web host reads none yet.
