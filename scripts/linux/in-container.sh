#!/bin/sh
# Runs inside the image from scripts/linux/Dockerfile with the repo at /work.
set -eu
cd /work

SOKOL_DIR=sokol-odin/sokol
FRAMES=120

echo "== toolchain"
odin version
roc version

# Same flags as build_lib_x64_debug in sokol-odin/sokol/build_clibs_linux.sh.
# That script also builds five unused modules, release variants and .so files,
# and needs ALSA headers, so only the four archives the engine links are built
# here.
echo "== sokol GLCORE archives"
for m in log gfx app glue; do
	cc -pthread -c -g -DIMPL -DSOKOL_GLCORE "$SOKOL_DIR/c/sokol_$m.c" -o "/tmp/sokol_$m.o"
	ar rcs "$SOKOL_DIR/$m/sokol_${m}_linux_x64_gl_debug.a" "/tmp/sokol_$m.o"
done

roc scripts/build.roc all

echo "== run bodies for $FRAMES frames under xvfb"
cd examples/bodies
RUN_LOG=/tmp/run.log
EXPECTED="Frame Count: $FRAMES"
set +e
# The timeout turns a hang into a failure instead of a stuck container.
timeout 600 xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 ROCCO_EXIT_AFTER_FRAMES=$FRAMES ./bodies_linux.bin > "$RUN_LOG" 2>&1
code=$?
set -e
frame_count_lines=$(grep -c '^Frame Count: ' "$RUN_LOG" || true)
if [ "$code" -ne 0 ] || [ "$frame_count_lines" -ne 1 ] || ! grep -qx "$EXPECTED" "$RUN_LOG"; then
	tail -40 "$RUN_LOG" >&2
	echo "FAIL: exit=$code, frame count lines=$frame_count_lines, expected '$EXPECTED'" >&2
	exit 1
fi
echo "$EXPECTED"
echo "PASS: exit=0"
