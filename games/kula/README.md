# Kula

A clone of Kula World (PS1, 1998) on the rocco engine. A ball rolls over a
grid of blocks. Gravity turns when the ball rolls over an edge. Collect
every key, then roll into the exit.

`SPEC.md` holds the original's numbers and says which of them this clone
copies.

## Run

From this directory:

```sh
roc run main.roc
roc test main.roc
```

The engine loads the meshes in `assets/meshes/` at startup.

## Controls

| Input | Action |
|---|---|
| Up, held | Roll forward, one cell after another |
| Left | Turn 90° left |
| Right | Turn 90° right |
| Space | Jump |
| Escape | Quit |

Up, Left, Right and Space act only when the ball is still. Left, Right and
Space act on the press. Hold Up to keep rolling. Escape quits at any time.
The controls are tank controls: they are relative to the ball, not to the
screen.

## Words

| Word | Meaning |
|---|---|
| Cell | An integer grid position `{ x, y, z }`. One block fills one cell. |
| Axis | A cell with one component of 1 or -1. `up` and `forward` are axes. |
| Pose | `{ cell, up, forward }`. The ball is in `cell` and stands on the block at `cell - up`. |
| Up | The direction away from the face the ball stands on. Gravity points along `-up`. |
| Forward | The direction the ball rolls. It is always at right angles to `up`. |
| Right | `forward × up`. |
| Face | One side of a block that touches an empty cell. Only faces draw. |
| Commit | A move sets the new pose when it starts. The ball then moves to that pose over the time of the move. |
| Open end | A block with no block to its left or right, as the ball sees it. Only an open end lets the ball roll over the edge. |
| Phase | `Playing` or `Won`. |

## Moves

All moves are on the grid. The ball does not start a new move until the
current one ends.

### Roll

The ball tests three cases in this order:

1. **Climb.** A block is in the cell ahead. The ball stays in its cell and
   turns onto that block's face. The new up is the old `-forward`. The new
   forward is the old up. Time: 0.28 s.
2. **Floor.** A block is ahead and one cell down. The ball moves one cell
   forward. Time: 0.26 s.
3. **Edge.** No block is ahead. The ball rolls over the edge onto the side
   of the block it stands on. The new up is the old forward. The new
   forward is the old `-up`. Time: 0.34 s.

The edge roll needs an open end. If a block is to the left or right of the
block the ball stands on, the ball does not move.

### Turn

Left and Right turn the ball 90° about up. The cell does not change.
Time: 0.32 s.

### Jump

A jump always aims two cells ahead, at the same level. Time: 0.54 s.

- If a block is above the ball, or in either of the two cells ahead, the
  jump bounces. The ball does not move.
- If a block is under the cell two ahead, the ball lands there.
- If no block is under the cell two ahead, the ball falls.

A jump never lands on top of the block ahead. To get onto a wall, roll into
it.

### Fall and restart

A fall drops the ball three cells along `-up` over 0.5 s. When the fall
ends, the level restarts: the ball goes back to the start, the keys come
back and the exit closes.

## Keys and the exit

- A key sits on the top face of a block. The ball collects it when a move
  into its cell commits. A collected key disappears.
- The exit is a block. It is open when the ball has collected every key.
  An open exit draws brighter than a closed one.
- When the ball enters the cell above the open exit, the phase changes to
  `Won`. The ball finishes its move and stops. The ball changes colour.
- In `Won`, every input except Escape does nothing.
- A closed exit does nothing. The ball can roll over it.

## Level files

A level is a text file in `levels/`. It holds layers of the grid, bottom
layer first. A blank line separates two layers.

- The layer index is `y`.
- The row index in a layer is `z`. The first row is `z = 0`.
- The column index in a row is `x`.
- Every row in the file must have the same length.

| Character | Meaning |
|---|---|
| `.` | Empty |
| `#` | A block |
| `S` | A block. The ball starts on top of it, facing `-z`. |
| `K` | A block with a key on top |
| `E` | The exit block |

A level needs exactly one `S`. A level that does not parse stops the game at
startup with the parse error.

### Example: level1

`levels/level1.txt` is one column wide. It has two layers:

```text
E        .
#        .
#        .
.        .
#        .
#        K
#        #
K        .
#        .
S        .
```

The left column is layer 0 and the right column is layer 1. In the file,
layer 1 comes after layer 0 and a blank line. The route:

1. Roll from `S` along `-z` over the first key.
2. Climb the wall of layer 1 and roll onto its top.
3. Collect the second key. Roll over the far edge onto the side of the
   block.
4. Climb back onto layer 0.
5. Jump the gap.
6. Roll on to the exit.

## Meshes

The blocks draw as faces, not as whole cubes. The camera can then sit inside
a block, as in the original, and still see the ball. Keys are primitive
cubes.

| File | What it is |
|---|---|
| `assets/meshes/face.glb` | A 1 × 1 quad facing +y, one-sided, with a lighter border |
| `assets/meshes/ball.glb` | A sphere of diameter 1 with eight white and red wedges |

`assets/source/make_meshes.py` builds both files. Run it with Blender from
this directory:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python assets/source/make_meshes.py
```

Commit the script and both `.glb` files. The build does not run Blender.
