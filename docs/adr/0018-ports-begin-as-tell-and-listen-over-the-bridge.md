# 0018: Ports begin as Tell and Listen over the Bridge

Status: accepted, 2026-10-29. It replaces the first consequence of ADR
0009: a Driver can now send the game a message. The other decisions of
ADR 0009 stand.

## Context

ADR 0009 kept Ports out of Milestone 19 because no game needed one. The
Agent Town design is the first consumer. Its stage shows agents as
characters, and it needs messages both ways: a Driver tells the stage what
the agents do, and the stage tells the Driver what the person selects.

`docs/RESEARCH-SCALING.md` section 4b proposed the shape, after Elm's ports:
`Tell` as a Command, `Ask` and `Listen` as Queries, and the answers in
`QueryResults.ports`. Each port is one named channel with a `Str` payload.

## Decision

- The Vocabulary gains three things: a `Tell({ port, msg })` Command, a
  `Listen(Str)` Query, and `QueryResults.ports : List({ port, msg })`. The
  `Port` module builds them and reads the messages of one port.
- The Bridge gains the `tell` op. It queues the message in the host, and
  the next step that runs receives it, if the Scene the window shows
  Listens on that port. The messages of each port arrive in the order the
  host got them, and the queue empties.
- A message for a port that no Query Listens on at that step is dropped,
  and the host logs once per port. So a stale queue cannot grow.
- The queue holds at most 4 MiB of port names and messages. A `tell` past
  that replies with an error and queues nothing.
- A `Tell` reaches the Driver in the `step` reply, as every Command does.
  The host does not act on it. So the `listen` op is not needed.
- `Ask` and the `listen` op wait for a consumer. The `ask` and `listen` ops
  stay reserved and reply `not yet`.
- An extension later feeds the same queue. The game does not know where a
  message comes from.

## Considered options

- `Ask` with a slot now, as section 4b proposed. Rejected: nothing in the
  host answers it yet, so its rules would be a guess.
- Deliver a message to the step after next. Rejected: one more step of
  latency for nothing, since the queue is already in the host when the
  next step starts.
- Keep the messages of a port until a Listen for it appears. Rejected: a
  queue that grows for a port nobody reads, with no limit but the cap.

## Consequences

- `BRIDGE_PROTOCOL` is 2, because the `results` of a `scene` reply gain
  `ports`.
- The Vocabulary changed, so every game rebuilds.
- A Scene with only a Listen Query still runs the collider walk. A later
  change may skip it.
- `examples/bridge-echo` Listens on `echo` and Tells each message back, and
  the Bridge check drives it on every OS.
