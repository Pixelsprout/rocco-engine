#!/usr/bin/env python3
"""The Bridge Done check. Run it from the repository root after the build:

    python3 scripts/bridge_check.py [out.png]

It runs tutorial chapter 3 with ROCCO_BRIDGE, holds W for 30 steps and checks
that Pip's Draw moved by the expected distance. Then it saves a screenshot,
by default into a temporary folder, and checks its size. RUN_PREFIX wraps the
game, as in run-games.sh, for example the xvfb-run line in the Linux image.
"""

import os
import shlex
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bridge

GAME = "tutorial/03-moving"
PIP_ID = 2
STEPS = 30
# examples/tutorial/03-moving/main.roc: speed 2.5 units a second, 120 steps a
# second, W walks along -z.
EXPECTED_DZ = -2.5 * STEPS / 120
TOLERANCE = 1e-4
WINDOW = [960, 540]


def binary_suffix():
    lines = subprocess.run(["roc", "scripts/build.roc", "--", "target"], check=True, capture_output=True, text=True).stdout
    for line in lines.splitlines():
        if line.startswith("suffix="):
            return line[len("suffix=") :]
    raise RuntimeError("roc scripts/build.roc -- target printed no suffix")


def pip_pos(reply):
    draws = [d for d in reply["scene"]["draws"] if d["id"] == PIP_ID]
    if len(draws) != 1:
        raise AssertionError(f"expected one Draw with id {PIP_ID}, got {reply['scene']['draws']}")
    return draws[0]["pos"]


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"PASS: {message}")


def drive(b, out):
    hello = b.hello()
    check(hello["step_hz"] == 120 and not hello["headless"], f"hello: {hello}")

    before = pip_pos(b.scene())
    stepped = b.step(STEPS, held=["W"])
    check(stepped["steps"] == hello["steps"] + STEPS, f"step ran {STEPS} steps, steps is now {stepped['steps']}")
    after_reply = b.scene()
    check(after_reply["steps"] == stepped["steps"], f"scene is from step {after_reply['steps']}")
    after = pip_pos(after_reply)
    dz = after["z"] - before["z"]
    check(abs(dz - EXPECTED_DZ) < TOLERANCE, f"Pip moved {dz} along z, expected {EXPECTED_DZ}")
    check(after["x"] == before["x"] and after["y"] == before["y"], f"Pip stayed at x {after['x']}, y {after['y']}")

    shot = b.screenshot(out)
    # physical is logical times the display scale: 1 under xvfb, 1 or 2 on a Mac.
    check(shot["logical"] == WINDOW, f"screenshot logical size {shot['logical']}")
    size = bridge.png_size(out)
    check(size == shot["physical"], f"PNG size {size} is the physical size {shot['physical']}")

    b.quit()


def main(argv):
    folder = os.path.join("examples", GAME)
    name = os.path.basename(GAME)
    command = shlex.split(os.environ.get("RUN_PREFIX", "")) + [os.path.abspath(os.path.join(folder, name + binary_suffix()))]
    port = bridge.free_port()
    env = dict(os.environ, ROCCO_BRIDGE=str(port))

    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.abspath(argv[0]) if argv else os.path.join(tmp, "bridge-check.png")
        log_path = os.path.join(tmp, "game.log")
        print(f"== bridge check: {GAME} on port {port}")
        with open(log_path, "w") as log:
            game = subprocess.Popen(command, cwd=folder, env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                with bridge.Bridge.connect(port, wait=120, process=game) as b:
                    drive(b, out)
                code = game.wait(timeout=60)
                check(code == 0, f"the game exited with code {code}")
            except BaseException:
                if game.poll() is None:
                    game.kill()
                    game.wait()
                log.flush()
                with open(log_path, errors="replace") as f:
                    print(f.read()[-4000:], file=sys.stderr)
                raise
    print("PASS: bridge check")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
