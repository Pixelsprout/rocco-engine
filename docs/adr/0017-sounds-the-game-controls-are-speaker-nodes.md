# 0017: Sounds the game controls are Speaker Nodes

Status: draft, 2026-10-27. It replaces the Loop decision of ADR 0012. The
Play decision stands.

## Context

ADR 0012 split sound in two: a `Play` Command for a sound that plays once,
and a Loop in `Scene.loops` for a sound that repeats. The split tied two
things together: a sound the game can stop or change was always a sound
that repeats. That left three gaps:

- A sound that plays once cannot stop. `guide/sound.md` said to use a Loop
  and remove it, but the Manifest gives no Sound length, so the game cannot
  remove the Loop before it repeats.
- A sound that plays once cannot follow a moving object. A Play keeps the
  place it started at.
- A Loop cannot restart from its start without a new Loop id.

It also went against ADR 0016, which gives the game each Clip's duration
and refuses a Loop or Once mode in the host. A Loop's place was a world
`pos`, while Lights and Colliders take their place from the Groups above
them.

## Decision

- A sound that the game controls is a `Speaker` Node in `Scene.nodes`:
  `{ id, sound, gain, pitch, at, repeat : [Loop, Once] }`. `Scene.loops`
  and the `Loop` type go. `Speaker.default` is id 0, Sound 0, gain 1,
  pitch 1, `Here` and `Loop`.
- `Play` stays a Command, unchanged, for a sound that the game fires and
  forgets.
- `at` is the `Place` of ADR 0012. Inside a Group, `At`'s `pos` is local to
  the Group, by the rule of a Draw's `pos`. A `Here` Speaker ignores its
  Group, as an Ambient Light does. The host takes the world place from the
  current Scene, with no interpolation, because the Listener is the camera
  of the current Scene.
- Speaker ids are apart from draw ids and Group ids. The host pairs a
  Speaker with the Speaker of the same id anywhere in the previous tree, so
  a Speaker that moves to another Group keeps playing. Of two Speakers that
  share an id, the first in a depth-first walk plays, and the host logs
  once.
- The pairing rules of a Loop stay: a new id starts, a missing id stops
  with a 5 ms fade, a changed Sound id restarts, and a changed gain, pitch
  or place applies on the next fixed step.
- A changed `repeat` applies to the voice that plays. Loop to Once stops
  at the end of the current pass. Once to Loop keeps repeating. A `Once`
  that has ended does not start again.
- A `Once` that ends stays paired and silent, and gives its voice back at
  once. The game plays it again with a new id, or by removing it for one
  step.
- The host does not tell the game that a `Once` ended. Each Manifest entry
  gains `duration : F32`, the Sound's length in seconds at pitch 1, and 0
  for a mesh or a sky. `Sound.duration` reads it.
- No new capacity. `voices` bounds the Speakers that sound. Speakers that
  wait for a voice start in walk order.

## Considered options

- A `repeat` field on today's `Scene.loops`, as a flat list. Rejected: a
  Loop's place stays a world `pos`, and a sound on a moving object needs
  its `pos` from the Model each step.
- Commands that start and stop a sound on a Node in the tree. Rejected: the
  host would hold what plays, and the game would keep a copy. A missed stop
  leaks a sound. `step` would compare each Model with the one before to
  find the moment to send each Command. A loaded save or a replay from the
  middle would not match what plays. A Description comes from the Model on
  each `view` and cannot drift.
- Sound duration only, with Loops as they are. Rejected: it closes the
  first gap only, and keeps a type called Loop for sounds that do not
  repeat.
- The host reports the end of a `Once`. Rejected: the game has the
  duration, as with Clips, and the seam gains no new data to the game.

## Consequences

- A sound placed on a moving object needs no `pos` from the Model. Put the
  Speaker in the object's Group.
- A `Once` Speaker that leaves with its object stops. An explosion on a
  projectile that the game removes is a `Play`.
- The duration is at pitch 1. A game that plays a `Once` at another pitch
  divides by the pitch.
- The Bridge shows a Speaker as one more Node tag in a `scene` reply, with
  no protocol change.
