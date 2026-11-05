#!/usr/bin/env python3
"""Check 200 point lights on one floor across camera and light movement."""

import functools
import json
import sys
import tempfile
from pathlib import Path

import bridge
from bridge_check import binary_suffix, check, project, run_game


@functools.lru_cache(maxsize=12)
def read_pixels(path):
    return bridge.png_rgba(Path(path).read_bytes())


def luminance(path, camera, world):
    width, height, pixels = read_pixels(path)
    x, y = project(camera, world, (width, height))
    if not 2 <= x < width - 2 or not 2 <= y < height - 2:
        raise AssertionError(f"floor sample {world} is outside the image")
    values = []
    for py in range(y - 1, y + 2):
        for px in range(x - 1, x + 2):
            at = (py * width + px) * 4
            values.append(sum(pixels[at:at + 3]) / 3)
    return sum(values) / len(values)


def drive(b, out):
    b.hello()
    b.step(1, tap=["P"])
    records = []
    previous = None
    for frame, (steps, held) in enumerate(((1, []), (60, ["D"]), (60, ["A"]), (60, []))):
        before = b.scene()["scene"]["nodes"]
        if frame == 3:
            b.step(1, tap=["P"])
        b.step(steps, held=held)
        if frame == 3:
            b.step(1, tap=["P"])
        scene = b.scene()["scene"]
        if frame == 3:
            check(scene["nodes"] != before, "the point lights move after unpausing")
        points = [node["Light"]["Point"] for node in scene["nodes"] if "Light" in node and "Point" in node["Light"]]
        check(len(points) == 200, f"view {frame} has 200 point lights")
        check(scene["nodes"][0]["Draw"]["mesh"] != 0, "the single tiled floor loaded")
        on = str(Path(out).with_name(f"clustered-{frame}-on.png"))
        off = str(Path(out).with_name(f"clustered-{frame}-off.png"))
        again = str(Path(out).with_name(f"clustered-{frame}-again.png"))
        b.screenshot(on)
        b.step(1, tap=["L"])
        b.screenshot(off)
        b.step(1, tap=["L"])
        b.screenshot(again)
        check(Path(on).read_bytes() == Path(again).read_bytes(), "paused rendering reproduces the same screenshot")
        gains = []
        for point in points:
            pos = point["pos"]
            sample = {"x": pos["x"] + 0.45, "y": 0, "z": pos["z"] + 0.35}
            gain = luminance(on, scene["camera"], sample) - luminance(off, scene["camera"], sample)
            if gain <= 12:
                raise AssertionError(f"view {frame}: lamp at {pos} lost its floor light, gain {gain:.2f}")
            gains.append(gain)
        if previous is not None:
            check(max(abs(a - c) for a, c in zip(previous, gains)) < 20, "camera movement keeps every lamp contribution")
        check(min(gains) > 12, f"view {frame}: all 200 floor patches are lit; minimum gain {min(gains):.2f}")
        previous = gains
        records.append({"view": frame, "minimum_floor_gain": min(gains), "maximum_floor_gain": max(gains)})
    Path(out).with_name("clustered-evidence.json").write_text(json.dumps(records, indent=2) + "\n")
    b.quit()


def main(argv):
    out = Path(argv[0] if argv else "build/bridge-check/clustered.png").resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        run_game("clustered-lights", drive, str(out), tmp, binary_suffix())
        log = Path(tmp, "clustered-lights.log").read_text(errors="replace")
        out.with_name("clustered-native.log").write_text(log)
        check("[sg][error]" not in log and "[sg][panic]" not in log, "the graphics log has no errors")
    print("PASS: clustered lighting check")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
