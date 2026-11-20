# 0021: Real devices through the Bridge

Status: accepted, 2026-10-31.

## Context

Agent Town phase 4 needs a person's keys and clicks while the relay drives
the stage. ADR 0009 rejected a merge of the real devices with the Driver's
Input, because a run would then depend on where the mouse is. ADR 0004 gave
the game a pointer and a hit test, so a click on a tagged Panel can now reach
the game, but only from the Driver.

## Decision

- `hello` takes `devices : Bool`. An absent field is false. The reply echoes
  it. A later `hello` sets it again. The setting belongs to the Driver that
  sent it: a Driver that reconnects starts with it off.
- With `devices` on, the host merges the real devices with the request's
  Input for each step. Keys and buttons take the union, mouse deltas add,
  and a request's pad or pointer replaces the real one. `guide/bridge.md`
  gives the rules.
- The real devices keep their edges while the run pauses, so a tap between
  two `step` requests reaches the game.
- The `inject` op feeds events to the real devices through the same entry
  as the window's events. It needs `devices` on. It is the test seam, so a
  check can click with no OS input.

## Considered options

- An env var such as `ROCCO_BRIDGE_DEVICES`. Rejected: the Driver knows if
  a person watches, and the next Driver may not.
- Merge always. Rejected: ADR 0009's reason stands for a test run.
- Merge a request pointer with the real pointer. Rejected: two positions
  have no union.
- The `inject` op only in a test build. Rejected: CI checks the normal
  build.

## Consequences

- A run with `devices` on depends on the person, so tests leave it off.
- On macOS, sokol's tracking area uses `NSTrackingActiveInKeyWindow`, and
  its view has no `acceptsFirstMouse`. So hover reaches only the focused
  window, and the first click on an unfocused window only focuses it. This
  is accepted, and sokol is not patched.
- When the window loses focus, the real held keys, pad buttons and pointer
  buttons let go. The request's Input still arrives.
- A Driver that leaves during a `step` keeps the real devices for the rest
  of that request's steps, because the transport sees the disconnect only
  at its next poll.
- Agent Town phase 4 can read a person's keys and clicks and Tell the relay.
- The `inject` op is a test op. The Agent Town relay does not use it.
