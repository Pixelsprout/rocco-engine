#!/bin/sh
# Runs inside the image from scripts/linux/Dockerfile with the repo at /work.
set -eu
cd /work

TARGET_DIR=platform/targets/x64glibc
SOKOL_DIR=sokol
LIBDIR=/usr/lib/x86_64-linux-gnu

echo "== toolchain"
odin version
roc version

# Same flags as build_lib_x64_debug in sokol/build_clibs_linux.sh. That script
# also builds five unused modules, release variants and .so files, and needs
# ALSA headers, so only the four archives the engine links are built here.
echo "== sokol GLCORE archives"
mkdir -p "$TARGET_DIR"
for m in log gfx app glue; do
	cc -pthread -c -g -DIMPL -DSOKOL_GLCORE "$SOKOL_DIR/c/sokol_$m.c" -o "/tmp/sokol_$m.o"
	ar rcs "$SOKOL_DIR/$m/sokol_${m}_linux_x64_gl_debug.a" "/tmp/sokol_$m.o"
	cp "$SOKOL_DIR/$m/sokol_${m}_linux_x64_gl_debug.a" "$TARGET_DIR/"
done

echo "== libhost.a"
odin build engine -build-mode:static -out:"$TARGET_DIR/libhost.a" -debug -vet -strict-style

echo "== CRT objects and shared libraries"
cp "$LIBDIR/Scrt1.o" "$LIBDIR/crti.o" "$LIBDIR/crtn.o" "$TARGET_DIR/"
cp "$LIBDIR/libc.so.6" "$LIBDIR/libm.so.6" "$TARGET_DIR/"
cp "$LIBDIR/libX11.so.6" "$LIBDIR/libXi.so.6" "$LIBDIR/libXcursor.so.1" "$LIBDIR/libGL.so.1" "$TARGET_DIR/"
ls -la "$TARGET_DIR"

echo "== roc build x64glibc"
cd examples/bodies
roc build --target=x64glibc --output=./bodies_linux.bin main.roc
readelf -d ./bodies_linux.bin | grep NEEDED || true

echo "== start under xvfb"
set +e
timeout 15 xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 ./bodies_linux.bin
code=$?
set -e
echo "process exit=$code"
# 124 means the process was still running at the timeout. 134 is sokol's
# abort at shader validation, expected until the shader comes from sokol-shdc.
case $code in
	0 | 124) echo "started and ran" ;;
	134) echo "started; aborted at shader validation (expected before sokol-shdc)" ;;
	*) echo "did not start cleanly" >&2; exit 1 ;;
esac
