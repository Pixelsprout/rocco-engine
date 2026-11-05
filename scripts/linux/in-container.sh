#!/bin/sh
# Runs inside the image from scripts/linux/Dockerfile with the repo at /work.
# Builds every game, checks the docs, runs each game, runs the tests,
# the host check, the alloc check and the bench smoke test.
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
sh scripts/linux/build-miniaudio.sh

# The timeout turns a hang into a failure instead of a stuck container.
RUN="timeout 600 xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1"
python3 scripts/shader_contract/install.py
$RUN python3 scripts/shader_contract/contract.py --shdc build/shader-tools/sokol-shdc --check --run
$RUN python3 scripts/shader_assets/native.py --shdc build/shader-tools/sokol-shdc
ROCCO_SHDC=build/shader-tools/sokol-shdc python3 -m unittest scripts/test_shader_assets.py

roc scripts/build.roc all "$@"

echo "== docs check"
roc scripts/build.roc docs --check

RUN_PREFIX="$RUN" sh scripts/run-games.sh "$FRAMES" cards entity-game pong bridge-echo glow mask widgets clustered-lights tutorial/01-window tutorial/02-character tutorial/03-moving tutorial/04-lights tutorial/05-pickups tutorial/06-door tutorial/07-hud tutorial/08-sound tutorial/09-gamepad tutorial/10-animation

# CI uploads the screenshots from build/bridge-check.
RUN_PREFIX="$RUN" python3 scripts/bridge_check.py build/bridge-check/bridge-check.png
RUN_PREFIX="$RUN" python3 scripts/cluster_check.py build/bridge-check/clustered.png
RUN_PREFIX="$RUN" python3 scripts/environment_check.py build/bridge-check/environment/reference.png

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
