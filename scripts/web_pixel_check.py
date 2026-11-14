#!/usr/bin/env python3
"""Compares a native and a web screenshot of one frame. Run it from the
repository root:

    python3 scripts/web_pixel_check.py native.png web.png

A pixel has changed when one of its colour channels differs by more than
the tolerance. The check fails when more pixels changed than the limit. The
two builds draw through different rasterizers, so the frames are close but
not equal. It prints the count at a few tolerances, so a CI log holds what
a new limit needs. Python standard library only.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bridge

# For pong after 60 steps: native Linux on Mesa llvmpipe GL, web on headless
# Chrome with WebGPU on Mesa lavapipe, both 960x540. CI run 43571158993
# measured 3768 changed pixels at 0, 280 at 16 and 24 at 64, mostly along
# edges. The limit is about twice the count at 16. A missing paddle changes
# about 900 pixels.
TOLERANCE = 16
LIMIT = 600
REPORT_TOLERANCES = (0, 4, 8, 16, 32, 64)


def read_rgba(path):
    with open(path, "rb") as f:
        return bridge.png_rgba(f.read())


def changed_counts(path_a, path_b, tolerances):
    """Returns the count of changed pixels at each tolerance, in order."""
    width_a, height_a, a = read_rgba(path_a)
    width_b, height_b, b = read_rgba(path_b)
    if (width_a, height_a) != (width_b, height_b):
        raise ValueError(f"{path_a} is {width_a}x{height_a} and {path_b} is {width_b}x{height_b}")
    counts = [0] * len(tolerances)
    for i in range(0, len(a), 4):
        diff = max(abs(a[i] - b[i]), abs(a[i + 1] - b[i + 1]), abs(a[i + 2] - b[i + 2]))
        for j, tolerance in enumerate(tolerances):
            if diff > tolerance:
                counts[j] += 1
    return counts


def changed_pixels(path_a, path_b, tolerance):
    return changed_counts(path_a, path_b, [tolerance])[0]


def main(argv=None):
    parser = argparse.ArgumentParser(description="Compare a native and a web screenshot of one frame.")
    parser.add_argument("native")
    parser.add_argument("web")
    parser.add_argument("--tolerance", type=int, default=TOLERANCE, help=f"the largest channel difference that is not a change (default: {TOLERANCE})")
    parser.add_argument("--limit", type=int, default=LIMIT, help=f"the most changed pixels that pass (default: {LIMIT})")
    args = parser.parse_args(argv)
    tolerances = sorted(set(REPORT_TOLERANCES) | {args.tolerance})
    counts = changed_counts(args.native, args.web, tolerances)
    for tolerance, count in zip(tolerances, counts):
        print(f"tolerance {tolerance}: {count} changed pixels")
    count = counts[tolerances.index(args.tolerance)]
    if count > args.limit:
        print(f"FAIL: {count} pixels differ by more than {args.tolerance}, and the limit is {args.limit}")
        return 1
    print(f"ok: {count} pixels differ by more than {args.tolerance}, within the limit of {args.limit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
