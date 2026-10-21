---
title: The Bridge
summary: Let a script, a CI test or an agent drive a run over a localhost socket, and say hello and quit.
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

## quit

`quit` replies `{"ok":true}`, then ends the run as a `Quit` Command does.
The host exits with code 0. The host does not answer requests that come
after `quit`.

## Names for later

The ops `tell`, `ask` and `listen` are kept for a later version. Today they
reply `{"ok":false,"error":"not yet"}`.
