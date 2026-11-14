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
    python3 scripts/bridge.py step --pointer 884,36 --tap-mouse Left
    python3 scripts/bridge.py --devices step 600   # the real devices reach the game during these steps
    python3 scripts/bridge.py scene
    python3 scripts/bridge.py screenshot out.png
    python3 scripts/bridge.py tell town 'hello'
    python3 scripts/bridge.py tell town --file msg.txt
    python3 scripts/bridge.py quit
    python3 scripts/bridge.py free-port
    python3 scripts/bridge.py relay --port 7878

relay serves a web run: the page connects to it with ?bridge=7878, and the
other calls then reach the page through it. It runs until the quit reply.

The CLI exits with 1 on an "ok": false reply and with 2 when it cannot talk
to the host. Python standard library only.
"""

import argparse
import base64
import hashlib
import json
import os
import selectors
import socket
import struct
import sys
import time
import urllib.parse
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

    # With devices, the person's real keyboard, mouse, pointer and pads reach
    # the game with each step's Input, while this connection lasts.
    def hello(self, devices=False):
        req = {"op": "hello"}
        if devices:
            req["devices"] = True
        return self.request(req)

    # gamepads is a list of pad dicts, as guide/bridge.md gives them. With
    # none, no pad is connected. pointer is one dict, sent as it is. With
    # none, the pointer is outside the window.
    def step(self, n=1, held=(), tap=(), mouse=None, gamepads=(), pointer=None):
        req = {"op": "step", "n": n}
        if held:
            req["held"] = list(held)
        if tap:
            req["tap"] = list(tap)
        if mouse is not None:
            req["mouse"] = list(mouse)
        if gamepads:
            req["gamepads"] = list(gamepads)
        if pointer is not None:
            req["pointer"] = dict(pointer)
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

    # A test op: it feeds events to the real devices, as the window does. It
    # needs devices on in hello. See guide/bridge.md.
    def inject(self, events):
        return self.request({"op": "inject", "events": list(events)})


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


WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_CONTINUATION, WS_TEXT, WS_BINARY, WS_CLOSE, WS_PING, WS_PONG = 0, 1, 2, 8, 9, 10
# A page on any other host could reach the Relay from the player's browser.
RELAY_ORIGIN_HOSTS = ("localhost", "127.0.0.1")
RELAY_PAGE_DROPPED = "the page closed before it replied"
# Tells a replaced page to stop dialling, so two tabs do not take the Relay
# from each other. engine/bridge_transport_web.odin reads it.
RELAY_REPLACED = 4000


def ws_accept(key):
    return base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()


def ws_frame(opcode, payload, mask=None, fin=True):
    """One WebSocket frame. A page's frames carry a mask and the Relay's do not."""
    head = bytearray([(0x80 if fin else 0) | opcode])
    mask_bit = 0x80 if mask is not None else 0
    if len(payload) < 126:
        head.append(mask_bit | len(payload))
    elif len(payload) < 65536:
        head.append(mask_bit | 126)
        head += struct.pack(">H", len(payload))
    else:
        head.append(mask_bit | 127)
        head += struct.pack(">Q", len(payload))
    if mask is None:
        return bytes(head) + payload
    return bytes(head) + mask + ws_mask(payload, mask)


def ws_mask(payload, mask):
    whole = (mask * (len(payload) // 4 + 1))[: len(payload)]
    return (int.from_bytes(payload, "big") ^ int.from_bytes(whole, "big")).to_bytes(len(payload), "big")


def ws_parse_frame(data):
    """Returns ((fin, opcode, payload), rest), or (None, data) until the frame is whole."""
    if len(data) < 2:
        return None, data
    fin = bool(data[0] & 0x80)
    opcode = data[0] & 0x0F
    masked = bool(data[1] & 0x80)
    length = data[1] & 0x7F
    at = 2
    if length == 126:
        if len(data) < 4:
            return None, data
        (length,) = struct.unpack(">H", data[2:4])
        at = 4
    elif length == 127:
        if len(data) < 10:
            return None, data
        (length,) = struct.unpack(">Q", data[2:10])
        at = 10
    mask = None
    if masked:
        if len(data) < at + 4:
            return None, data
        mask = data[at : at + 4]
        at += 4
    if len(data) < at + length:
        return None, data
    payload = bytes(data[at : at + length])
    if mask is not None:
        payload = ws_mask(payload, mask)
    return (fin, opcode, payload), data[at + length :]


def relay_origin_allowed(head):
    """A browser always sends Origin. A page from another host is refused."""
    origin = relay_header(head, "origin")
    return origin == "" or urllib.parse.urlsplit(origin).hostname in RELAY_ORIGIN_HOSTS


def relay_header(head, wanted):
    for line in head.split("\r\n")[1:]:
        name, _, value = line.partition(":")
        if name.strip().lower() == wanted:
            return value.strip()
    return ""


class RelayConn:
    def __init__(self, sock):
        self.sock = sock
        self.buf = b""
        # One of "new", "page" or "driver".
        self.kind = "new"
        # A page's message so far, while its frames are split.
        self.message = b""


class Relay:
    """Joins one page's WebSocket and one Driver's JSON Lines on one port.

    The first bytes name the side: "GET " is the page, anything else is a
    Driver. Each Driver line goes to the page as one text message, and each
    page message goes back as one reply line. A new page replaces the old
    one. A request waits until a page connects. The Relay exits after it
    forwards the reply to quit."""

    def __init__(self, port, host="127.0.0.1"):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind((host, port))
        self.listener.listen(8)
        self.port = self.listener.getsockname()[1]
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.listener, selectors.EVENT_READ)
        self.page = None
        self.driver = None
        # Drivers that connected while another was served, in order.
        self.waiting = []
        # The request the page owes a reply to, and the Driver that sent it.
        self.in_flight = None
        self.done = False

    def close(self):
        self.done = True
        socks = [key.fileobj for key in self.selector.get_map().values()] + [conn.sock for conn in self.waiting]
        self.selector.close()
        for sock in socks:
            sock.close()

    def serve(self):
        try:
            while not self.done:
                for key, _ in self.selector.select(timeout=0.2):
                    if self.done:
                        break
                    if key.data is None:
                        self.accept()
                    else:
                        self.read(key.data)
        except (OSError, ValueError):
            if not self.done:
                raise

    def accept(self):
        sock, _ = self.listener.accept()
        conn = RelayConn(sock)
        self.selector.register(sock, selectors.EVENT_READ, conn)

    def drop(self, conn):
        try:
            self.selector.unregister(conn.sock)
        except (KeyError, ValueError):
            pass
        conn.sock.close()
        if conn is self.page:
            self.page = None
            if self.in_flight is not None:
                _, driver = self.in_flight
                self.in_flight = None
                if driver is not None:
                    self.reply(driver, json.dumps({"ok": False, "error": RELAY_PAGE_DROPPED}, separators=(",", ":")).encode())
        elif conn is self.driver:
            self.driver = None
            if self.in_flight is not None:
                # The page still owes the reply, and it goes nowhere.
                self.in_flight = (self.in_flight[0], None)
            self.next_driver()
        elif conn in self.waiting:
            self.waiting.remove(conn)

    def read(self, conn):
        try:
            data = conn.sock.recv(65536)
        except OSError:
            data = b""
        if not data:
            self.drop(conn)
            return
        conn.buf += data
        if conn.kind == "new":
            self.classify(conn)
        elif conn.kind == "page":
            self.read_page(conn)
        if conn.kind == "driver" and conn is self.driver:
            self.forward()

    def classify(self, conn):
        if conn.buf.startswith(b"GET "):
            end = conn.buf.find(b"\r\n\r\n")
            if end >= 0:
                self.open_page(conn, conn.buf[:end].decode("latin-1"), conn.buf[end + 4 :])
            return
        if len(conn.buf) < 4 and b"\n" not in conn.buf and b"GET "[: len(conn.buf)] == conn.buf:
            return
        conn.kind = "driver"
        if self.driver is None:
            self.driver = conn
        else:
            self.waiting.append(conn)
            # A waiting Driver's lines stay in the socket until its turn.
            self.selector.unregister(conn.sock)

    def open_page(self, conn, head, rest):
        key = relay_header(head, "sec-websocket-key")
        if not relay_origin_allowed(head) or not key:
            conn.sock.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            self.drop(conn)
            return
        conn.sock.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" f"Sec-WebSocket-Accept: {ws_accept(key)}\r\n\r\n").encode())
        if self.page is not None:
            old = self.page
            try:
                old.sock.sendall(ws_frame(WS_CLOSE, struct.pack(">H", RELAY_REPLACED) + b"replaced"))
            except OSError:
                pass
            self.drop(old)
        conn.kind = "page"
        conn.buf = rest
        self.page = conn
        self.read_page(conn)
        self.forward()

    def read_page(self, conn):
        while conn is self.page:
            frame, conn.buf = ws_parse_frame(conn.buf)
            if frame is None:
                return
            fin, opcode, payload = frame
            if opcode == WS_PING:
                conn.sock.sendall(ws_frame(WS_PONG, payload))
            elif opcode == WS_CLOSE:
                self.drop(conn)
            elif opcode in (WS_TEXT, WS_BINARY, WS_CONTINUATION):
                conn.message += payload
                if fin:
                    message, conn.message = conn.message, b""
                    self.page_reply(message)

    def page_reply(self, message):
        if self.in_flight is None:
            return
        request, driver = self.in_flight
        self.in_flight = None
        try:
            reply = json.loads(message)
        except ValueError:
            reply = None
        if isinstance(reply, dict) and "png" in reply:
            message = self.save_png(request, reply)
        # A Driver that left before the reply gets nothing, but its quit
        # still ends the run.
        if driver is not None:
            self.reply(driver, message)
        if request.get("op") == "quit" and isinstance(reply, dict) and reply.get("ok"):
            self.done = True
            return
        self.forward()

    # The host has no file system to write to, so the Relay writes the PNG
    # to the request's path and gives the Driver the native reply.
    def save_png(self, request, reply):
        data = base64.b64decode(reply.pop("png"))
        try:
            with open(request["path"], "wb") as f:
                f.write(data)
        except (OSError, KeyError, TypeError) as err:
            reply = {"ok": False, "error": f"the Relay cannot write {request.get('path')!r}: {err}"}
        return json.dumps(reply, separators=(",", ":")).encode()

    def reply(self, driver, message):
        try:
            driver.sock.sendall(message + b"\n")
        except OSError:
            self.drop(driver)

    # Sends the Driver's next line when the page owes nothing.
    def forward(self):
        while self.driver is not None and self.page is not None and self.in_flight is None:
            end = self.driver.buf.find(b"\n")
            if end < 0:
                return
            line, self.driver.buf = self.driver.buf[:end].rstrip(b"\r"), self.driver.buf[end + 1 :]
            if not line.strip():
                continue
            try:
                request = json.loads(line)
            except ValueError:
                request = {}
            self.in_flight = (request if isinstance(request, dict) else {}, self.driver)
            try:
                self.page.sock.sendall(ws_frame(WS_TEXT, line))
            except OSError:
                self.drop(self.page)

    def next_driver(self):
        if self.driver is not None or not self.waiting:
            return
        self.driver = self.waiting.pop(0)
        self.selector.register(self.driver.sock, selectors.EVENT_READ, self.driver)
        self.forward()


def mouse_arg(text):
    parts = text.split(",")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("the mouse movement is dx,dy, such as 4,-2")
    try:
        return [int(p) if p.strip().lstrip("-").isdigit() else float(p) for p in parts]
    except ValueError:
        raise argparse.ArgumentTypeError("the mouse movement is dx,dy, such as 4,-2") from None


def point_arg(text):
    parts = text.split(",")
    try:
        if len(parts) == 2:
            return [float(p) for p in parts]
    except ValueError:
        pass
    raise argparse.ArgumentTypeError("a point is x,y, such as 884,36")


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


# The pointer flags build one pointer. None when no flag is given.
def step_pointer(args):
    if args.pointer is None:
        return None
    x, y = args.pointer
    pointer = {"x": x, "y": y}
    if args.outside:
        pointer["inside"] = False
    if args.held_mouse:
        pointer["held"] = args.held_mouse
    if args.tap_mouse:
        pointer["tap"] = args.tap_mouse
    if args.wheel is not None:
        pointer["wheel"] = args.wheel
    return pointer


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
    parser.add_argument("--devices", action="store_true", help="say hello with devices on first, so the real devices reach the game during the op")
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
    ptr = step.add_argument_group("the pointer", "the pointer for the steps, in logical window pixels; without --pointer it is outside the window")
    ptr.add_argument("--pointer", type=point_arg, metavar="X,Y", help="the pointer position for every step")
    ptr.add_argument("--held-mouse", action="append", default=[], metavar="BUTTON", help="a mouse button held for every step; repeat for more buttons")
    ptr.add_argument("--tap-mouse", action="append", default=[], metavar="BUTTON", help="a mouse button clicked in the first step; repeat for more buttons")
    ptr.add_argument("--wheel", type=point_arg, metavar="DX,DY", help="the wheel scroll in the first step")
    ptr.add_argument("--outside", action="store_true", help="the pointer is outside the window")
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
    relay = ops.add_parser("relay", help="join a web page's WebSocket and the Drivers on one port, until quit")
    # SUPPRESS keeps the main --port when this one is not given.
    relay.add_argument("--port", type=int, default=argparse.SUPPRESS, help=f"the port the page and the Drivers connect to (default: ${PORT_ENV})")
    args = parser.parse_args(argv)
    if args.op == "tell" and (args.msg is None) == (args.file is None):
        tell.error("give either MSG or --file PATH")
    if args.op == "step" and args.pointer is None and (args.held_mouse or args.tap_mouse or args.wheel is not None or args.outside):
        step.error("--held-mouse, --tap-mouse, --wheel and --outside need --pointer X,Y")
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
    if args.op == "relay":
        try:
            relay = Relay(port)
        except OSError as err:
            print(f"bridge.py: the Relay cannot listen on 127.0.0.1:{port}: {err}", file=sys.stderr)
            return 2
        try:
            relay.serve()
        except KeyboardInterrupt:
            pass
        finally:
            relay.close()
        return 0
    try:
        with Bridge.connect(port, wait=args.wait) as b:
            try:
                # With --devices, the hello goes first on the same connection,
                # since devices last only while the Driver stays connected.
                if args.devices or args.op == "hello":
                    b.hello(devices=args.devices)
                if args.op == "step":
                    b.step(args.n, held=args.held, tap=args.tap, mouse=args.mouse, gamepads=step_gamepads(args), pointer=step_pointer(args))
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
