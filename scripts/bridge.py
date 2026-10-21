#!/usr/bin/env python3
"""A Bridge Driver. See guide/bridge.md for the requests and replies.

As a library:

    from bridge import Bridge
    with Bridge.connect(7878, wait=30) as b:
        b.hello()
        b.step(30, held=["W"])
        pip = b.scene()["scene"]["draws"][1]
        b.screenshot("pip.png")
        b.quit()

As a CLI, each call connects, sends one request, prints the reply and
disconnects. The port comes from --port or ROCCO_BRIDGE:

    python3 scripts/bridge.py hello
    python3 scripts/bridge.py step 30 --held W --tap Space --mouse 4,0
    python3 scripts/bridge.py scene
    python3 scripts/bridge.py screenshot out.png
    python3 scripts/bridge.py quit
    python3 scripts/bridge.py free-port

The CLI exits with 1 on an "ok": false reply and with 2 when it cannot talk
to the host. Python standard library only.
"""

import argparse
import json
import os
import socket
import struct
import sys
import time

PORT_ENV = "ROCCO_BRIDGE"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class BridgeError(Exception):
    """The host replied "ok": false. reply holds the whole reply."""

    def __init__(self, reply):
        super().__init__(reply.get("error", "the host replied ok: false"))
        self.reply = reply


class Bridge:
    def __init__(self, sock):
        self.sock = sock
        self.reader = sock.makefile("rb")
        # The last reply as the host sent it, for the CLI to print.
        self.last_line = ""

    # The host opens its listener before the window, but a Driver that starts
    # with the game can still dial first, so connect retries until wait ends.
    # With process (a subprocess.Popen), it stops early when the game exits.
    @classmethod
    def connect(cls, port, wait=0.0, timeout=300.0, process=None, host="127.0.0.1"):
        deadline = time.monotonic() + wait
        while True:
            try:
                sock = socket.create_connection((host, port), timeout=timeout)
                return cls(sock)
            except OSError as err:
                if process is not None and process.poll() is not None:
                    raise ConnectionError(f"the game exited with code {process.returncode} before the Bridge connected") from err
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.1)

    def close(self):
        self.reader.close()
        self.sock.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def request(self, req):
        """Sends one request and returns the reply. Raises BridgeError on "ok": false."""
        self.sock.sendall(json.dumps(req, separators=(",", ":")).encode() + b"\n")
        line = self.reader.readline()
        if not line:
            raise ConnectionError(f"the host closed the connection before it replied to {req.get('op')!r}")
        self.last_line = line.decode().rstrip("\r\n")
        reply = json.loads(self.last_line)
        if not reply.get("ok"):
            raise BridgeError(reply)
        return reply

    def hello(self):
        return self.request({"op": "hello"})

    def step(self, n=1, held=(), tap=(), mouse=None):
        req = {"op": "step", "n": n}
        if held:
            req["held"] = list(held)
        if tap:
            req["tap"] = list(tap)
        if mouse is not None:
            req["mouse"] = list(mouse)
        return self.request(req)

    def scene(self):
        return self.request({"op": "scene"})

    # The host writes the file from the game's folder, so the path is made
    # absolute here, against the Driver's working directory.
    def screenshot(self, path):
        return self.request({"op": "screenshot", "path": os.path.abspath(path)})

    def quit(self):
        return self.request({"op": "quit"})


# Another process can take the port before the game opens it. That is rare
# enough for scripts and CI.
def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def png_size(path):
    """Returns [width, height] from the IHDR chunk of a PNG file."""
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != PNG_SIGNATURE or head[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a PNG")
    width, height = struct.unpack(">II", head[16:24])
    return [width, height]


def mouse_arg(text):
    parts = text.split(",")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("the mouse movement is dx,dy, such as 4,-2")
    try:
        return [int(p) if p.strip().lstrip("-").isdigit() else float(p) for p in parts]
    except ValueError:
        raise argparse.ArgumentTypeError("the mouse movement is dx,dy, such as 4,-2") from None


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Send one Bridge request and print the reply.")
    parser.add_argument("--port", type=int, help=f"the host's port (default: ${PORT_ENV})")
    parser.add_argument("--wait", type=float, default=0.0, help="seconds to keep trying to connect (default: 0)")
    ops = parser.add_subparsers(dest="op", required=True)
    ops.add_parser("hello")
    step = ops.add_parser("step")
    step.add_argument("n", type=int, nargs="?", default=1)
    step.add_argument("--held", action="append", default=[], metavar="KEY", help="a key held for every step; repeat for more keys")
    step.add_argument("--tap", action="append", default=[], metavar="KEY", help="a key tapped before the first step; repeat for more keys")
    step.add_argument("--mouse", type=mouse_arg, metavar="DX,DY", help="the mouse movement in the first step")
    ops.add_parser("scene")
    shot = ops.add_parser("screenshot")
    shot.add_argument("path")
    ops.add_parser("quit")
    ops.add_parser("free-port", help="print a free localhost port for ROCCO_BRIDGE")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    if args.op == "free-port":
        print(free_port())
        return 0
    port = args.port
    if port is None:
        value = os.environ.get(PORT_ENV, "")
        if not value.isdigit():
            print(f"bridge.py: give --port or set {PORT_ENV}", file=sys.stderr)
            return 2
        port = int(value)
    try:
        with Bridge.connect(port, wait=args.wait) as b:
            try:
                if args.op == "hello":
                    b.hello()
                elif args.op == "step":
                    b.step(args.n, held=args.held, tap=args.tap, mouse=args.mouse)
                elif args.op == "scene":
                    b.scene()
                elif args.op == "screenshot":
                    b.screenshot(args.path)
                elif args.op == "quit":
                    b.quit()
            except BridgeError:
                print(b.last_line)
                return 1
            print(b.last_line)
            return 0
    except (OSError, ValueError) as err:
        print(f"bridge.py: cannot talk to the host on 127.0.0.1:{port}: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
