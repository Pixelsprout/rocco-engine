"""Runs pong natively and in headless Chrome, then compares the two traces.

    python3 spikes/web-pong/compare.py [chrome]

Run build.sh first. The page runs every step inside main, so headless Chrome
needs no animation frames. Each trace line is a digest of the commands or the
Scene for one step, so equal traces mean equal step results.
"""

import html
import http.server
import re
import socket
import subprocess
import sys
import tempfile
import threading
from functools import partial
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD = HERE / "build"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def native_trace():
    run = subprocess.run([str(BUILD / "pong_native.bin")], capture_output=True, text=True, check=True)
    return run.stdout.splitlines()


def web_trace(chrome):
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    handler = partial(QuietHandler, directory=str(BUILD / "page"))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    # A fresh profile keeps the run apart from a Chrome the user has open.
    profile = tempfile.TemporaryDirectory()
    try:
        run = subprocess.run(
            [chrome, "--headless=new", "--disable-gpu", "--no-first-run", f"--user-data-dir={profile.name}",
             "--virtual-time-budget=60000", "--dump-dom", f"http://127.0.0.1:{port}/index.html"],
            capture_output=True, text=True, timeout=180, check=True)
    finally:
        profile.cleanup()
        server.shutdown()
    match = re.search(r'<pre id="output">(.*?)</pre>', run.stdout, re.S)
    if not match:
        sys.exit("compare: the page has no output element")
    return html.unescape(match.group(1)).splitlines()


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def main():
    chrome = sys.argv[1] if len(sys.argv) > 1 else CHROME
    native = native_trace()
    web = web_trace(chrome)
    (BUILD / "native.txt").write_text("\n".join(native) + "\n")
    (BUILD / "web.txt").write_text("\n".join(web) + "\n")
    print(f"native: {len(native)} lines, {native[0]}")
    print(f"web:    {len(web)} lines, {web[0] if web else '(none)'}")
    # The first line names the pointer width, so it is the one line that differs.
    if native[1:] != web[1:]:
        for i, (a, b) in enumerate(zip(native, web)):
            if i > 0 and a != b:
                print(f"first difference at line {i + 1}:\n  native: {a[:300]}\n  web:    {b[:300]}")
                break
        else:
            print("one trace ends early")
        sys.exit(1)
    if web[-1] != "done":
        sys.exit("compare: the web trace does not end with done")
    print(f"same: {len(native) - 1} lines match after the pointer width line")


if __name__ == "__main__":
    main()
