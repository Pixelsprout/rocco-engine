# 0042: The Editor is a Rocco app that watches over the Bridge

Status: accepted, 2026-11-20. Grilled for Milestone 47.

## Context

Milestone 47 starts a Rocco Editor, with a level editor as the end goal.
The Scene is a Description that the game rebuilds each step, and the host
keeps no Node from one Scene to the next (ADR 0014). The Bridge
already drives any game with no change to the game (ADR 0009), but it
serves one Driver, in lockstep, and has no way to watch a live run.

A measurement on `bench/draws` gave these `scene` reply costs on one
socket:

| Nodes | JSON bytes | Host encode | Python decode |
|---|---|---|---|
| 1,001 | 347 KB | 0.5 ms | 2.2 ms |
| 10,001 | 3.5 MB | 4.7 ms | 24 ms |

The host encodes and sends inside the Frame, so a watched game at 10,000
Nodes loses about 5.5 ms of each Frame.

## Decision

- The Editor is a Rocco app written in Roc. It launches the game as its
  own process and reaches it through a Link: a Port whose far end is the
  game's Bridge. Other Drivers and Observers, such as an agent, attach to
  the same run. `.rocco/session.json` in the game folder names the port,
  the process id and the current Driver.
- The Bridge serves one Driver and any number of Observers. An Observer
  reads and Watches, but cannot step or inject Input. `hello` names each
  process and gives a protocol version and a capability list. The Editor
  stays open as an Observer and shows which process drives.
- Requests and the `scene` reply stay JSON. A Watch sends a binary Scene
  codec that the glue generates from the Vocabulary, with the Roc decoder.
  The host copies the stored Scene and encodes and sends it off the Frame
  thread. Each Watch has its own rate, and a slow Observer gets the
  newest Scene, not a queue.
- New ops: `watch`, `manifest` (the loaded Packs and their ids) and
  `asset` (an asset's bytes). The Editor gets everything through the
  protocol, so another editor can do the same.
- The Scene pane draws the game's Scene in the Editor, with the Editor's
  camera. A Render, a Scene drawn into an Image, puts it in a Pane. The
  Game pane shows the game's own frames through a shared GPU texture in a
  later milestone, one backend at a time. On the web it is an iframe.
- The Editor is a Shell that composes Tools. A Tool is a Roc package whose
  core names no Rocco type. A project can write its own Shell from stock
  and custom Tools.
- The protocol is a product: a specification, a Roc client package and a
  conformance suite that runs against a Headless host.
- Inspection works on any game unchanged. Every edit goes through a Port
  that the game Listens on.
- The Editor lives in `editor/` in this repo. Hot reload aims to keep the
  Model, as the Tour does; rebuild and relaunch comes first.

## Considered options

- The Editor inside the game process. Rejected: it puts editor state
  beside the game and breaks Bridge determinism.
- A new editor protocol beside the Bridge. Rejected: two transports, and
  existing games would need both.
- Protobuf or FlatBuffers for a Watch. Rejected: a second schema to keep in
  step with the Vocabulary and a new dependency. simdjson helps only the
  client decode, not the encode inside the Frame.
- JSON for a Watch, sent off the Frame thread. A smaller first step, but
  the Roc client would still need a hand-written decoder for the whole
  Vocabulary.
- Game frames as the only view. Rejected for the first milestone: a
  shared texture is separate work on each backend and does not work
  between web pages.

## Consequences

- "An editor" leaves the out-of-scope list in `docs/ROADMAP.md`.
- A Link is a Vocabulary change and the first Rocco feature that opens a
  socket from a game. It stays localhost only, so networking between
  players stays out of scope.
- A Render changes the meaning of Image: an Image is no longer only a
  Pack asset.
- `packages/ui` needs a tree view and split Panes before the first
  milestone. A text field waits for editing.
