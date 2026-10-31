# 0009: The Bridge drives the host, not the game

Status: accepted, 2026-10-22. ADR 0021 on 2026-10-31 lets a Driver opt in
to the real devices. The rejection of the merge stands for a test run.

## Context

Milestone 19 makes the engine drivable by a script, a CI test or an agent.
`docs/RESEARCH-SCALING.md` section 4 proposed Ports first: `Tell`, `Ask`
and `Listen` in the Vocabulary, with a Bridge as "a Port whose far end is a
socket". No game needs a Port yet. Audio arrives as a host module with
`Play` and `Scene.sounds`, and the first real Port user is the extension ABI
in a later arc.

## Decision

- The Bridge is a host module, outside the Vocabulary. The game does not
  know it exists, and Milestone 19 makes no Vocabulary change.
- The Driver talks to the host, not to the game. It replaces the Input that
  `step` gets, asks for fixed steps, and reads the Scene the host stores.
- While a Driver controls the run, the host ignores the real keyboard and
  mouse. The same requests give the same Scenes.
- The socket and its JSON Lines framing are one module, and the Driver ops
  are another. The op names `tell`, `ask` and `listen` are reserved. When
  Ports arrive, a Port can reach the Driver through the same transport.

## Considered options

- Ports in Milestone 19, with the Bridge as one Port. Rejected: with no
  consumer, the Port design would be a guess, and it is a Vocabulary change
  that rebuilds every game.
- Merge the real devices with the injected Input. Rejected: a run would then
  depend on where the mouse is.

## Consequences

- A Driver cannot send the game a message. A game that wants one waits for
  Ports.
- The research's order is reversed: a Port reaches the Driver through the
  Bridge, and the Bridge is not a kind of Port.
