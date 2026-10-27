# 0012: A Play is a Command, a Loop is a Description

Status: accepted, 2026-10-22. Partly replaced by ADR 0017 on 2026-10-27: a
sound the game controls is a Speaker Node, and the Loop and `Scene.loops`
are gone. The Play decision stands.

## Context

A sound lasts longer than a fixed step, so the host holds it between steps.
`docs/DESIGN.md` section 6 planned that the first thing with host-side
lifetime would add `Spawn` and `Destroy` by id to `Command`, and that the
host would reconcile. Sound is that first thing. Every Vocabulary change
rebuilds the host and every game, so Milestone 20 makes one change.

## Decision

- A sound that plays once is the Command `Play({ sound, gain, pitch, at })`.
  Nothing pairs it, and the game cannot stop it. It plays to its end, or
  until its pack unloads.
- A sound that repeats is a Loop in `Scene.loops`, a Description:
  `{ id, sound, gain, pitch, at }`. The host pairs Loops by Loop id with
  the previous Scene. A new id starts, a missing id stops with a short
  fade, a changed gain, pitch or place applies, and a changed Sound id
  restarts.
- `at` is `[Here, At({ pos, range })]`. The Listener is the Camera of the
  current Scene. A placed sound falls off linearly to zero at `range`, as a
  Point Light does.
- `Capacity` gains `sounds` and `voices`.

## Considered options

- `Spawn` and `Destroy` by id, as section 6 planned. Rejected: the game
  would track which sounds it started and send a `Destroy` for each, and a
  missed `Destroy` leaks a sound forever. A Loop that leaves the Scene
  stops by itself.
- Every sound in the Scene, with no Command. Rejected: a sound that plays
  once would need an id, and the game would keep it in the Scene until the
  sound ends, which only the host knows.
- `Play` only, with Loops later. Rejected: two Vocabulary changes in place
  of one, for a shape the research had already settled.

## Consequences

- A game cannot stop a Play. Music that must stop is a Loop.
- A game has no master volume. It scales the gains it returns.
- The Bridge shows a Play in the Commands of a `step` reply and the Loops in
  a `scene` reply, with no protocol change.
