#!/bin/sh
# Builds examples/pong against a headless harness host twice: as a wasm32
# page, and on macOS as a native twin. compare.py runs both. Run it through
# scripts/toolchain.sh run, so odin, roc and emcc are the pins.
#
#   sh scripts/toolchain.sh run sh spikes/web-pong/build.sh
#
# The build copies the platform, the packages and pong into build/mirror and
# gives the copied platform the two spike targets. The real platform is not
# changed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=$here/build
mirror=$work/mirror
page=$work/page
link=$root/spikes/web-link
llvm=$(em-config LLVM_ROOT)

rm -rf "$work"
mkdir -p "$work/host" "$work/reference" "$mirror/platform/targets/arm64mac" "$mirror/platform/targets/wasm32" "$mirror/examples/pong" "$page"

echo "== mirror: platform, packages and pong"
cp "$root"/platform/*.roc "$mirror/platform/"
cp -R "$root/platform/targets/macos-sysroot" "$mirror/platform/targets/"
cp -R "$root/packages" "$mirror/"
cp "$root/examples/pong/main.roc" "$mirror/examples/pong/"
python3 "$here/mirror_targets.py" "$mirror/platform/main.roc"

echo "== host sources"
cp "$here"/host/*.odin "$work/host/"
sed 's/^package engine$/package web_pong/' "$root/engine/roc_platform_abi.odin" > "$work/host/roc_platform_abi.odin"

# The mirror has only an arm64mac native target. CI builds the page alone.
if [ "$(uname -s)" = Darwin ]; then
	echo "== native: host and link"
	odin build "$work/host" -build-mode:static -out:"$mirror/platform/targets/arm64mac/libhost.a" -vet -strict-style
	cp "$root/platform/targets/arm64mac/libclang_rt.osx.a" "$mirror/platform/targets/arm64mac/"
	(cd "$mirror/examples/pong" && roc build --output="$work/pong_native.bin" main.roc)
fi

echo "== web: host object"
odin build "$work/host" -target:freestanding_wasm32 -build-mode:obj -no-entry-point \
	-default-to-nil-allocator -vet -strict-style -out:"$work/host_odin.o"
emcc -c "$link/host/main.c" -o "$work/main.o"

# The reference link writes the loader. Its -v output names the system
# libraries that the relocatable host.o needs.
echo "== emcc: reference link and loader"
emcc -v "$work/main.o" "$work/host_odin.o" -o "$work/reference/index.html" \
	--shell-file "$here/host/shell.html" \
	-sALLOW_MEMORY_GROWTH=1 -sERROR_ON_UNDEFINED_SYMBOLS=0 \
	2> "$work/emcc.log" || { cat "$work/emcc.log" >&2; exit 1; }
libs=$(grep 'wasm-ld ' "$work/emcc.log" | tr ' ' '\n' | grep -E '^-[lL]' | tr '\n' ' ')

echo "== wasm-ld: relocatable host.o"
# shellcheck disable=SC2086
"$llvm/wasm-ld" -r -o "$mirror/platform/targets/wasm32/host.o" "$work/main.o" "$work/host_odin.o" $libs

echo "== roc: pong for wasm32"
(cd "$mirror/examples/pong" && roc build --target=wasm32 --output="$page/index.wasm" main.roc)

echo "== page"
cp "$work/reference/index.html" "$work/reference/index.js" "$page/"
python3 "$link/check_link.py" "$work/reference/index.wasm" "$page/index.wasm"
echo "== ready: $page"
