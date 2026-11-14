#!/bin/sh
# Prebuilds the web host into platform/targets/wasm32. roc build links a
# game's wasm against host.o there, and the page runs it with index.js.
# Run it from the repository root through scripts/toolchain.sh run, so odin
# and emcc are the pins:
#
#   sh scripts/toolchain.sh run sh scripts/web/build-host.sh [debug|release]
#
# The steps follow spikes/web-link/README.md: emcc writes the JS loader for a
# reference link of the host, and wasm-ld -r packs the host and the members of
# the emscripten system libraries that it uses into one relocatable object.
set -eu
mode=${1:-debug}
root=$(pwd)
work=$root/build/web-host
target=$root/platform/targets/wasm32
llvm=$(em-config LLVM_ROOT)
odin_root=$(odin root)

case $mode in
debug)
	c_opt="-g"
	odin_opt="-debug"
	;;
release)
	c_opt="-O2"
	odin_opt="-o:speed"
	;;
*)
	echo "usage: build-host.sh [debug|release]" >&2
	exit 2
	;;
esac

rm -rf "$work"
mkdir -p "$work" "$target"

echo "== emcc: sokol for WebGPU"
for lib in log gfx app glue; do
	emcc -c $c_opt -DIMPL -DSOKOL_WGPU --use-port=emdawnwebgpu \
		"$root/sokol-odin/sokol/c/sokol_$lib.c" -o "$work/sokol_$lib.o"
done

echo "== emcc: miniaudio and stb_image"
emcc -c $c_opt "$root/scripts/miniaudio/rocco_miniaudio.c" -o "$work/miniaudio.o"
emcc -c $c_opt -DSTBI_NO_STDIO -DSTBI_ONLY_PNG "$odin_root/vendor/stb/src/stb_image.c" -o "$work/stb_image.o"
emcc -c $c_opt "$root/scripts/web/main.c" -o "$work/main.o"
emcc -c $c_opt --use-port=emdawnwebgpu "$root/scripts/web/rocco_web.c" -o "$work/rocco_web.o"

echo "== odin: engine object"
odin build "$root/engine" -target:freestanding_wasm32 -build-mode:obj -no-entry-point \
	-default-to-nil-allocator $odin_opt -vet -strict-style -out:"$work/engine.o"

objects="$work/main.o $work/rocco_web.o $work/engine.o $work/sokol_log.o $work/sokol_gfx.o $work/sokol_app.o $work/sokol_glue.o
	$work/miniaudio.o $work/stb_image.o $root/clay/bindings/odin/clay-odin/wasm/clay.o"

# The Roc functions stay undefined here. The loader gets an unused stub for
# each, and the Roc link defines them, so the game's wasm never imports them.
# Roc links with an 8 MB stack. emscripten's 64 KB default overflows in
# renderer_init, which keeps many sokol descriptors on the stack.
echo "== emcc: reference link and loader"
# shellcheck disable=SC2086
emcc -v $objects -o "$work/index.js" \
	--use-port=emdawnwebgpu -lwebsocket.js -sDEFAULT_TO_CXX -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=8MB \
	-sFORCE_FILESYSTEM=1 -sERROR_ON_UNDEFINED_SYMBOLS=0 \
	2> "$work/emcc.log" || { cat "$work/emcc.log" >&2; exit 1; }
# The system libraries come as -l flags, and ports such as emdawnwebgpu as
# archive paths.
libs=$(grep 'wasm-ld ' "$work/emcc.log" | tr ' ' '\n' | grep -E '^-[lL]|\.a$' | tr '\n' ' ')

echo "== wasm-ld: relocatable host.o"
# shellcheck disable=SC2086
"$llvm/wasm-ld" -r -o "$target/host.o" $objects $libs
cp "$work/index.js" "$target/index.js"
cp "$work/index.wasm" "$target/reference.wasm"
cp "$root/scripts/web/index.html" "$target/index.html"
echo "== ready: $target"
