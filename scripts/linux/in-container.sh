#!/bin/sh
# Runs inside the image from scripts/linux/Dockerfile with the repo at /work.
# Builds every game, runs it, runs the tests, the host check, the alloc check
# and the bench smoke test.
# Pass --release to build the release host and inputs.
set -eu
cd /work
# The bench records the git hash. The mounted checkout has another owner, so
# git refuses it without this.
git config --global --add safe.directory /work

FRAMES=120

echo "== toolchain"
odin version
roc version

sh scripts/linux/build-sokol.sh

roc scripts/build.roc all "$@"

# The timeout turns a hang into a failure instead of a stuck container.
RUN="timeout 600 xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1"
RUN_PREFIX="$RUN" sh scripts/run-games.sh "$FRAMES" cards entity-game pong

sh scripts/test-all.sh

# The host check runs first, because the alloc check rebuilds the host with
# the host tracking allocator.
echo "== host check"
sh scripts/host-check.sh

echo "== alloc check"
RUN_PREFIX="$RUN" sh scripts/alloc-check.sh

echo "== bench games"
sh bench/check.sh
# A smoke test only: CI makes no timing claims. It builds a release host with
# Spans, so it runs last.
roc scripts/build.roc bench model-size,model-size-twin 64
