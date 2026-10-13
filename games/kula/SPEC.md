# Kula behaviour spec

This file states how the original Kula World (PAL, SCES-01000) moves the
ball, places the camera and draws blocks. It also states what this clone
copies. Each fact has a label:

- **Code**: read in the decompilation, `github.com/dezgeg/kula-world-decomp`
  at commit `2ca79ff`. Paths below are in that repository.
- **Reported**: a third party states it. Nobody checked it in code.
- **Inferred**: derived from Code facts.

## Units

The original uses 512 units for one block and 4096 for a full turn. The
game logic runs once per video frame, at 50 frames per second on PAL. This
clone uses cells, radians and seconds. One PAL frame is 0.02 s.

## Ball

| Fact | Original | Label | Clone |
|---|---|---|---|
| Radius | 100 units, 0.195 cell | Code: the ball centre rests 100 units above a face | `Ball.radius = 0.195` |
| Visual radius | Not found | | Same as the collision radius |
| Spin | Not modelled here | | The distance the centre travels over the radius |

The ball centre is 0.195 cell above the face it stands on. The draw centre
is the cell centre minus 0.305 along up.

## Moves

The clone moves on a grid. The pose commits when a move starts. A move then
plays out over its duration.

### Roll

The ball tests three cases in this order (`src/player_movement.c`,
`src/level_update.c`, Code):

1. **Climb.** A block is directly ahead. The ball stays in its cell. New up
   is minus old forward. New forward is old up.
2. **Floor.** A block is ahead and below. The ball moves one cell forward.
3. **Edge.** Otherwise the ball rolls over the edge onto the side of the
   block it stands on. New up is old forward. New forward is minus old up.

The edge roll needs an open end. If a block sits to the left or the right
of the block the ball stands on, the ball does not roll (Code,
`HandleViewportRotationStart`). The speedrun notes on
speeddemosarchive.com report the same rule.

| Move | Original | Label | Clone |
|---|---|---|---|
| Floor roll | Speeds up by 7 units a frame to 40 units a frame | Code | 0.26 s, the time for one cell at top speed |
| Climb | The camera turns 90° in 14 frames. The ball does not move | Code | 0.28 s |
| Edge roll | The ball wraps the edge in 4 frames. The camera turns 90° in 11 frames | Code | 0.34 s: half a cell at top speed, the wrap, half a cell (inferred) |
| Turn | 90° in 16 frames, linear | Code | 0.32 s |

Round an edge, the original moves the ball centre on a fixed arc. Each of
the 4 frames steps (up, forward) by (38, 8), (32, 22), (22, 32), (8, 39)
units, about one radius in all (Code, `ProcessMovement` case `ROTATING`).
The clone moves the centre half a cell to the edge, a quarter circle of one
radius about the edge line, then half a cell down the side. The ball never
enters the block.

The original stops the ball at a cell centre when forward is not held. The
clone has no speed-up.

### Jump

| Fact | Original | Label | Clone |
|---|---|---|---|
| Landing | Exactly two cells ahead at the same level | Code | Same |
| No floor there | The ball falls | Code | `Fall`. The Rules task makes the ball fall |
| A block in the path | The ball bounces back and falls | Code, `CheckForPlayerWallHit` | `Bounce` when a block sits one or two cells ahead |
| A block above | Not found | | `Bounce` (inferred) |
| Duration | 27 frames | Reported, wiki.kula.quest | 0.54 s |
| Peak height | Not found | | 0.5 cell |

A jump never lands on top of the block ahead. The only way onto a wall is
to roll into it.

## Camera

The camera is rigid in the ball's frame (`HandlePlayerMovementStuff`,
`src/level_update.c`, Code):

- The camera basis is the ball's right, up and forward, pitched down by
  250/4096 of a turn, 21.97°.
- In view space the ball centre sits 250 units below the screen centre at a
  depth of 800 units.
- The camera has no smoothing and no collision test.

Inferred from these: the eye is 1.27 cells behind the ball centre and 1.04
cells above it. The clone builds the eye from the same view-space numbers.

| Fact | Original | Label | Clone |
|---|---|---|---|
| Vertical field of view | 73.7° on 4:3 | Inferred from a projection distance of 160 on a 320-pixel screen | 1.286 rad |
| Smoothing | None | Code | None |
| Turn during a climb or edge roll | Linear in angle | Code | Normalised lerp of up and forward |
| Look up and look down | R1 and R2 | Code | Not copied yet |

After a climb, the eye sits inside the floor block the ball left (Inferred).
The next section explains why that floor does not hide the ball.

## Blocks

At level load, the original builds one quad for each block face. It skips a
face when the neighbour cell holds a solid block (`ProcessCubesIntoFaces`,
`src/level_init.c`, Code). Faces carry a flag that the decompiler marks as
back-face culling, with a question mark.

The clone draws each exposed face as the one-sided primitive plane. The
engine culls back faces. A camera inside a block therefore sees through
that block, because every face of it points away. No face exists between
two blocks, so the neighbours do not hide the ball.

A whole-cube mesh would draw the faces between blocks. Do not use one for
level blocks.

## Not copied

- The speed-up at the start of a roll.
- Look up and look down.
- The "hall of mirrors": in skybox themes the original does not clear the
  screen each frame (Code, `src/disp.c`). The engine clears every frame.
- The long jump and the boost.

## Sources

- https://github.com/dezgeg/kula-world-decomp
- https://wiki.kula.quest/
- https://speeddemosarchive.com/KulaWorld.html
- https://kulaquest.pinkgothic.com/storybehind.html
