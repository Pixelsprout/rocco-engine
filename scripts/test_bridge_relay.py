# Run from the repository root: python3 -m unittest scripts/test_bridge_relay.py
#
# The tests run the Relay in a thread on a free port. A fake page speaks the
# client side of a WebSocket, and a Bridge from bridge.py is the Driver.

import base64
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bridge


class FakePage:
    """The client side of a WebSocket, as a browser page opens it."""

    def __init__(self, port, origin="http://127.0.0.1:8000"):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=10)
        key = base64.b64encode(os.urandom(16)).decode()
        lines = ["GET / HTTP/1.1", f"Host: 127.0.0.1:{port}", "Upgrade: websocket", "Connection: Upgrade", f"Sec-WebSocket-Key: {key}", "Sec-WebSocket-Version: 13"]
        if origin is not None:
            lines.append(f"Origin: {origin}")
        self.sock.sendall(("\r\n".join(lines) + "\r\n\r\n").encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1)
            if not chunk:
                break
            head += chunk
        self.status = head.split(b"\r\n", 1)[0].decode()
        self.accept = ""
        for line in head.decode().split("\r\n")[1:]:
            name, _, value = line.partition(":")
            if name.lower() == "sec-websocket-accept":
                self.accept = value.strip()
        self.key = key
        self.buf = b""

    def recv_exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("the Relay closed the page")
            self.buf += chunk
        data, self.buf = self.buf[:n], self.buf[n:]
        return data

    # Returns (opcode, payload) of one frame. The Relay never masks.
    def recv_frame(self):
        first, second = self.recv_exact(2)
        length = second & 0x7F
        if length == 126:
            (length,) = struct.unpack(">H", self.recv_exact(2))
        elif length == 127:
            (length,) = struct.unpack(">Q", self.recv_exact(8))
        return first & 0x0F, self.recv_exact(length)

    def recv_text(self):
        opcode, payload = self.recv_frame()
        if opcode != 1:
            raise AssertionError(f"expected a text frame, got opcode {opcode}")
        return payload.decode()

    def send_frame(self, opcode, payload, fin=True):
        self.sock.sendall(bridge.ws_frame(opcode, payload, mask=os.urandom(4), fin=fin))

    def send_text(self, text):
        self.send_frame(1, text.encode())

    def close(self):
        self.sock.close()


class RelayRun:
    def __init__(self):
        self.relay = bridge.Relay(0)
        self.port = self.relay.port
        self.thread = threading.Thread(target=self.relay.serve, daemon=True)
        self.thread.start()

    def driver(self):
        return bridge.Bridge.connect(self.port, wait=5, timeout=10)

    def page(self, **kwargs):
        return FakePage(self.port, **kwargs)

    def join(self, timeout=5):
        self.thread.join(timeout)
        return not self.thread.is_alive()

    def close(self):
        self.relay.close()
        self.thread.join(5)


# Answers each request on the page with reply(request) in a thread.
def answer_in_thread(page, reply, count=1):
    def run():
        for _ in range(count):
            request = json.loads(page.recv_text())
            page.send_text(json.dumps(reply(request), separators=(",", ":")))

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    return thread


