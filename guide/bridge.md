---
title: The Bridge
summary: Let a script, a CI test or an agent play a run over a localhost socket. Inject Input for N steps, read the Scene as JSON and save a screenshot.
order: 12
---

# The Bridge

A person plays a game with the keyboard and the mouse. A script, a CI test
or an agent cannot. It cannot press W, it cannot read where the player
stands, and it cannot see the result of 30 steps. A run on the real clock
also differs each time, so a check that waits a second and looks gives a
different answer on a slow machine.

The Bridge gives them a way in. The host listens on a localhost socket,
and one outside process, the Driver, sends it requests. The Driver gives
`step` its Input, asks for fixed steps, reads the Scene as JSON and saves a
screenshot. Between requests the run pauses, so the same requests always
give the same Scenes.

The game does not know that the Bridge exists. It gets the same calls with
the same kind of values, and nothing in the Vocabulary names the Bridge.
You do not change a game to drive it.

## A first session

Start tutorial chapter 3 with the Bridge on port 7878:

```sh
cd examples/tutorial/03-moving
ROCCO_BRIDGE=7878 roc main.roc
```

The window opens and shows Pip at the first `view`. Nothing moves: the run
waits for a Driver. In a second terminal, at the repository root, walk Pip
forward for a quarter of a second with `scripts/bridge.py`:

```sh
$ export ROCCO_BRIDGE=7878
$ python3 scripts/bridge.py hello
{"ok":true,"protocol":1,"step_hz":120,"steps":0,"headless":false}
$ python3 scripts/bridge.py step 30 --held W
{"ok":true,"steps":30,"commands":[],"alloc":{"step":30,"allocs":3,"deallocs":3,"reallocs":0,"live":3,"step_us":1.1,"view_us":0.9}}
$ python3 scripts/bridge.py scene
{"ok":true,"steps":30,"scene":{"camera":{...},"nodes":[{"Light":{...}},{"Light":{...}},{"Draw":{"id":1,"mesh":1,...}},{"Draw":{"id":2,"mesh":4,"pos":{"x":0,"y":0,"z":-0.62499994},...}}],...},"results":{...}}
$ python3 scripts/bridge.py screenshot pip.png
{"ok":true,"path":".../pip.png","physical":[1920,1080],"logical":[960,540]}
$ python3 scripts/bridge.py quit
{"ok":true}
```

