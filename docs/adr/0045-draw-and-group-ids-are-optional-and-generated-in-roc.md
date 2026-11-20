# 0045: Draw and Group ids are optional and generated in Roc

Status: accepted, 2026-11-20. Grilled for Milestone 47 (bcpqrlof).

## Context

A game types a `U64` id on every Draw and Group, and on each Collider,
Speaker, Emitter and Panel. The host pairs Draws and Groups with the
previous Scene only to interpolate (ADR 0013, ADR 0014). The other ids are
names the game reads or addresses: Contacts and hits report Collider ids,
Speakers start and stop by id, a Burst names an Emitter, and Panel ids feed
the UI hit test, where id 0 already means "not tagged".

The examples choose ids in five ways: typed constants, a counter in the
Model, a base plus an offset, the list index and generated tables. No
helper exists. The Editor (ADR 0042) needs Nodes that stay the same from
step to step to show a tree and a selection. ADR 0043 pairs a placed Prefab
node by a `U64` hash of the placed id and its Path.

The grilling for ADR 0043 decided that an id is made once, when the game
first creates the thing, and stored in the Model. The host never issues
ids.

## Decision

- Draw and Group ids are optional. Id 0 means no id.
- A Draw or Group with id 0 pairs by its position under its anchor: the
  nearest ancestor Group with a non-zero id, or the Scene root. The
  position counts only siblings of the same kind that also have id 0.
- A placed Prefab node has its hash id, so it never pairs by position.
- Collider, Speaker, Emitter and Panel ids stay explicit, because the game
  names them.
- An Attach must name a non-zero draw id. An Attach to id 0 logs once and
  does nothing. A Collider with id 0 collides and reports id 0.
- A platform module, `Id.roc`, holds an opaque `Ids` counter that a game
  keeps in its Model. `ids.fresh()` returns the next id, from 1 upward.
  It never reuses an id and replays the same.
- Bit 63 of an id is reserved for Prefab node hashes. Generated and typed
  ids keep it clear. A debug build logs once for a typed id that sets it.
- `Prefab.node_id` folds the placed id and each Path id with SplitMix64,
  then sets bit 63. Test vectors in Roc and in Odin pin the result. It
  ships with the Prefab Node, not before.
- The rule for authors: give an id to anything that comes, goes or moves
  between lists.

## Considered options

- An id on every Node. Rejected: scenery needs an id that nothing reads.
- Optional ids for every kind, Speakers included. Rejected: a Speaker
  without an id restarts or fades when a list changes, and the game names
  it anyway.
- No pairing for a Node without an id. Rejected: a moving Node jumps.
- A position that counts every child. Rejected: a new Light or Speaker
  would shift the Draws after it.
- Random generated ids from a Seed. Rejected: a counter replays the same
  and reads well in the Editor. Random local ids stay for Prefab files,
  which git branches edit (ADR 0043).
- A full-width hash with no reserved bit, or a separate id space for
  Prefab nodes. Rejected: the first is a probability, not a guarantee; the
  second adds a map to every pairing table.
- `packages/ids`. Rejected: `node_id` must match the host, so it belongs
  with the Vocabulary.
- xxHash64. Rejected: SplitMix64 is a few lines on each side and mixes well
  enough for ids.

## Consequences

- Existing non-zero ids behave as before. Id 0 changes meaning: today all
  Draws with id 0 share one id, and the first pairs.
- `cards` stops using slot index 0 as a draw id.
- The tutorial games and `entity-game` move to `ids.fresh()` and drop their
  scenery ids. Other examples and Kula move when someone works on them.
- Editor selection of a Node without an id uses its positional key, and can
  slip to another Node when a list ahead of it changes.
- Three tickets under Milestone 47 deliver it: the host, then `Id.roc` with
  the `cards` fix, then the games and the docs. Each blocks the next, and
  all three block Editor 1.
