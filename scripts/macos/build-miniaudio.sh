#!/bin/sh
# Builds the miniaudio archive, debug and release, from
# scripts/miniaudio/rocco_miniaudio.c into build/miniaudio/, with the same
# flags as scripts/macos/build-sokol.sh. The engine tests link the debug
# archive, and the inputs step copies one of them.
set -eu
cd "$(dirname "$0")/../.."

out=build/miniaudio
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
o=$tmp/miniaudio.o

echo "== miniaudio archive"
MACOSX_DEPLOYMENT_TARGET=10.13 clang -c -g -arch arm64 scripts/miniaudio/rocco_miniaudio.c -o "$o"
rm -f "$out/miniaudio_macos_arm64_debug.a"
ar rcs "$out/miniaudio_macos_arm64_debug.a" "$o"
MACOSX_DEPLOYMENT_TARGET=10.13 clang -c -O2 -arch arm64 -DNDEBUG scripts/miniaudio/rocco_miniaudio.c -o "$o"
rm -f "$out/miniaudio_macos_arm64_release.a"
ar rcs "$out/miniaudio_macos_arm64_release.a" "$o"
