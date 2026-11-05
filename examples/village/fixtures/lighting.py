#!/usr/bin/env python3
"""Capture lighting switches with equal simulation steps through the Bridge."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / "examples/village"
sys.path.insert(0, str(ROOT / "scripts"))
from bridge import Bridge, png_rgba


def capture(out, view, switch, steps, require_1080, retina):
    name = view + "-" + switch
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, ROCCO_BRIDGE=str(port), ROCCO_SEED="0", ROCCO_EXIT_AFTER_FRAMES="20000")
    suffix = ".exe" if os.name == "nt" else "_linux.bin" if sys.platform.startswith("linux") else ".bin"
    with (out / (name + ".log")).open("w") as log:
        command = [str(GAME / ("village" + suffix))]
        if retina:
            command.append("--retina-1080")
        process = subprocess.Popen(command, cwd=GAME, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            with Bridge.connect(port, wait=60) as bridge:
                bridge.hello()
                for ready_step in range(1, 1025):
                    bridge.step(1)
                    scene = bridge.scene()["scene"]
                    if scene["nodes"]:
                        break
                    assert scene["ui"], "Loading feedback disappeared"
                else:
                    raise AssertionError("The village did not finish loading")
                bridge.tell("lighting", "all")
                if switch != "all":
                    bridge.tell("lighting", switch)
                bridge.tell("view", view)
                bridge.step(steps)
                scene = bridge.scene()["scene"]
                path = out / (name + ".png")
                result = bridge.screenshot(str(path))
                if require_1080:
                    assert result["physical"] == [1920, 1080], result
                bridge.quit()
            assert process.wait(timeout=30) == 0
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=30)
    return {"view": view, "disabled": switch, "ready_step": ready_step, "steps_after_ready": steps, "physical": result["physical"], "camera": scene["camera"], "environment": scene["environment"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def surface_difference(a, b):
    width, height, left = png_rgba(a.read_bytes())
    w, h, right = png_rgba(b.read_bytes())
    assert (width, height) == (w, h)
    # The lower quarter contains ground and buildings in the approved views.
    deltas = [abs(left[(y * width + x) * 4 + c] - right[(y * width + x) * 4 + c]) for y in range(height * 3 // 4, height) for x in range(width) for c in range(3)]
    return sum(deltas) / len(deltas)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    parser.add_argument("--views", nargs="+", default=["hero", "square", "tour"])
    parser.add_argument("--switches", nargs="+", default=["all", "sky", "sun", "exposure", "ground", "lamps", "bloom", "haze"])
    parser.add_argument("--steps", type=int, default=480)
    parser.add_argument("--require-1080", action="store_true")
    parser.add_argument("--retina-1080", action="store_true")
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    report = {"seed": 0, "retina_1080": args.retina_1080, "binary_sha256": hashlib.sha256((GAME / ("village.exe" if os.name == "nt" else "village_linux.bin" if sys.platform.startswith("linux") else "village.bin")).read_bytes()).hexdigest(), "captures": []}
    for view in args.views:
        for switch in args.switches:
            result = capture(out, view, switch, args.steps, args.require_1080, args.retina_1080)
            report["captures"].append(result)
            print(view, switch, result["sha256"], flush=True)
        if "all" in args.switches and "sky" in args.switches:
            delta = surface_difference(out / (view + "-all.png"), out / (view + "-sky.png"))
            assert delta > 0.5, "The sky did not affect visible surfaces"
            report.setdefault("surface_sky_difference", {})[view] = delta
    (out / "lighting.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
