#!/bin/sh
# Type-checks and tests each bench game, Odin twin and the Roc heap micro
# benchmark. scripts/test-all.sh reads only examples/ and packages/, so the
# bench games need this script.
set -eu
cd "$(dirname "$0")/.."

for file in bench/*/main.roc; do
	echo "== roc check $file"
	roc check "$file"
	echo "== roc test $file"
	roc test "$file"
done

# odin rejects an output path without .exe on Windows.
ext=
[ "${OS:-}" = Windows_NT ] && ext=.exe

for file in bench/*/main.odin; do
	dir=$(dirname "$file")
	echo "== odin test $dir"
	mkdir -p build
	odin test "$dir" -debug -vet -strict-style "-out:build/$(basename "$dir")-test$ext"
done
