#!/bin/sh
# Builds the miniaudio archive, debug and release, from
# scripts/miniaudio/rocco_miniaudio.c into build/miniaudio/, with the same
# flags as scripts/linux/build-sokol.sh. It runs in the image from
# scripts/linux/Dockerfile or on a Linux machine. miniaudio opens ALSA and
# PulseAudio at run time, so the build needs no audio headers.
#
# Ubuntu's cc turns on _FORTIFY_SOURCE, which calls glibc's __*_chk
# functions. The Linux stubs do not list them, so the build turns it off.
set -eu
cd "$(dirname "$0")/../.."

out=build/miniaudio
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
o=$tmp/miniaudio.o

echo "== miniaudio archive"
cc -pthread -c -g -U_FORTIFY_SOURCE scripts/miniaudio/rocco_miniaudio.c -o "$o"
rm -f "$out/miniaudio_linux_x64_debug.a"
ar rcs "$out/miniaudio_linux_x64_debug.a" "$o"
cc -pthread -c -O2 -DNDEBUG -U_FORTIFY_SOURCE scripts/miniaudio/rocco_miniaudio.c -o "$o"
rm -f "$out/miniaudio_linux_x64_release.a"
ar rcs "$out/miniaudio_linux_x64_release.a" "$o"
