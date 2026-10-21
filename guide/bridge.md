---
title: The Bridge
summary: Let a script, a CI test or an agent drive a run over a localhost socket. Say hello, run steps with your own Input, and quit.
order: 11
---

# The Bridge

A person plays a game with the keyboard and the mouse. A script, a CI test
or an agent cannot. The Bridge gives them a way in: the host listens on a
localhost socket, and one outside process, the Driver, sends it requests.
The Driver asks for fixed steps, reads what the host sees and ends the run.

The game does not know that the Bridge exists. It gets the same calls with
the same values, and nothing in the Vocabulary names the Bridge.

## Turn it on

Set `ROCCO_BRIDGE` to a port:

```sh
ROCCO_BRIDGE=7878 roc main.roc
```

The host runs `launch` and `init`, opens the window and shows the first
`view`. Then it waits for a Driver on `127.0.0.1:7878`. It listens only on
the local machine, and it talks to one Driver at a time. When the Driver
disconnects, the host waits for the next one.

A Bridge run is Lockstep that pauses. Each frame runs one fixed step while
the Driver has asked for steps, and no step while it has not. The window
keeps drawing, so it shows where the run has stopped. The same requests
always give the same run.

The Bridge also works in Headless. There the host blocks on the socket
while the Driver has asked for no steps, so it does not need
`ROCCO_EXIT_AFTER_FRAMES`:

```sh
ROCCO_HEADLESS=1 ROCCO_BRIDGE=7878 roc main.roc
```

If another process already uses the port, the host prints the error and
exits with code 1. It does not start a normal run.

## Requests and replies

The Driver and the host talk in JSON Lines: one JSON object on each line.
Each request has an `op`. Each reply has `ok`, and a reply to a failed
request also has an `error`:

```
{"op":"jump"}
{"ok":false,"error":"unknown op \"jump\""}
```

A bad request gets an error reply, and the connection stays open.

You can try it by hand with `nc`:

```sh
nc 127.0.0.1 7878
```

Type a request and press Return to see the reply.

## hello

`hello` tells the Driver about the run:

```
{"op":"hello"}
{"ok":true,"protocol":1,"step_hz":120,"steps":0,"headless":false}
```

| Field | Means |
|---|---|
| `protocol` | The version of the requests and replies. It changes when a reply changes shape. |
| `step_hz` | The fixed steps per second, from the game's Launch. |
| `steps` | The fixed steps that the run has taken. |
| `headless` | `true` in a Headless run, `false` with a window. |

## step

`step` runs fixed steps with the Input you give it, then replies once
after the last one:

```
{"op":"step","n":30,"held":["W"],"tap":["Space"],"mouse":[4,-2]}
{"ok":true,"steps":30,"commands":[],"alloc":{"step":30,"allocs":3,"deallocs":3,"reallocs":0,"live":3,"step_us":12.5,"view_us":5.5}}
```

The host runs one step per frame, so the window shows each one. While the
steps run, the host answers no other request. It reads the next one after
it has sent the reply.

| Field | Means |
|---|---|
| `n` | How many steps to run, 1 or more. Without it, the host runs 1. |
| `held` | Keys held down for every step. |
| `tap` | Keys pressed and let go before the first step. They are Pressed but not Held, in the first step only. |
| `mouse` | The mouse movement `[dx, dy]`, in the first step only. |

The keys are the names from `pf.Key`, such as `"W"`, `"Space"`,
`"LeftShift"` and `"Num0"`. A name that `pf.Key` does not have fails the
request, and no step runs:

```
{"op":"step","held":["Jump"]}
{"ok":false,"error":"unknown Key \"Jump\" in \"held\""}
```

A field you leave out means none: no keys held, no taps, no mouse
movement. So a `step` with no `held` lets go of every key.

Pressed works as it does with a real keyboard. A key is Pressed in the
first step where it is held and was not held in the step before. If one
request holds `W` and the next one holds `W` too, `W` is Pressed only in
the first step of the first request. If a request in between leaves `held`
out, `W` is Pressed again.

While the Bridge is on, `step` gets its Input from the Driver only. The
real keyboard and mouse do not reach the game. The debug camera still
reads them, so you can fly it while a Driver plays.

The reply has these fields:

| Field | Means |
|---|---|
| `steps` | The fixed steps that the run has taken, after this request. |
| `commands` | The Commands the game returned in these steps, in order. |
| `alloc` | The Roc heap counts of the last step, the same fields as the `ROCCO_ALLOC_REPORT` line in [Running and debugging](running.md). |

A Command is written with its Vocabulary tag. A tag with a payload is an
object with one key, and a tag with no payload is a string:

```
["Quit", {"Load":{"pack":"level1","assets":["pip","rock"]}}, {"Unload":"level1"}]
```

If the game returns `Quit`, the host stops at that step. It sends the
reply, with `steps` at the step that quit, and then ends the run.

## scene

`scene` replies with the Scene of the last step, the one the window shows,
and the QueryResults that the next `step` gives the game. This reply is
from tutorial chapter 3 after 60 steps with `W` held. The host sends it on
one line:

```
{"op":"scene"}
{"ok":true,"steps":60,
 "scene":{"camera":{"eye":{"x":0,"y":3.6,"z":4.8},"target":{"x":0,"y":0,"z":0.3},"up":{"x":0,"y":1,"z":0},"fov_y":1.047},
  "draws":[{"id":1,"mesh":1,"pos":{"x":0,"y":-0.1,"z":0},"scale":{"x":6,"y":0.2,"z":6},"rot":{"x":0,"y":0,"z":0,"w":1},"scale_rot":{"x":0,"y":0,"z":0,"w":1},"tint":{"r":0.12,"g":0.25,"b":0.1}},
   {"id":2,"mesh":4,"pos":{"x":0,"y":0,"z":-1.25},"scale":{"x":1,"y":1,"z":1},"rot":{"x":0,"y":1,"z":0,"w":-4.3711392e-08},"scale_rot":{"x":0,"y":0,"z":0,"w":1},"tint":{"r":1,"g":1,"b":1}}],
  "colliders":[],
  "lights":[{"Ambient":{"r":0.3,"g":0.3,"b":0.3}},{"Directional":{"dir":{"x":-0.4,"y":-0.8,"z":-0.45},"color":{"r":4,"g":4,"b":4},"shadow":false}}],
  "cursor":"Free","sky":0,"ui":[],"queries":[]},
 "results":{"contacts":[],"rays":[],"overlaps":[]}}
```

`steps` is the fixed steps that the run has taken, as in `hello`. The
fields and the tags in `scene` and `results` have the names you use in the
game, from the Vocabulary: `draws[].scale_rot`, `{"Sphere":0.5}`,
`{"Open":{...}}`, `"Close"`. Tags follow the same rule as the Commands in
`step`. Each number is the shortest one that reads back as the same `F32`.
A NaN or an infinity is `null`, because JSON has no word for them.

While the Driver has asked for no steps, the window draws this Scene as it
is, so a screenshot shows what `scene` returns.

## quit

`quit` replies `{"ok":true}`, then ends the run as a `Quit` Command does.
The host exits with code 0. The host does not answer requests that come
after `quit`.

## Names for later

The ops `tell`, `ask` and `listen` are kept for a later version. Today they
reply `{"ok":false,"error":"not yet"}`.
