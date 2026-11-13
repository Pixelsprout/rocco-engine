#!/bin/sh
# Builds the web lit slice for the web into spikes/web-lit/build/page and,
# on macOS, natively into spikes/web-lit/build/native. Run it through
# scripts/toolchain.sh run, so odin and emcc are the pins.
#
#   sh scripts/toolchain.sh run sh spikes/web-lit/build.sh [web|native|all]
#
# The native build links the macOS sokol archives from scripts/macos.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=$here/build
which=${1:-all}

# The surface packs build into the build folder, so the examples stay as
# they are and CI needs no game build first.
assets() {
	mkdir -p "$1/meshes" "$1/shaders"
	cp "$root"/examples/glow/assets/meshes/salvage.glb "$root"/examples/glow/assets/meshes/panel.glb \
		"$root"/examples/glow/assets/meshes/tube.glb "$1/meshes/"
	(cd "$root/examples/surface" && python3 "$root/platform/shader-tools/build.py" --install \
		--out "$work/surface/shaders" --helpers "$work/surface/helpers")
	cp "$work/surface/shaders/IndirectSurface.shaderpack" "$1/shaders/"
}

web() {
	page=$work/page
	rm -rf "$work/web" "$page"
	mkdir -p "$work/web/sokol" "$page"

	# The pinned sokol_gfx.h builds the WebGPU dynamic offset map at the
	# sokol slot index, so a shader with sparse uniform slots, as every
	# custom pack has, reads the wrong uniforms. Upstream sokol indexes it by
	# the bind group entry. The copy here takes that one-line fix.
	echo "== emcc: sokol for WebGPU"
	cp -R "$root/sokol-odin/sokol/c" "$work/web/sokol-c"
	sed -i.orig -e 's/dynoffset_map\[i\]\.sokol_slot = (uint8_t)i;/dynoffset_map[bgl_index].sokol_slot = (uint8_t)i;/' \
		-e 's/dynoffset_map\[i\]\.wgpu_slot = (uint8_t)bgl_entry->binding;/dynoffset_map[bgl_index].wgpu_slot = (uint8_t)bgl_entry->binding;/' \
		"$work/web/sokol-c/sokol_gfx.h"
	if [ "$(grep -c 'dynoffset_map\[bgl_index\]' "$work/web/sokol-c/sokol_gfx.h")" != 2 ]; then
		echo "build.sh: the sokol_gfx.h dynoffset fix did not apply" >&2
		exit 1
	fi
	for lib in log gfx app glue; do
		emcc -c -g -DIMPL -DSOKOL_WGPU --use-port=emdawnwebgpu \
			"$work/web/sokol-c/sokol_$lib.c" -o "$work/web/sokol/sokol_$lib.o"
	done

	echo "== slice: engine copy"
	sh "$here/slice.sh" "$work/web/slice"

	echo "== odin: host object"
	odin build "$here/host" -target:freestanding_wasm32 -build-mode:obj -no-entry-point \
		-default-to-nil-allocator -collection:rocco="$root" \
		-collection:slice="$work/web/slice" -collection:spike="$here" -out:"$work/web/host_odin.o"
	emcc -c "$here/host/main.c" -o "$work/web/main.o"

	# emscripten's default 64 KB stack overflows in renderer_init, which keeps
	# many sokol descriptors on the stack.
	echo "== emcc: page"
	assets "$work/web/assets"
	emcc "$work/web/main.o" "$work/web/host_odin.o" "$work/web/sokol/"*.o \
		"$root/clay/bindings/odin/clay-odin/wasm/clay.o" \
		-o "$page/index.html" --shell-file "$here/host/shell.html" \
		--use-port=emdawnwebgpu -sDEFAULT_TO_CXX -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=4MB --profiling-funcs \
		--preload-file "$work/web/assets@/assets"
	echo "== ready: $page"
}

# The native twin imports the real engine through the slice collection.
native() {
	out=$work/native
	rm -rf "$out"
	mkdir -p "$out"
	assets "$out/assets"
	odin build "$here/native" -debug -collection:rocco="$root" -collection:slice="$root" \
		-collection:spike="$here" -out:"$out/web-lit.bin"
	echo "== ready: $out/web-lit.bin"
}

case $which in
web) web ;;
native) native ;;
all)
	web
	native
	;;
*)
	echo "usage: build.sh [web|native|all]" >&2
	exit 2
	;;
esac
