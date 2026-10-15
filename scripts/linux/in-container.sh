#!/bin/sh
# Runs inside the image from scripts/linux/Dockerfile with the repo at /work.
# Builds every game, runs it, runs the tests, the alloc check and the host check.
# Pass --release to build the release host and inputs.
set -eu
cd /work

SOKOL_DIR=sokol-odin/sokol
FRAMES=120

echo "== toolchain"
odin version
roc version

# Same flags as build_lib_x64_debug and build_lib_x64_release in
# sokol-odin/sokol/build_clibs_linux.sh. That script also builds five unused
# modules and .so files, and needs ALSA headers, so only the four archives the
# engine links are built here.
echo "== sokol GLCORE archives"
for m in log gfx app glue; do
	cc -pthread -c -g -DIMPL -DSOKOL_GLCORE "$SOKOL_DIR/c/sokol_$m.c" -o "/tmp/sokol_$m.o"
	ar rcs "$SOKOL_DIR/$m/sokol_${m}_linux_x64_gl_debug.a" "/tmp/sokol_$m.o"
	cc -pthread -c -O2 -DNDEBUG -DIMPL -DSOKOL_GLCORE "$SOKOL_DIR/c/sokol_$m.c" -o "/tmp/sokol_$m.o"
	ar rcs "$SOKOL_DIR/$m/sokol_${m}_linux_x64_gl_release.a" "/tmp/sokol_$m.o"
done

roc scripts/build.roc all "$@"

# The timeout turns a hang into a failure instead of a stuck container.
RUN="timeout 600 xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1"
RUN_PREFIX="$RUN" sh scripts/run-games.sh "$FRAMES" cards entity-game pong kula

sh scripts/test-all.sh

echo "== alloc check"
RUN_PREFIX="$RUN" sh scripts/alloc-check.sh

echo "== host check"
sh scripts/host-check.sh
