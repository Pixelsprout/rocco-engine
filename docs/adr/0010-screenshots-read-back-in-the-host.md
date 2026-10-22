# 0010: Screenshots read back in the host

Status: accepted, 2026-10-22.

## Context

The Bridge's `screenshot` op saves what the window shows. The pinned sokol
has no pixel readback, and sokol_app has no capture call. On macOS the Metal
layer is `framebufferOnly`, so the drawable cannot be read. Before
Milestone 19, `scripts/screenshot.sh` captured the window from outside the
process with ScreenCaptureKit. That works on macOS only and needs the
Screen Recording permission.

## Decision

- The host renders each Frame to an offscreen target, then copies it to the
  swapchain.
- On a `screenshot` request, a native copy per backend reads the target
  back: Metal `getBytes`, a D3D11 staging texture and GL `glReadPixels`.
- A small PNG writer in the host stores the image at physical pixel size,
  with stored deflate blocks. It adds no link input.
- `scripts/screenshot.sh` drives the Bridge, and `wincap.swift` is deleted.
- Headless has no GPU, so the op returns an error there.

## Considered options

- Capture from outside the process: the Bridge gives the pid and the window
  id, and the Driver uses OS tools. Rejected: each Driver needs code per OS,
  macOS needs a permission, and Windows had no tool.
- `vendor:stb` image_write for the PNG. Rejected: it adds a C archive to
  every target's link catalog.
- Defer the screenshot. Rejected: a pixel check on all three targets is the
  main reason the engine is a harness for CI.

## Consequences

- Every Frame pays one extra full-screen copy.
- Each sokol backend has a native path in the host that sokol does not own.
  A sokol update can break it.
- The offscreen target is where post-processing can start in Milestone 25.
