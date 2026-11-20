# 0017: Sounds the game controls are Speaker Nodes

Status: accepted, 2026-10-27.
Supersedes: ADR 0012 (A Play is a Command, a Loop is a Description).

## Context

A sound lasts longer than a fixed step, so the host holds it between steps.
Some sounds the game fires and forgets. Others the game must stop, change,
restart, or carry on a moving object. Lights and Colliders already take
their place from the Groups above them, and ADR 0016 gives the game each
Clip's duration instead of a Loop or Once mode in the host.

## Decision

- A sound that plays once and needs no control is the Command `Play`.
  Nothing pairs it, and the game cannot stop it. It plays to its end, or
  until its pack unloads.
- A sound that the game controls is a Speaker Node in the Scene tree, with
  `repeat : [Loop, Once]`.
- A Place inside a Group is local to the Group, by the rule of a Draw's
  `pos`. A `Here` Speaker ignores its Group, as an Ambient Light does. The
  host takes the world place from the current Scene, with no
  interpolation, because the Listener is the Camera of the current Scene.
  A placed sound falls off linearly to zero at its range, as a Point Light
  does.
- The host pairs a Speaker with the Speaker of the same Speaker id anywhere
  in the previous tree, so a Speaker that moves to another Group keeps
  playing. A new id starts, a missing id stops with a short fade, a
  changed Sound id restarts, and a changed gain, pitch or Place applies.
- A `Once` that ends stays paired and silent, and gives its voice back. The
  game plays it again with a new id, or by removing it for one step.
- The host does not tell the game that a `Once` ended. The Manifest gives
  each Sound's duration at pitch 1.

## Considered options

- `Spawn` and `Destroy` Commands by id. Rejected: the game would track
  which sounds it started, and a missed `Destroy` leaks a sound forever. A
  Speaker that leaves the Scene stops by itself. `step` would also compare
  each Model with the one before to find when to send each Command, and a
  loaded save or a replay from the middle would not match what plays. A
  Description comes from the Model on each `view` and cannot drift.
- Every sound in the Scene, with no Command. Rejected: a sound that plays
  once would need an id, and the game would keep it in the Scene until the
  sound ends, which only the host knows.
- A flat list of repeating sounds in the Scene, apart from the tree.
  Rejected: its place is a world `pos`, so a sound on a moving object needs
  its `pos` from the Model each step. It also cannot hold a sound that
  plays once but must stop.
- The host reports the end of a `Once`. Rejected: the game has the
  duration, as with Clips, and the seam gains no new data to the game.

## Consequences

- A sound placed on a moving object needs no `pos` from the Model. Put the
  Speaker in the object's Group.
- A `Once` Speaker that leaves with its object stops. An explosion on a
  projectile that the game removes is a `Play`.
- The duration is at pitch 1. A game that plays a `Once` at another pitch
  divides by the pitch.
- A game has no master volume. It scales the gains it returns.