These are the replies from a real run on a Mac. The `scene` reply is
trimmed: the full reply is in the [scene](#scene) section. The `screenshot`
reply gives the full path of `pip.png`, trimmed here to `...`. The `step_us`
and `view_us` times differ from run to run.

Pip's Draw is the one with mesh 4. It starts at z 0, and after 30 steps
with W held it is at z -0.625: W walks Pip along -z at 2.5 units a second,
and the game runs 120 steps a second. The window shows Pip where `scene`
says, and `pip.png` holds the same image. After `quit`, the game exits with
code 0.

Each `bridge.py` call connects, sends one request, prints the reply and
disconnects. So an agent can drive a run across separate shell commands,
and the run keeps its place between them.

### From a Python script

A Python script can import `bridge.py` instead. `Bridge` has one method for
each op, and each one returns the reply as a dict:

```python
import sys
sys.path.insert(0, "scripts")
from bridge import Bridge

def draw(reply, id):
    nodes = reply["scene"]["nodes"]
    return next(n["Draw"] for n in nodes if "Draw" in n and n["Draw"]["id"] == id)

with Bridge.connect(7878, wait=30) as b:
    b.hello()
    before = draw(b.scene(), 2)["pos"]["z"]
    b.step(30, held=["W"])
    after = draw(b.scene(), 2)["pos"]["z"]
    print(f"Pip walked from z {before} to z {after}")
    b.screenshot("pip.png")
    b.quit()
```

Against a fresh run of chapter 3, this prints
`Pip walked from z 0 to z -0.62499994`. A reply with `"ok": false` raises
`BridgeError`, and its `reply` holds the whole reply. `wait=30` keeps
trying to connect for 30 seconds while the game starts.

`scripts/bridge_check.py` is the same session with checks. It starts the
game itself on a free port, and CI runs it on Linux, macOS and Windows.
It also walks Pip into a pickup in chapter 8 and checks that the `step`
reply holds the `Play` of the blip.

### Screenshots of any example

`scripts/screenshot.sh <game> <out.png> [steps]` saves one frame of an
example in `examples/`, such as `tutorial/04-lights`. It starts the built
game with the Bridge on a free port, runs the steps with no Input, saves the
screenshot and quits. With no step count, it runs one second of steps. It
prints the `screenshot` reply.

## Requests and replies

The Driver and the host talk in JSON Lines: one JSON object on each line,
in UTF-8, ending with a newline. Each request has an `op`. Each reply has
`ok`, and a reply to a failed request also has an `error`. The host answers
the requests in order, one reply for each:

```
{"op":"jump"}
{"ok":false,"error":"unknown op \"jump\""}
```

A bad request gets an error reply, and the connection stays open. A
request with a bad field changes nothing in the run.

You can try it by hand with `nc`:

```sh
nc 127.0.0.1 7878
```

Type a request and press Return to see the reply. The examples in this
section and the next ones show the request on the first line and the reply
on the second. They come from real runs of the tutorial on a Mac.

## hello

`hello` tells the Driver about the run:

```
{"op":"hello"}
{"ok":true,"protocol":1,"step_hz":120,"steps":0,"headless":false}
```

`protocol` is the version of the requests and replies. It goes up when a
reply changes shape, so a Driver can check it first. `step_hz` is the step
rate from the game's [Launch](launch.md), and `steps` is the count of fixed
steps the run has taken. `headless` is `true` in a Headless run.

## step

`step` runs fixed steps with the Input you give it, and replies once after
the last one:

```
{"op":"step","n":30,"held":["W"],"tap":["Space"],"mouse":[4,-2]}
{"ok":true,"steps":30,"commands":[],"alloc":{"step":30,"allocs":3,"deallocs":3,"reallocs":0,"live":3,"step_us":1.2,"view_us":0.9}}
```

`n` is the number of steps, 1 when you leave it out. `held` lists the keys
that are down for every step. `tap` lists keys pressed and let go before
the first step. `mouse` is the mouse movement `[dx, dy]` of the first step.
[The Input rules](#the-input-rules) say how the host turns these fields
into the Input that `step` gets.

The keys are the names from `pf.Key`, such as `"W"`, `"Space"`,
`"LeftShift"` and `"Num0"`. A name that `pf.Key` does not have fails the
request, and no step runs:

```
{"op":"step","held":["Jump"]}
{"ok":false,"error":"unknown Key \"Jump\" in \"held\""}
```

The reply gives the step count after the last step, the Commands the game
returned in these steps, and the Roc heap counts of the last step. The
`alloc` fields are the same as on the `ROCCO_ALLOC_REPORT` line in
[Running and debugging](running.md).

A Command is written with its Vocabulary tag. A tag with a payload is an
object with one key, and a tag with no payload is a string. So `Quit` is
`"Quit"`, `Unload("pip")` is `{"Unload":"pip"}`, a `Load` is
`{"Load":{"pack":"pip","assets":["pip"]}}`, and `Sound.play(3)` is
`{"Play":{"sound":3,"gain":1,"pitch":1,"at":"Here"}}`.

If the game returns `Quit`, the host stops at that step. It sends the
reply, with `steps` at the step that quit, and then ends the run. Chapter 6
quits on Escape, so a tap of Escape stops a `step` of 10 after one step:

```
{"op":"step","n":10,"tap":["Escape"]}
{"ok":true,"steps":1,"commands":["Quit"],"alloc":{"step":1,"allocs":12,"deallocs":10,"reallocs":6,"live":4,"step_us":65.6,"view_us":93.8}}
```

The host runs one step for each frame. In a window you see each step, and
the steps run as fast as the window draws, not at `step_hz`. While they
run, the host reads no other request. It reads the next one after it has
sent the reply.

## scene

`scene` replies with the Scene of the last step, the one the window shows,
and the QueryResults that the next `step` gives the game. This is the full
reply from chapter 3 after the 30 steps of the `step` example above. The
host sends it on one line, and it is split into lines here:

```
{"op":"scene"}
{"ok":true,"steps":30,
 "scene":{"camera":{"eye":{"x":0,"y":3.6,"z":4.8},"target":{"x":0,"y":0,"z":0.3},"up":{"x":0,"y":1,"z":0},"fov_y":1.047},
  "nodes":[{"Light":{"Ambient":{"r":0.3,"g":0.3,"b":0.3}}},
   {"Light":{"Directional":{"dir":{"x":-0.4,"y":-0.8,"z":-0.45},"color":{"r":4,"g":4,"b":4},"shadow":false}}},
   {"Draw":{"id":1,"mesh":1,"pos":{"x":0,"y":-0.1,"z":0},"scale":{"x":6,"y":0.2,"z":6},"rot":{"x":0,"y":0,"z":0,"w":1},"scale_rot":{"x":0,"y":0,"z":0,"w":1},"tint":{"r":0.12,"g":0.25,"b":0.1}}},
   {"Draw":{"id":2,"mesh":4,"pos":{"x":0,"y":0,"z":-0.62499994},"scale":{"x":1,"y":1,"z":1},"rot":{"x":0,"y":1,"z":0,"w":-4.3711392e-08},"scale_rot":{"x":0,"y":0,"z":0,"w":1},"tint":{"r":1,"g":1,"b":1}}}],
  "cursor":"Free","sky":0,"ui":[],"queries":[],"loops":[]},
 "results":{"contacts":[],"rays":[],"overlaps":[]}}
```

The fields and the tags have the names you use in the game, from the
Vocabulary: `scale_rot`, `{"Light":{"Directional":{...}}}`, `"Free"`. Tags
follow the same rule as the Commands in `step`. Each number is the
shortest one that reads back as the same `F32`, so Pip's z is
`-0.62499994`, not `-0.625`.

The `nodes` field mirrors the tree of Nodes that the game wrote, with each
Pose local to its Group, as the game wrote it. A Group is an object with
its `id`, its `pose` and its `children`, and each child is a Node in the
same form:

```
{"Group":{"id":0,"pose":{"pos":{"x":1,"y":0,"z":2},"rot":{"x":0,"y":0.38268343,"z":0,"w":0.9238795}},
  "children":[{"Draw":{"id":0,...}},{"Collider":{"id":0,...}},{"Draw":{"id":40,...}}]}}
```

The leaves are `{"Draw":{...}}`, `{"Light":{...}}` and
`{"Collider":{...}}`. The reply does not give world Poses. To find where a
child is in the world, compose the Poses down the tree yourself, with the
rule of `Pose.compose` in `packages/linalg`: the world `pos` is the
parent's `pos` plus the child's `pos` turned by the parent's `rot`, and the
world `rot` is the parent's `rot` times the child's `rot`. Queries and
`results` are in world space already.

A Scene with Colliders and Queries gives `results` rows. In chapter 6, Pip
touches the pickup with id 12 after 27 steps with W held. This reply is
trimmed to the `queries` and the `results`:

```
{"op":"step","n":27,"held":["W"]}
{"ok":true,"steps":27,"commands":[],"alloc":{"step":27,"allocs":12,"deallocs":11,"reallocs":6,"live":5,"step_us":5.1,"view_us":4.0}}
{"op":"scene"}
{"ok":true,"steps":27,"scene":{...,"queries":[{"ContactsOf":2}]},"results":{"contacts":[{"a":2,"b":12,"normal":{"x":0.82404196,"y":0,"z":-0.5665287},"depth":0.00729388}],"rays":[],"overlaps":[]}}
```

The game sees this Contact in its next step, and the pickup's Draw is then
gone from `nodes`.

The `ui` field mirrors the UI tree that the game wrote. A `Box` is an
object with its `config` and its `children`, and each child is a `Box` or a
`Text` in the same form. In chapter 7, after one step, the HUD is two root
Boxes with one Text each. This reply is trimmed to the `ui`, and split into
lines:

```
{"op":"scene"}
{"ok":true,"steps":1,"scene":{...,"ui":[
  {"Box":{"config":{"width":{"Fit":{"min":0,"max":0}},"height":{"Fit":{"min":0,"max":0}},"pad":{"left":8,"right":8,"top":8,"bottom":8},"gap":0,"direction":"Row","child_align":{"x":"Start","y":"Start"},"background":{"r":0,"g":0,"b":0,"a":0.5},"radius":8,"floating":{"Float":{"attach":"LeftTop","offset":{"x":16,"y":16}}}},
          "children":[{"Text":{"str":"Pickups: 0 / 5","size":24,"color":{"r":1,"g":1,"b":1,"a":1},"wrap":"None"}}]}},
  {"Box":{"config":{...,"floating":{"Float":{"attach":"CenterBottom","offset":{"x":0,"y":-16}}}},
          "children":[{"Text":{"str":"Collect every pickup.","size":24,"color":{"r":1,"g":1,"b":1,"a":1},"wrap":"None"}}]}}],...},...}
```

To find a string in the HUD, walk `children` down from each root, as a Roc
test matches the tree with a pattern.

## screenshot

`screenshot` saves the last frame the window drew as a PNG:

```
{"op":"screenshot","path":"pip.png"}
{"ok":true,"path":"pip.png","physical":[1920,1080],"logical":[960,540]}
```

The host writes the file itself, so a relative `path` is relative to the
folder the game runs in. This example wrote
`examples/tutorial/03-moving/pip.png`. Send an absolute path when the
Driver runs somewhere else. `bridge.py` does this for you. The reply gives
the path back as you sent it.

The image has the window's physical pixels. `logical` is the size in the
window's own units, the size in the Launch. On a high-DPI display,
`physical` is larger: the two sizes differ by the display's scale, 2 on
most Mac screens and 1 under xvfb and on the CI runners. The PNG is opaque,
as the window is.

While no steps are owed, the window draws the Scene that `scene` returns,
so the screenshot shows it too. The host draws the first frame before it
reads any request, so a `screenshot` straight after `hello` shows the first
`view`.

A path the host cannot write, such as one in a missing folder, gets an
error, and the run goes on:

```
{"op":"screenshot","path":"/no/such/folder/pip.png"}
{"ok":false,"error":"the host cannot write \"/no/such/folder/pip.png\": file does not exist"}
```

A Headless run draws nothing, so it replies with an error there:

```
{"op":"screenshot","path":"/tmp/x.png"}
{"ok":false,"error":"a Headless run draws no image to screenshot"}
```

## quit

`quit` ends the run as a `Quit` Command does:

```
{"op":"quit"}
{"ok":true}
```

The host sends the reply, then exits with code 0. It does not answer the
requests that come after `quit`.

## The Input rules

While the Bridge is on, `step` gets its Input from the Driver only. The
real keyboard and mouse do not reach the game, so a run does not depend on
where the mouse is. The debug camera still reads them, so you can fly it
with `ROCCO_DEBUG_CAMERA=1` while a Driver plays.

The host builds the Input of each step from the `step` request:

- **Held**: the keys in `held`, in every step of the request. A field you
  leave out means none, so a `step` with no `held` lets go of every key.
- **Pressed**: a key in `held` that was not held in the step before, as
  with a real keyboard. A key in `tap` is also Pressed, but only in the
  first step, and it is not Held.
- **Mouse**: the `mouse` movement, in the first step only. The other steps
  get no movement.

Pressed follows the steps, not the requests. If one request holds W and the
next one holds W too, W is Pressed only in the first step of the first
request. If a request in between leaves `held` out, W is Pressed again.

The run remembers the held keys, not the Driver. A Driver that connects
after another one left gets the held keys of the last step that ran. So if
the last `step` held W, and the new Driver's first `step` holds W too, W is
not Pressed. To press it, send a `step` without W first, or put W in `tap`.
This is also why it does not matter that each `bridge.py` call connects
again.

So to walk, put the key in `held`. To jump once, put Space in `tap`, or
start a `held` of Space after a step where it was not held.

## The lifecycle

1. The host reads `ROCCO_BRIDGE` and opens its socket on `127.0.0.1`
   before it calls `launch`. If another process already uses the port, the
   host prints the error and exits with code 1. It does not start a normal
   run. The error looks like
   `ROCCO_BRIDGE=7878: the host cannot listen on 127.0.0.1:7878: Address_In_Use`.
2. The host runs `launch` and `init`, opens the window and draws the first
   `view`.
3. The run waits for a Driver. It is Lockstep that pauses: each frame runs
   one fixed step while the Driver is owed steps, and no step otherwise.
   The window keeps drawing while the run waits, but no faster than about
   60 frames a second.
4. A Driver connects and sends requests. The host answers them one at a
   time, between frames.
5. When the Driver disconnects, the run stays where it is, and the host
   waits for the next Driver. If the Driver leaves while a `step` runs, the
   host runs the rest of the steps, and nobody gets the reply.
6. The run ends on `quit`, on a `Quit` from the game or when you close the
   window. The game exits with code 0.

The host talks to one Driver at a time. A second Driver can connect, but
the host answers it only after the first one has gone.

In Headless the host blocks on the socket while no steps are owed, so it
needs no `ROCCO_EXIT_AFTER_FRAMES`:

```sh
ROCCO_HEADLESS=1 ROCCO_BRIDGE=7878 roc main.roc
```

A Headless run takes one frame for each step, and draws nothing.

## Limits

- The host listens on `127.0.0.1` only. A Driver on another machine cannot
  connect.
- The Driver controls the host, not the game. It cannot send the game a
  message, and the game cannot send one to the Driver.
- `step` runs at least one step. To read the Scene without a step, send
  `scene`.
- A request longer than 1 MiB gets the error
  `the request is longer than 1 MiB`.
- A screenshot's size depends on the display's scale. Compare `logical`
  with the Launch window size, and the PNG with `physical`.
- With `ROCCO_EXIT_AFTER_FRAMES`, a windowed Bridge run still stops after
  that many frames, and it counts the frames where it waits. If the frames
  run out during a `step`, the host sends the reply with the steps it ran,
  then ends the run. Leave it unset when a Driver ends the run.
- A Scene whose `cursor` is `Locked` still locks the real mouse in the
  window.
- The ops `tell`, `ask` and `listen` are kept for a later version. Today
  they reply `{"ok":false,"error":"not yet"}`.

## Reference

### Requests

| Op | Fields | Reply fields |
|---|---|---|
| `hello` | none | `protocol`, `step_hz`, `steps`, `headless` |
| `step` | `n`, `held`, `tap`, `mouse`, each optional | `steps`, `commands`, `alloc` |
| `scene` | none | `steps`, `scene`, `results` |
| `screenshot` | `path` | `path`, `physical`, `logical` |
| `quit` | none | none |

### Fields

| Field | Means |
|---|---|
| `protocol` | The version of the requests and replies. Today it is 1. |
| `step_hz` | The fixed steps per second, from the game's Launch. |
| `steps` | The fixed steps that the run has taken. |
| `headless` | `true` in a Headless run, `false` with a window. |
| `n` | How many steps to run, a whole number of 1 or more. The default is 1. |
| `held` | A list of Key names, held for every step. |
| `tap` | A list of Key names, Pressed but not Held, in the first step only. |
| `mouse` | `[dx, dy]`, the mouse movement in the first step only. |
| `commands` | The Commands the game returned in the steps, in order. |
| `alloc` | `step`, `allocs`, `deallocs`, `reallocs`, `live`, `step_us` and `view_us` of the last step. |
| `scene` | The Scene of the last step: `camera`, `nodes`, `cursor`, `sky`, `ui`, `queries` and `loops`. `nodes` mirrors the tree with local Poses. |
| `results` | The QueryResults that the next step gets: `contacts`, `rays` and `overlaps`. |
| `path` | The PNG file. The host writes it, from the game's folder. |
| `physical` | `[width, height]` of the PNG, in pixels. |
| `logical` | `[width, height]` in the window's units. |

### Values

| Vocabulary value | JSON |
|---|---|
| `Vec3` | `{"x":0,"y":1,"z":0}` |
| `Quat` | `{"x":0,"y":0,"z":0,"w":1}` |
| `Rgb`, `Rgba` | `{"r":1,"g":1,"b":1}`, `{"r":1,"g":1,"b":1,"a":1}` |
| `F32` | The shortest number that reads back as the same `F32`. NaN and infinity are `null`. |
| An id, a mesh id | A whole number. |
| A tag with a payload | An object with one key: `{"Sphere":0.25}`, `{"ContactsOf":2}`. |
| A tag with no payload | A string: `"Quit"`, `"Free"`, `"Locked"`. |
| `Element` | `{"Box":{"config":{...},"children":[...]}}` or `{"Text":{...}}`. A Box's two payloads get the names `config` and `children`. |

### Errors

| Error | When |
|---|---|
| `unknown op "<name>"` | The `op` is not one of the ops. |
| `not yet` | The op is `tell`, `ask` or `listen`. |
| `the request is not JSON: <reason>` | The line is not JSON. |
| `the request is not a JSON object` | The line is JSON, but not an object. |
| `the request has no "op" string` | The object has no `op`, or it is not a string. |
| `the request is longer than 1 MiB` | The line is too long. |
| `"n" must be a whole number of 1 or more` | `n` is 0, negative or not a whole number. |
| `"held" must be a list of Key names` | `held` or `tap` is not a list of strings. The error names the field. |
| `unknown Key "<name>" in "held"` | A name is not in `pf.Key`. The error names the field. |
| `"mouse" must be [dx, dy]` | `mouse` is not a list of two numbers. |
| `"path" must be a file path` | `path` is missing, empty or not a string. |
| `a Headless run draws no image to screenshot` | A `screenshot` in Headless. |
| `the host cannot write "<path>": <reason>` | The host cannot write the PNG. |

### bridge.py

| Command | Sends |
|---|---|
| `bridge.py hello` | `hello` |
| `bridge.py step [N] [--held KEY]... [--tap KEY]... [--mouse DX,DY]` | `step`. Give `--held` and `--tap` once for each key. |
| `bridge.py scene` | `scene` |
| `bridge.py screenshot PATH` | `screenshot`, with `PATH` made absolute from the folder you run it in. |
| `bridge.py quit` | `quit` |
| `bridge.py free-port` | Nothing. It prints a free localhost port for `ROCCO_BRIDGE`. |

`bridge.py` reads the port from `--port P` or from `ROCCO_BRIDGE`.
`--wait S` keeps trying to connect for S seconds. It prints the reply as
the host sent it. It exits with 0 on `"ok": true`, with 1 on
`"ok": false`, and with 2 when it cannot talk to the host. So a shell
script with `set -e` stops at the first failed request. It needs Python 3
and nothing else.
