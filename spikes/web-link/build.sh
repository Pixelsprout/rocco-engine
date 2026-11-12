#!/bin/sh
# Builds the web link spike page into spikes/web-link/build/page.
# Run it through scripts/toolchain.sh run, so odin, roc and emcc are the pins.
#
#   sh scripts/toolchain.sh run sh spikes/web-link/build.sh
#
# Everything before "roc: app" is the platform prebuild. A game author runs
# only the steps from there on.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$here/build
target=$here/platform/targets/wasm32
page=$work/page
emscripten=$(dirname "$(command -v emcc)")
llvm=$(em-config LLVM_ROOT)

rm -rf "$work"
mkdir -p "$work" "$target" "$page"

echo "== odin: host object"
odin build "$here/host" -target:freestanding_wasm32 -build-mode:obj -no-entry-point \
	-default-to-nil-allocator -vet -strict-style -out:"$work/host_odin.o"
emcc -c "$here/host/main.c" -o "$work/main.o"

# emcc writes the loader and picks the system libraries the host needs.
# roc_init and roc_step stay undefined here. The loader gets a stub for each,
# and the Roc link defines them, so the final wasm never imports them.
echo "== emcc: reference link and loader"
emcc -v "$work/main.o" "$work/host_odin.o" -o "$target/index.html" \
	--shell-file "$here/host/shell.html" \
	-sALLOW_MEMORY_GROWTH=1 -sFORCE_FILESYSTEM=1 -sERROR_ON_UNDEFINED_SYMBOLS=0 \
	2> "$work/emcc.log" || { cat "$work/emcc.log" >&2; exit 1; }
mv "$target/index.wasm" "$work/reference.wasm"
libs=$(grep 'wasm-ld ' "$work/emcc.log" | tr ' ' '\n' | grep -E '^-[lL]' | tr '\n' ' ')

# Roc whole-archives every platform input on wasm, so the host and the parts
# of the system libraries it uses go in as one relocatable object.
echo "== wasm-ld: relocatable host.o"
# shellcheck disable=SC2086
"$llvm/wasm-ld" -r -o "$target/host.o" "$work/main.o" "$work/host_odin.o" $libs

echo "== roc: app"
(cd "$here/app" && roc build --target=wasm32 --output="$page/index.wasm" main.roc)

echo "== page"
cp "$target/index.html" "$target/index.js" "$page/"
"$emscripten/tools/file_packager" "$page/pack.data" --preload "$here/app/hello.txt@/hello.txt" \
	--js-output="$page/pack.js" > /dev/null
python3 "$here/check_link.py" "$work/reference.wasm" "$page/index.wasm"
echo "== ready: $page"
