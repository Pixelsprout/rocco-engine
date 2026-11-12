#!/bin/sh
# Builds the web arenas spike page into spikes/web-arenas/build/page.
# Run it through scripts/toolchain.sh run, so odin and emcc are the pins.
#
#   sh scripts/toolchain.sh run sh spikes/web-arenas/build.sh [emcc memory flags]
#
# The default memory flag is -sALLOW_MEMORY_GROWTH=1. Pass other -s flags to
# try a fixed memory size, such as -sINITIAL_MEMORY=96MB.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$here/build
page=$work/page

if [ $# -eq 0 ]; then
	set -- -sALLOW_MEMORY_GROWTH=1
fi

rm -rf "$work"
mkdir -p "$work" "$page"

echo "== odin: host object"
odin build "$here/host" -target:freestanding_wasm32 -build-mode:obj -no-entry-point \
	-default-to-nil-allocator -vet -strict-style -out:"$work/host_odin.o"
emcc -c "$here/host/main.c" -o "$work/main.o"

echo "== emcc: page ($*)"
emcc "$work/main.o" "$work/host_odin.o" -o "$page/index.html" "$@"
echo "== ready: $page"
