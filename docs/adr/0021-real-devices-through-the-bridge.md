# 0021: Real devices through the Bridge

Status: accepted, 2026-10-31. It amends the considered options of ADR 0009:
the rejection of the merge stands for a test run, and a Driver may opt in.

## Context

Agent Town phase 4 needs a person's keys and clicks while the relay drives
the stage. ADR 0009 rejected a merge of the real devices with the Driver's
Input, because a run would then depend on where the mouse is. ADR 0020 gave
the game a pointer and a hit test, so a click on a tagged Box can now reach
the game, but only from the Driver.

## Decision

- `hello` takes `devices : Bool`. An absent field is false. The reply echoes
  it. A later `hello` sets it again. The setting belongs to the Driver that
  sent it: a Driver that reconnects starts with it off.
- With `devices` on, the host merges the real devices with the request's
  Input for each step:
  - Held keys are the union of the real keys and the request's `held`.
    Pressed follows from that union, step by step.
  - Mouse deltas add.
  - A pad in the request replaces the real pad in its slot. A real pad in
    another slot passes through with its own rules, so a pad that connects
    with a button down holds it and does not press it.
  - A request `pointer` replaces the real pointer's position, `inside` and
    wheel for that step. Without one, the real pointer passes through.
  - Pointer buttons merge like keys. Pressed and released follow from the
    union.
- The real latch keeps its edges while the run pauses. The step after a
  pause takes them, so a tap between two `step` requests reaches the game,
  and the step gets the whole mouse delta of the pause.
- A real press counts as Pressed when the key was not held in the step
  before. So a key that the request already holds is not pressed again by
  the real key.
- The `inject` op feeds events to the real devices through the same entry
  as the window's events. It needs `devices` on. It is the test seam, so a
  check can click with no OS input.
- `BRIDGE_PROTOCOL` becomes 7.

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
