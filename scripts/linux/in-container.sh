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

# The timeout turns a hang into a failure instead of a stuck container.
RUN="timeout 600 xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1"
EXPECTED="Frame Count: $FRAMES"
for game in cards entity-game; do
	echo "== run $game for $FRAMES frames under xvfb"
	RUN_LOG=/tmp/$game.log
	set +e
	(cd "examples/$game" && ROCCO_EXIT_AFTER_FRAMES=$FRAMES $RUN "./${game}_linux.bin") > "$RUN_LOG" 2>&1
	code=$?
	set -e
	frame_count_lines=$(grep -c '^Frame Count: ' "$RUN_LOG" || true)
	if [ "$code" -ne 0 ] || [ "$frame_count_lines" -ne 1 ] || ! grep -qx "$EXPECTED" "$RUN_LOG"; then
		tail -40 "$RUN_LOG" >&2
		echo "FAIL: $game exit=$code, frame count lines=$frame_count_lines, expected '$EXPECTED'" >&2
		exit 1
	fi
	echo "PASS: $game exit=0, $EXPECTED"
done

echo "== alloc check"
RUN_PREFIX="$RUN" sh scripts/alloc-check.sh

echo "== host check"
sh scripts/host-check.sh
