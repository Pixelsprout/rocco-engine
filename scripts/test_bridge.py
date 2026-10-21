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


def png_bytes(width, height):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    rows = b"".join(b"\x00" + b"\x00" * (width * 4) for _ in range(height))
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
                '{"ok":true,"steps":30,"scene":{"draws":[]},"results":{}}',
                '{"ok":true,"path":"x","physical":[1920,1080],"logical":[960,540]}',
                '{"ok":true}',
            ]
        )
        with bridge.Bridge.connect(host.port) as b:
            self.assertEqual(b.hello()["step_hz"], 120)
            self.assertEqual(b.step(30, held=["W"], tap=["Space"], mouse=[4, -2])["steps"], 30)
            self.assertEqual(b.scene()["scene"], {"draws": []})
            self.assertEqual(b.screenshot("out.png")["logical"], [960, 540])
            self.assertEqual(b.quit(), {"ok": True})
        host.close()
        self.assertEqual(
            host.requests,
            [
                {"op": "hello"},
                {"op": "step", "n": 30, "held": ["W"], "tap": ["Space"], "mouse": [4, -2]},
                {"op": "scene"},
                {"op": "screenshot", "path": os.path.abspath("out.png")},
                {"op": "quit"},
            ],
        )

    def test_step_leaves_out_empty_fields(self):
        host = FakeHost(['{"ok":true,"steps":1,"commands":[],"alloc":{}}'])
        with bridge.Bridge.connect(host.port) as b:
            b.step()
        host.close()
        self.assertEqual(host.requests, [{"op": "step", "n": 1}])

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


class CliTest(unittest.TestCase):
    def test_step_prints_the_reply(self):
        reply = '{"ok":true,"steps":30,"commands":[],"alloc":{"step":30}}'
        host = FakeHost([reply])
        code, out, _ = run_cli(["--port", str(host.port), "step", "30", "--held", "W", "--held", "A", "--tap", "Space", "--mouse", "4,0.5"])
        host.close()
        self.assertEqual(code, 0)
        self.assertEqual(out, reply + "\n")
        self.assertEqual(host.requests, [{"op": "step", "n": 30, "held": ["W", "A"], "tap": ["Space"], "mouse": [4, 0.5]}])

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
