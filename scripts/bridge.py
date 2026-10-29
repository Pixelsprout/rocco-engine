#!/usr/bin/env python3
"""A Bridge Driver. See guide/bridge.md for the requests and replies.

As a library:

    from bridge import Bridge
    with Bridge.connect(7878, wait=30) as b:
        b.hello()
        b.step(30, held=["W"])
        pip = b.scene()["scene"]["nodes"][3]["Draw"]
        b.screenshot("pip.png")
        b.quit()

As a CLI, each call connects, sends one request, prints the reply and
disconnects. The port comes from --port or ROCCO_BRIDGE:

    python3 scripts/bridge.py hello
    python3 scripts/bridge.py step 30 --held W --tap Space --mouse 4,0
    python3 scripts/bridge.py step 30 --held-button South --left-stick 0,1
    python3 scripts/bridge.py step --gamepads '[{"slot":1,"held":["Start"]}]'
    python3 scripts/bridge.py scene
    python3 scripts/bridge.py screenshot out.png
    python3 scripts/bridge.py tell town 'hello'
    python3 scripts/bridge.py tell town --file msg.txt
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
import zlib

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

    # gamepads is a list of pad dicts, as guide/bridge.md gives them. With
    # none, no pad is connected.
    def step(self, n=1, held=(), tap=(), mouse=None, gamepads=()):
        req = {"op": "step", "n": n}
        if held:
            req["held"] = list(held)
        if tap:
            req["tap"] = list(tap)
        if mouse is not None:
            req["mouse"] = list(mouse)
        if gamepads:
            req["gamepads"] = list(gamepads)
        return self.request(req)

    def scene(self):
        return self.request({"op": "scene"})

    def tell(self, port, msg):
        return self.request({"op": "tell", "port": port, "msg": msg})

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


def png_chunks(data):
    """Returns the (kind, body) chunks of PNG bytes and checks each CRC."""
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("no PNG signature")
    chunks = []
    at = 8
    while at < len(data):
        (length,) = struct.unpack(">I", data[at : at + 4])
        kind = data[at + 4 : at + 8]
        body = data[at + 8 : at + 8 + length]
        (crc,) = struct.unpack(">I", data[at + 8 + length : at + 12 + length])
        if zlib.crc32(kind + body) != crc:
            raise ValueError(f"bad CRC in {kind!r}")
        chunks.append((kind, body))
        at += 12 + length
    return chunks


def png_rgba(data):
    """Returns (width, height, pixels) of an 8-bit RGBA PNG with no interlace.
    Every filter type is read, so the reader does not assume the host's
    choice of filter 0."""
    chunks = png_chunks(data)
    kinds = [kind for kind, _ in chunks]
    if kinds[0] != b"IHDR" or kinds[-1] != b"IEND":
        raise ValueError(f"bad chunk order {kinds}")
    width, height, depth, color_type, compression, filter_method, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    if (depth, color_type, compression, filter_method, interlace) != (8, 6, 0, 0, 0):
        raise ValueError("not 8-bit RGBA")
    # zlib checks the Adler-32.
    raw = zlib.decompress(b"".join(body for kind, body in chunks if kind == b"IDAT"))
    stride = width * 4
    if len(raw) != (stride + 1) * height:
        raise ValueError("wrong length of rows")
    rows = []
    prev = bytearray(stride)
    for y in range(height):
        line = raw[y * (stride + 1) : (y + 1) * (stride + 1)]
        row = png_unfilter(line[0], bytearray(line[1:]), prev)
        rows.append(bytes(row))
        prev = row
    return width, height, b"".join(rows)


def png_unfilter(kind, row, prev):
    if kind == 0:
        return row
    for i in range(len(row)):
        left = row[i - 4] if i >= 4 else 0
        up = prev[i]
        up_left = prev[i - 4] if i >= 4 else 0
        if kind == 1:
            add = left
        elif kind == 2:
            add = up
        elif kind == 3:
            add = (left + up) // 2
        elif kind == 4:
            p = left + up - up_left
            pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
            add = left if pa <= pb and pa <= pc else (up if pb <= pc else up_left)
        else:
            raise ValueError(f"bad filter type {kind}")
        row[i] = (row[i] + add) & 255
    return row


def png_changed_pixels(path_a, path_b):
    """Returns the count of pixels that differ between two PNG files of one size."""
    with open(path_a, "rb") as f:
        width_a, height_a, a = png_rgba(f.read())
    with open(path_b, "rb") as f:
        width_b, height_b, b = png_rgba(f.read())
    if (width_a, height_a) != (width_b, height_b):
        raise ValueError(f"{path_a} is {width_a}x{height_a} and {path_b} is {width_b}x{height_b}")
    pixels_a = memoryview(a).cast("I")
    pixels_b = memoryview(b).cast("I")
    return sum(1 for x, y in zip(pixels_a, pixels_b) if x != y)


def mouse_arg(text):
    parts = text.split(",")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("the mouse movement is dx,dy, such as 4,-2")
    try:
        return [int(p) if p.strip().lstrip("-").isdigit() else float(p) for p in parts]
    except ValueError:
        raise argparse.ArgumentTypeError("the mouse movement is dx,dy, such as 4,-2") from None


def stick_arg(text):
    parts = text.split(",")
    try:
        if len(parts) == 2:
            return [number(p) for p in parts]
    except ValueError:
        pass
    raise argparse.ArgumentTypeError("a stick is x,y, such as 0,1")


def number(text):
    text = text.strip()
    return int(text) if text.lstrip("-").isdigit() else float(text)


def gamepads_arg(text):
    try:
        pads = json.loads(text)
    except ValueError:
        pads = None
    if not isinstance(pads, list):
        raise argparse.ArgumentTypeError('the gamepads are a JSON list, such as [{"slot":0,"held":["South"]}]')
    return pads


# The pad flags build one pad. --gamepads gives the whole list instead.
def step_gamepads(args):
    if args.gamepads is not None:
        return args.gamepads
    pad = {}
    if args.slot is not None:
        pad["slot"] = args.slot
    if args.held_button:
        pad["held"] = args.held_button
    if args.tap_button:
        pad["tap"] = args.tap_button
    for field in ("left_stick", "right_stick", "left_trigger", "right_trigger"):
        value = getattr(args, field)
        if value is not None:
            pad[field] = value
    return [pad] if pad else []


# newline="" keeps the file's line endings, so the game gets its exact text.
def tell_message(args):
    if args.file is None:
        return args.msg
    with open(args.file, encoding="utf-8", newline="") as f:
        return f.read()


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
    pad = step.add_argument_group("one gamepad", "any of these connects one pad for the steps")
    pad.add_argument("--slot", type=int, help="the pad's slot, 0 to 3 (default: 0)")
    pad.add_argument("--held-button", action="append", default=[], metavar="BUTTON", help="a button held for every step; repeat for more buttons")
    pad.add_argument("--tap-button", action="append", default=[], metavar="BUTTON", help="a button tapped before the first step; repeat for more buttons")
    pad.add_argument("--left-stick", type=stick_arg, metavar="X,Y", help="the left stick for every step, +y up")
    pad.add_argument("--right-stick", type=stick_arg, metavar="X,Y", help="the right stick for every step, +y up")
    pad.add_argument("--left-trigger", type=number, metavar="V", help="the left trigger for every step, 0 to 1")
    pad.add_argument("--right-trigger", type=number, metavar="V", help="the right trigger for every step, 0 to 1")
    step.add_argument("--gamepads", type=gamepads_arg, metavar="JSON", help="the whole gamepads list as JSON, in place of the pad flags")
    ops.add_parser("scene")
    tell = ops.add_parser("tell", help="queue a message for the game's Listen Queries on a port")
    # dest tell_port, as port is the host's --port.
    tell.add_argument("tell_port", metavar="PORT", help="the port the game Listens on")
    tell.add_argument("msg", nargs="?", metavar="MSG", help="the message text")
    tell.add_argument("--file", metavar="PATH", help="send the whole file, read as UTF-8 text, in place of MSG")
    shot = ops.add_parser("screenshot")
    shot.add_argument("path")
    ops.add_parser("quit")
    ops.add_parser("free-port", help="print a free localhost port for ROCCO_BRIDGE")
    args = parser.parse_args(argv)
    if args.op == "tell" and (args.msg is None) == (args.file is None):
        tell.error("give either MSG or --file PATH")
    return args


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
                    b.step(args.n, held=args.held, tap=args.tap, mouse=args.mouse, gamepads=step_gamepads(args))
                elif args.op == "scene":
                    b.scene()
                elif args.op == "screenshot":
                    b.screenshot(args.path)
                elif args.op == "tell":
                    b.tell(args.tell_port, tell_message(args))
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
