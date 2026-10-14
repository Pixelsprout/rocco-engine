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

The original has two kinds of jump, chosen when the jump starts
(`StartMovementIfNeeded`, `src/player_movement.c:125-188`, Code). The
buttons are read every frame (`HandlePlayerButtons`, `src/level_update2.c`).

- **Forward jump.** X while Up is held, or X while the ball rolls.
- **Jump in place.** X while the ball is still and Up is not held.

Speed does not change the kind. No input acts during a forward jump. During
a jump in place, L and R still turn the ball.

The ball stays in the rolling state until it reaches the edge of its block
(`HandleViewportRotationStart`, Code). Only then does the edge turn start.
X can therefore start a forward jump on the way to an edge.

A turn press during a turn waits. The next turn starts when the current one
ends (`startTurningLeftNextFrame`, `HandlePlayerButtons`, Code). The clone
copies this for every turn.

| Fact | Original | Label | Clone |
|---|---|---|---|
| Choice of kind | Forward when Up is held or the ball rolls; in place otherwise | Code | Same. A floor roll, or an edge roll before the ball reaches the edge, can start a jump. Climbs and turns cannot |
| Forward distance | 1024 units, two cells ahead at the same level (`player_movement.c:391`) | Code | Same |
| Start of a rolling jump | At once, from the ball's current position. Only the sideways offset snaps to the cell centre (`AutoAlignJumpStartPos`) | Code | At once, from the ball's current position. The ball lands two cells past the cell it is nearest to. On the way to an edge, that is the cell the ball rolls from. The clone's ball is always on the cell line, so it has no sideways snap |
| Jump in place | Same curve with only the vertical part. Lands on the same cell (`ProcessMovement`, `JUMPING_INPLACE`) | Code | `JumpingInPlace`: same duration and peak as the forward jump |
| Turn in mid-air | Forward jump: no input acts. Jump in place: L and R still turn the ball | Code | Same. The turn takes 0.32 s and can outlast the jump |
| No floor there | The jump ends, then the ball falls straight down. Gravity adds 6 units a frame to the fall speed, up to 80. It lands on the first block below (`CheckIfPlayerLanded`). The level ends only when the ball leaves the grid, -1 to 35 on each axis (`ProcessEnemiesRenderItemsAndCheckFellOff`) | Code | `Falling`: the jump arc, then a drop at 29.3 cells/s², up to 7.8 cells/s. The drop starts at the arc's end speed. It lands on the first block below. With no block below, the level restarts 2 cells past the lowest block along gravity |
| A block in the path | Forward jump only. Past 412/512 of its cell, a block ahead at the ball's height bounces it back and it falls (`CheckForPlayerWallHit`) | Code | Forward jump only. `Bounce` when a block sits one or two cells ahead. The ball does not jump |
| A block above | Both kinds. A rising ball at height 412 or more under a block bounces down and falls (`CheckPlayerHitCeiling`) | Code | Both kinds. `Bounce` before the jump starts |
| Landing window | The last 11 frames of the jump can land (`CheckPlayerJumpingStuff`) | Code | Same (`Ball.can_land`, t >= 16/27). The ball lands when its centre is at or below rest height over a floor. On level ground this is the end of the jump |
| After landing | Up held keeps the ball rolling at full speed (`CheckIfPlayerLanded`) | Code | Same. With Up held, the next roll starts in the step the jump lands and gets the time left over. A roll that ends with Up held does the same |
| Duration | 27 frames | Reported, wiki.kula.quest. The frame count is in GGI data (`ggiPart5JumpAnimData`), not in the C code | 0.54 s |
| Peak height | In GGI data | | 0.5 cell |

A jump never lands on top of the block ahead. The only way onto a wall is
to roll into it.

### Long jump

The long jump is not a button combination (Code):

- The Bouncy pill (`OBJ_BOUNCY_PILL`, `src/level_update3.c:184`) makes the
  ball jump all the time for 14 s. While it acts, Up and X held for more
  than 3 frames start a long jump (`level_update2.c`).
- A bounce pad (`OBJ_BOUNCEPAD`, `level_update3.c:1076-1093`) forces a long
  jump.
- A long jump scales the jump curve by 3/2. It lands 1536 units, three
  cells, ahead (`player_movement.c:371-389`).
- A wall hit, a ceiling hit or a landing ends it.

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

The clone draws each exposed face as `face.glb`, a one-sided quad like the
primitive plane with a lighter border. The engine culls back faces. A
camera inside a block therefore sees through that block, because every face
of it points away. No face exists between two blocks, so the neighbours do
not hide the ball.

Halfway through a climb, the eye passes down through the top face of the
floor the ball left. Just before that, the engine's near plane cuts that
floor inside the screen, and a hole shows. The original's near-polygon code
(`SubdivideLevelGeometryPolys`) is still assembly, so its behaviour is not
known.

The clone hides a face only when the near plane cuts it inside the screen
(`View.cut_by_near_plane`). Two conditions must both be true:

- The face is within 0.2 cell of the eye. The corners of the near plane's
  window are 0.183 cell from the eye, with the engine's near plane at 0.1
  and a 16:9 screen.
- The face's plane passes through that window.

In a climb at the level1 wall, this hides the old floor for about 2 ms.
A face that crosses the near plane outside the screen still draws, so the
ball's floor and the walls beside the ball do not vanish (Inferred).

A whole-cube mesh would draw the faces between blocks. Do not use one for
level blocks.

## Not copied

- The speed-up at the start of a roll.
- Look up and look down.
- The "hall of mirrors": in skybox themes the original does not clear the
  screen each frame (Code, `src/disp.c`). The engine clears every frame.
- The long jump, the Bouncy pill, bounce pads and the boost.

## Sources

- https://github.com/dezgeg/kula-world-decomp
- https://wiki.kula.quest/
- https://speeddemosarchive.com/KulaWorld.html
- https://kulaquest.pinkgothic.com/storybehind.html
