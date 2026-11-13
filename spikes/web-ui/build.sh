#!/bin/sh
# Builds the web UI spike page into spikes/web-ui/build/page.
# Run it through scripts/toolchain.sh run, so odin and emcc are the pins.
#
#   sh scripts/toolchain.sh run sh spikes/web-ui/build.sh
#
# It needs build/shader-tools/sokol-shdc: python3 scripts/shader_contract/install.py
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=$here/build
slice=$work/engine
page=$work/page
shdc=${ROCCO_SHDC:-$root/build/shader-tools/sokol-shdc}

rm -rf "$work"
mkdir -p "$work/sokol" "$slice" "$page"

echo "== emcc: sokol for WebGPU"
for lib in log gfx app glue; do
	emcc -c -g -DIMPL -DSOKOL_WGPU --use-port=emdawnwebgpu \
		"$root/sokol-odin/sokol/c/sokol_$lib.c" -o "$work/sokol/sokol_$lib.o"
done

# The engine's shader file also holds the lit pass, which does not compile to
# WGSL yet. The UI program and its srgb block compile on their own.
echo "== sokol-shdc: UI shader as WGSL"
{
	echo "@header package engine"
	echo "@header import sg \"rocco:sokol-odin/sokol/gfx\""
	sed -n '/^@block srgb$/,/^@end$/p' "$root/engine/shaders/basic.glsl"
	sed -n '/^@vs ui_vs$/,/^@program ui ui_vs ui_fs$/p' "$root/engine/shaders/basic.glsl"
} > "$work/ui.glsl"
"$shdc" -i "$work/ui.glsl" -o "$slice/shader_ui_wgsl.odin" -l wgsl -f sokol_odin

# The full engine package does not build for wasm yet. The slice is a copy of
# the UI files with their imports moved onto the rocco collection, plus stubs
# for the renderer parts they touch.
echo "== slice: engine UI files"
for file in ui.odin ui_render.odin font.odin font_baked.odin vocabulary.odin roc_platform_abi.odin; do
	sed -e 's#"\.\./#"rocco:#' -e 's#^import "core:fmt"$#import fmt "spike:webfmt"#' \
		"$root/engine/$file" > "$slice/$file"
done
cp "$here/slice/"*.odin "$slice/"

echo "== odin: host object"
odin build "$here/host" -target:freestanding_wasm32 -build-mode:obj -no-entry-point \
	-default-to-nil-allocator -vet -strict-style -collection:rocco="$root" \
	-collection:slice="$work" -collection:spike="$here" -out:"$work/host_odin.o"
emcc -c "$here/host/main.c" -o "$work/main.o"

echo "== emcc: page"
emcc "$work/main.o" "$work/host_odin.o" "$work/sokol/"*.o \
	"$root/clay/bindings/odin/clay-odin/wasm/clay.o" \
	-o "$page/index.html" --shell-file "$here/host/shell.html" \
	--use-port=emdawnwebgpu -sDEFAULT_TO_CXX -sALLOW_MEMORY_GROWTH=1
echo "== ready: $page"
