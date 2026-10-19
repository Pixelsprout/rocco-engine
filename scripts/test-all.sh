#!/bin/sh
# The engine tests link the debug sokol archives for this machine, so build
# those first.
set -eu
cd "$(dirname "$0")/.."

for file in examples/*/main.roc packages/*/main.roc scripts/build.roc scripts/Keys.roc; do
	[ -f "$file" ] || continue
	echo "== roc check $file"
	roc check "$file"
	echo "== roc test $file"
	roc test "$file"
done

echo "== odin test engine"
odin test engine -debug
# A Spans build compiles other code, so its tests run in a build of their own.
echo "== odin test engine with Spans"
odin test engine -debug -define:ROCCO_SPANS=true
