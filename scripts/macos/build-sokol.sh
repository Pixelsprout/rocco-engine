#!/bin/sh
# Same flags as build_lib_arm64_debug and build_lib_arm64_release in
# sokol-odin/sokol/build_clibs_macos.sh, for only the four modules the
# engine links. The engine tests link the debug archives.
set -eu
cd "$(dirname "$0")/../../sokol-odin/sokol"

o=$(mktemp)
trap 'rm -f "$o"' EXIT

echo "== sokol Metal archives"
for m in log gfx app glue; do
	source="c/sokol_$m.c"
	MACOSX_DEPLOYMENT_TARGET=10.13 clang -c -g -x objective-c -arch arm64 -DIMPL -DSOKOL_METAL "$source" -o "$o"
	archive="$m/sokol_${m}_macos_arm64_metal_debug.a"
	rm -f "$archive"
	ar rcs "$archive" "$o"
	MACOSX_DEPLOYMENT_TARGET=10.13 clang -c -O2 -x objective-c -arch arm64 -DNDEBUG -DIMPL -DSOKOL_METAL "$source" -o "$o"
	archive="$m/sokol_${m}_macos_arm64_metal_release.a"
	rm -f "$archive"
	ar rcs "$archive" "$o"
done