class FramingTest(unittest.TestCase):
    def test_accept_key_follows_the_rfc_example(self):
        self.assertEqual(bridge.ws_accept("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    def test_a_frame_reads_back_at_each_length_form(self):
        for size in (0, 125, 126, 65535, 65536):
            payload = bytes(i & 255 for i in range(size))
            for mask in (None, b"\x01\x02\x03\x04"):
                frame = bridge.ws_frame(1, payload, mask=mask)
                parsed, rest = bridge.ws_parse_frame(frame + b"next")
                self.assertEqual(parsed, (True, 1, payload), f"size {size} mask {mask}")
                self.assertEqual(rest, b"next")

    def test_a_partial_frame_waits_for_more_bytes(self):
        frame = bridge.ws_frame(1, b"hello", mask=b"abcd")
        for cut in range(len(frame)):
            self.assertEqual(bridge.ws_parse_frame(frame[:cut]), (None, frame[:cut]))

    def test_the_relay_answers_the_handshake(self):
        run = RelayRun()
        try:
            page = run.page()
            self.assertEqual(page.status, "HTTP/1.1 101 Switching Protocols")
            self.assertEqual(page.accept, bridge.ws_accept(page.key))
            page.close()
        finally:
            run.close()

    def test_a_page_from_another_origin_is_refused(self):
        run = RelayRun()
        try:
            page = run.page(origin="https://example.itch.io")
            self.assertTrue(page.status.startswith("HTTP/1.1 403"), page.status)
            page.close()
        finally:
            run.close()


class RelayTest(unittest.TestCase):
    def setUp(self):
        self.run = RelayRun()

    def tearDown(self):
        self.run.close()

    def test_each_driver_line_is_one_message_and_each_message_one_reply_line(self):
        page = self.run.page()
        thread = answer_in_thread(page, lambda req: {"ok": True, "echo": req["op"]}, count=2)
        with self.run.driver() as b:
            self.assertEqual(b.hello()["echo"], "hello")
            self.assertEqual(b.scene()["echo"], "scene")
        thread.join(5)
        page.close()

    def test_a_split_message_is_one_reply(self):
        page = self.run.page()

        def run():
            page.recv_text()
            page.send_frame(1, b'{"ok":true,', fin=False)
            page.send_frame(0, b'"steps":3}')

        threading.Thread(target=run, daemon=True).start()
        with self.run.driver() as b:
            self.assertEqual(b.step(3)["steps"], 3)
        page.close()

    def test_a_ping_gets_a_pong(self):
        page = self.run.page()
        page.send_frame(9, b"beat")
        self.assertEqual(page.recv_frame(), (10, b"beat"))
        page.close()

    def test_requests_wait_until_a_page_connects(self):
        with self.run.driver() as b:
            got = {}
            thread = threading.Thread(target=lambda: got.update(b.hello()), daemon=True)
            thread.start()
            time.sleep(0.3)
            self.assertEqual(got, {})
            page = self.run.page()
            self.assertEqual(json.loads(page.recv_text()), {"op": "hello"})
            page.send_text('{"ok":true,"web":true}')
            thread.join(5)
            self.assertEqual(got, {"ok": True, "web": True})
            page.close()

    def test_a_new_page_replaces_the_old_one(self):
        old = self.run.page()
        new = self.run.page()
        opcode, payload = old.recv_frame()
        self.assertEqual(opcode, 8)
        self.assertEqual(struct.unpack(">H", payload[:2])[0], bridge.RELAY_REPLACED)
        with self.assertRaises(ConnectionError):
            while True:
                old.recv_frame()
        thread = answer_in_thread(new, lambda req: {"ok": True, "page": "new"})
        with self.run.driver() as b:
            self.assertEqual(b.hello()["page"], "new")
        thread.join(5)
        old.close()
        new.close()

    def test_a_page_that_drops_during_a_request_gives_an_error_reply(self):
        page = self.run.page()

        def drop():
            page.recv_text()
            page.close()

        threading.Thread(target=drop, daemon=True).start()
        with self.run.driver() as b:
            with self.assertRaises(bridge.BridgeError) as caught:
                b.step(5)
            self.assertIn("page", caught.exception.reply["error"])

    def test_a_reply_owed_to_a_gone_driver_is_dropped(self):
        page = self.run.page()
        with self.run.driver() as first:
            first.sock.sendall(b'{"op":"step","n":9}\n')
            self.assertEqual(json.loads(page.recv_text())["op"], "step")
        with self.run.driver() as second:
            got = {}
            thread = threading.Thread(target=lambda: got.update(second.scene()), daemon=True)
            thread.start()
            time.sleep(0.2)
            page.send_text('{"ok":true,"steps":9}')
            self.assertEqual(json.loads(page.recv_text())["op"], "scene")
            page.send_text('{"ok":true,"scene":{}}')
            thread.join(5)
            self.assertEqual(got, {"ok": True, "scene": {}})
        page.close()

    def test_a_screenshot_reply_with_png_bytes_writes_the_file(self):
        png = b"\x89PNG\r\n\x1a\nfake"
        page = self.run.page()
        thread = answer_in_thread(page, lambda req: {"ok": True, "path": req["path"], "physical": [4, 2], "logical": [4, 2], "png": base64.b64encode(png).decode()})
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "out.png")
            with self.run.driver() as b:
                reply = b.screenshot(path)
            with open(path, "rb") as f:
                self.assertEqual(f.read(), png)
        thread.join(5)
        self.assertEqual(reply, {"ok": True, "path": path, "physical": [4, 2], "logical": [4, 2]})
        page.close()

    def test_the_relay_exits_after_it_forwards_the_quit_reply(self):
        page = self.run.page()
        thread = answer_in_thread(page, lambda req: {"ok": True})
        with self.run.driver() as b:
            self.assertEqual(b.quit(), {"ok": True})
        thread.join(5)
        self.assertTrue(self.run.join())
        page.close()

    def test_a_quit_from_a_driver_that_left_still_ends_the_relay(self):
        page = self.run.page()
        with self.run.driver() as b:
            b.sock.sendall(b'{"op":"quit"}\n')
            self.assertEqual(json.loads(page.recv_text()), {"op": "quit"})
        time.sleep(0.2)
        page.send_text('{"ok":true}')
        self.assertTrue(self.run.join())
        page.close()


class CliTest(unittest.TestCase):
    # Each CLI call is its own connection, as an agent makes one per shell call.
    def test_separate_cli_calls_reach_one_page_and_quit_ends_the_relay(self):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bridge.py")
        port = bridge.free_port()
        relay = subprocess.Popen([sys.executable, script, "relay", "--port", str(port)])
        try:
            page = None
            deadline = time.monotonic() + 10
            while page is None:
                try:
                    page = FakePage(port)
                except OSError:
                    if time.monotonic() > deadline:
                        raise
                    time.sleep(0.05)
            thread = answer_in_thread(page, lambda req: {"ok": True, "op": req["op"]}, count=3)
            for op in ("hello", "scene", "quit"):
                out = subprocess.run([sys.executable, script, "--port", str(port), op], capture_output=True, text=True, timeout=20)
                self.assertEqual(out.returncode, 0, out.stderr)
                self.assertEqual(json.loads(out.stdout)["op"], op)
            thread.join(5)
            self.assertEqual(relay.wait(10), 0)
            page.close()
        finally:
            relay.kill()
            relay.wait()


if __name__ == "__main__":
    unittest.main()
