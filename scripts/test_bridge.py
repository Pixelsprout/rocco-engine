# Run from the repository root: python3 -m unittest scripts/test_bridge.py
#
# The tests run bridge.py against a fake host: a socket server on a free
# port that records each request line and answers from a list of replies.

import contextlib
import io
import json
import os
import socket
import struct
import sys
import tempfile
import threading
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bridge


class FakeHost:
    def __init__(self, replies):
        self.replies = list(replies)
        self.requests = []
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    # One reply per request line. With no replies left, it closes the
    # connection, as the host does after quit.
    def serve(self):
        conn, _ = self.listener.accept()
        with conn, conn.makefile("rb") as reader:
            while self.replies:
                line = reader.readline()
                if not line:
                    return
                self.requests.append(json.loads(line))
                conn.sendall(self.replies.pop(0).encode() + b"\n")

    def close(self):
        self.thread.join(timeout=5)
        self.listener.close()


# lit holds the (x, y) of each white pixel. The rest are zero.
def png_bytes(width, height, lit=()):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    pixels = bytearray(width * height * 4)
    for x, y in lit:
        pixels[(y * width + x) * 4 : (y * width + x + 1) * 4] = b"\xff" * 4
    rows = b"".join(b"\x00" + bytes(pixels[y * width * 4 : (y + 1) * width * 4]) for y in range(height))
    return bridge.PNG_SIGNATURE + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def run_cli(argv):
    out = io.StringIO()
    err = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = bridge.main(argv)
    return code, out.getvalue(), err.getvalue()


