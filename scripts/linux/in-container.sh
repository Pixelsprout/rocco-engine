#!/bin/sh
# Runs inside the image from scripts/linux/Dockerfile with the repo at /work.
# Builds every game, runs it, runs the tests, the alloc check and the host check.
# Pass --release to build the release host and inputs.
set -eu
cd /work

FRAMES=120

echo "== toolchain"
odin version
roc version

sh scripts/linux/build-sokol.sh

roc scripts/build.roc all "$@"

# The timeout turns a hang into a failure instead of a stuck container.
RUN="timeout 600 xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1"
RUN_PREFIX="$RUN" sh scripts/run-games.sh "$FRAMES" cards entity-game pong kula

sh scripts/test-all.sh

echo "== alloc check"
RUN_PREFIX="$RUN" sh scripts/alloc-check.sh

echo "== host check"
sh scripts/host-check.sh
