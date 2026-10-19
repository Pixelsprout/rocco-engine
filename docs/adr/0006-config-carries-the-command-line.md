# 0006: Config carries the command line

Status: accepted, 2026-10-19.

## Context

A bench game must run at many sizes, such as 64 to 16,384 Draws. A game is
pure and cannot read the environment, so the size must arrive through the
seam. Config held only the Seed and the asset names.

## Decision

- Config gets `args : List Str`: the words after the game's name on the
  command line, in the order typed.
- The host does not parse the Args. What they mean is the game's decision.

## Considered options

- Build N into each bench game as a constant. It was rejected. Each N needs
  a rebuild, and Roc can fold the constant, so the code is less like a real
  game.
- Encode N in the Seed. It was rejected. The Seed then means two things.
- Let the game raise N itself during one run. It was rejected. Warmup and
  steady state mix in one curve.

## Consequences

- This is a Vocabulary change, so it rebuilds the host and every game.
- Real games can also take arguments, such as a level name.