class LibraryTest(unittest.TestCase):
    def test_each_op_sends_its_request(self):
        host = FakeHost(
            [
                '{"ok":true,"protocol":1,"step_hz":120,"steps":0,"headless":false}',
                '{"ok":true,"steps":30,"commands":[],"alloc":{}}',
                '{"ok":true,"steps":30,"scene":{"nodes":[]},"results":{}}',
                '{"ok":true,"path":"x","physical":[1920,1080],"logical":[960,540]}',
                '{"ok":true,"queued":1}',
                '{"ok":true}',
            ]
        )
        with bridge.Bridge.connect(host.port) as b:
            self.assertEqual(b.hello()["step_hz"], 120)
            self.assertEqual(b.step(30, held=["W"], tap=["Space"], mouse=[4, -2])["steps"], 30)
            self.assertEqual(b.scene()["scene"], {"nodes": []})
            self.assertEqual(b.screenshot("out.png")["logical"], [960, 540])
            self.assertEqual(b.tell("town", "hi")["queued"], 1)
            self.assertEqual(b.quit(), {"ok": True})
        host.close()
        self.assertEqual(
            host.requests,
            [
                {"op": "hello"},
                {"op": "step", "n": 30, "held": ["W"], "tap": ["Space"], "mouse": [4, -2]},
                {"op": "scene"},
                {"op": "screenshot", "path": os.path.abspath("out.png")},
                {"op": "tell", "port": "town", "msg": "hi"},
                {"op": "quit"},
            ],
        )

    def test_step_leaves_out_empty_fields(self):
        host = FakeHost(['{"ok":true,"steps":1,"commands":[],"alloc":{}}'])
        with bridge.Bridge.connect(host.port) as b:
            b.step()
        host.close()
        self.assertEqual(host.requests, [{"op": "step", "n": 1}])

    def test_step_sends_the_gamepads(self):
        host = FakeHost(['{"ok":true,"steps":1,"commands":[],"alloc":{}}'])
        pads = [{"slot": 1, "held": ["South"], "left_stick": [0, 1]}]
        with bridge.Bridge.connect(host.port) as b:
            b.step(gamepads=pads)
        host.close()
        self.assertEqual(host.requests, [{"op": "step", "n": 1, "gamepads": pads}])

    def test_tell_sends_the_port_and_the_message(self):
        host = FakeHost(['{"ok":true,"queued":1}'])
        with bridge.Bridge.connect(host.port) as b:
            self.assertEqual(b.tell("town", "a\tb\n"), {"ok": True, "queued": 1})
        host.close()
        self.assertEqual(host.requests, [{"op": "tell", "port": "town", "msg": "a\tb\n"}])

    def test_an_error_reply_raises(self):
        host = FakeHost(['{"ok":false,"error":"unknown Key \\"Jump\\" in \\"held\\""}'])
        with bridge.Bridge.connect(host.port) as b:
            with self.assertRaises(bridge.BridgeError) as caught:
                b.step(held=["Jump"])
        host.close()
        self.assertEqual(str(caught.exception), 'unknown Key "Jump" in "held"')
        self.assertFalse(caught.exception.reply["ok"])

    def test_a_closed_connection_raises(self):
        host = FakeHost([])
        with bridge.Bridge.connect(host.port) as b:
            with self.assertRaises(ConnectionError):
                b.hello()
        host.close()

    def test_connect_gives_up_after_wait(self):
        port = bridge.free_port()
        with self.assertRaises(OSError):
            bridge.Bridge.connect(port, wait=0.2)

    def test_png_size_reads_the_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "a.png")
            with open(path, "wb") as f:
                f.write(png_bytes(5, 3))
            self.assertEqual(bridge.png_size(path), [5, 3])
            with open(path, "wb") as f:
                f.write(b"not a png at all, not at all")
            with self.assertRaises(ValueError):
                bridge.png_size(path)

    def test_png_changed_pixels_counts_the_pixels_that_differ(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = os.path.join(tmp, "a.png")
            b = os.path.join(tmp, "b.png")
            with open(a, "wb") as f:
                f.write(png_bytes(4, 3, lit=[(0, 0)]))
            with open(b, "wb") as f:
                f.write(png_bytes(4, 3, lit=[(1, 2), (3, 1)]))
            self.assertEqual(bridge.png_changed_pixels(a, a), 0)
            self.assertEqual(bridge.png_changed_pixels(a, b), 3)
            with open(b, "wb") as f:
                f.write(png_bytes(3, 4))
            with self.assertRaises(ValueError):
                bridge.png_changed_pixels(a, b)


class CliTest(unittest.TestCase):
    def test_step_prints_the_reply(self):
        reply = '{"ok":true,"steps":30,"commands":[],"alloc":{"step":30}}'
        host = FakeHost([reply])
        code, out, _ = run_cli(["--port", str(host.port), "step", "30", "--held", "W", "--held", "A", "--tap", "Space", "--mouse", "4,0.5"])
        host.close()
        self.assertEqual(code, 0)
        self.assertEqual(out, reply + "\n")
        self.assertEqual(host.requests, [{"op": "step", "n": 30, "held": ["W", "A"], "tap": ["Space"], "mouse": [4, 0.5]}])

    def test_step_sends_one_pad_from_the_pad_flags(self):
        host = FakeHost(['{"ok":true,"steps":2,"commands":[],"alloc":{}}'])
        argv = ["--port", str(host.port), "step", "2", "--slot", "2", "--held-button", "South", "--held-button", "DpadUp", "--tap-button", "Start"]
        argv += ["--left-stick", "0.5,-0.25", "--right-stick", "0,1", "--left-trigger", "0.75", "--right-trigger", "1"]
        code, _, _ = run_cli(argv)
        host.close()
        self.assertEqual(code, 0)
        pad = {"slot": 2, "held": ["South", "DpadUp"], "tap": ["Start"], "left_stick": [0.5, -0.25], "right_stick": [0, 1], "left_trigger": 0.75, "right_trigger": 1}
        self.assertEqual(host.requests, [{"op": "step", "n": 2, "gamepads": [pad]}])

    def test_step_sends_the_gamepads_as_json(self):
        host = FakeHost(['{"ok":true,"steps":1,"commands":[],"alloc":{}}'])
        pads = [{"held": ["East"]}, {"slot": 3}]
        code, _, _ = run_cli(["--port", str(host.port), "step", "--gamepads", json.dumps(pads)])
        host.close()
        self.assertEqual(code, 0)
        self.assertEqual(host.requests, [{"op": "step", "n": 1, "gamepads": pads}])

    def test_step_with_no_pad_flags_sends_no_gamepads(self):
        host = FakeHost(['{"ok":true,"steps":1,"commands":[],"alloc":{}}'])
        code, _, _ = run_cli(["--port", str(host.port), "step", "--held", "W"])
        host.close()
        self.assertEqual(code, 0)
        self.assertEqual(host.requests, [{"op": "step", "n": 1, "held": ["W"]}])

    def test_tell_from_the_cli_sends_the_message(self):
        reply = '{"ok":true,"queued":1}'
        host = FakeHost([reply])
        code, out, _ = run_cli(["--port", str(host.port), "tell", "town", "hi"])
        host.close()
        self.assertEqual(code, 0)
        self.assertEqual(out, reply + "\n")
        self.assertEqual(host.requests, [{"op": "tell", "port": "town", "msg": "hi"}])

    def test_tell_from_the_cli_reads_the_message_from_a_file(self):
        host = FakeHost(['{"ok":true,"queued":1}'])
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "msg.txt")
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write("x\ny")
            code, _, _ = run_cli(["--port", str(host.port), "tell", "town", "--file", path])
        host.close()
        self.assertEqual(code, 0)
        self.assertEqual(host.requests, [{"op": "tell", "port": "town", "msg": "x\ny"}])

    def test_tell_from_the_cli_needs_a_message_or_a_file(self):
        port = str(bridge.free_port())
        for argv in (["tell", "town"], ["tell", "town", "hi", "--file", "msg.txt"]):
            with self.subTest(argv=argv), self.assertRaises(SystemExit) as caught:
                run_cli(["--port", port] + argv)
            self.assertEqual(caught.exception.code, 2)

    def test_port_from_the_environment(self):
        host = FakeHost(['{"ok":true}'])
        os.environ[bridge.PORT_ENV] = str(host.port)
        try:
            code, _, _ = run_cli(["quit"])
        finally:
            del os.environ[bridge.PORT_ENV]
        host.close()
        self.assertEqual(code, 0)
        self.assertEqual(host.requests, [{"op": "quit"}])

    def test_an_error_reply_exits_1(self):
        reply = '{"ok":false,"error":"a Headless run draws no image to screenshot"}'
        host = FakeHost([reply])
        code, out, _ = run_cli(["--port", str(host.port), "screenshot", "out.png"])
        host.close()
        self.assertEqual(code, 1)
        self.assertEqual(out, reply + "\n")

    def test_no_host_exits_2(self):
        code, out, err = run_cli(["--port", str(bridge.free_port()), "hello"])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("cannot talk to the host", err)

    def test_no_port_exits_2(self):
        saved = os.environ.pop(bridge.PORT_ENV, None)
        try:
            code, _, err = run_cli(["hello"])
        finally:
            if saved is not None:
                os.environ[bridge.PORT_ENV] = saved
        self.assertEqual(code, 2)
        self.assertIn("--port", err)

    def test_free_port_prints_a_port(self):
        code, out, _ = run_cli(["free-port"])
        self.assertEqual(code, 0)
        self.assertTrue(1 <= int(out) <= 65535)


if __name__ == "__main__":
    unittest.main()
