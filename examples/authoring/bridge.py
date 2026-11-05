"""Standalone Bridge protocol and PNG reader for the external authoring fixture."""
import json
import os
import socket
import struct
import time
import zlib

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
        self.last_line = ""

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

    def hello(self, devices=False):
        req = {"op": "hello"}
        if devices:
            req["devices"] = True
        return self.request(req)

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

    def screenshot(self, path):
        return self.request({"op": "screenshot", "path": os.path.abspath(path)})

    def quit(self):
        return self.request({"op": "quit"})

    def inject(self, events):
        return self.request({"op": "inject", "events": list(events)})


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
