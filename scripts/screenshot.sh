#!/bin/sh
# Usage: scripts/screenshot.sh <game> <out.png> [delay seconds]
# Runs a built game from examples/, waits, saves its window to
# out.png and stops the game. ROCCO_* variables pass through to the game.
# macOS only. Builds scripts/macos/wincap.swift into build/ when it changes.
set -eu
cd "$(dirname "$0")/.."

if [ $# -lt 2 ]; then
	echo "usage: scripts/screenshot.sh <game> <out.png> [delay seconds]" >&2
	exit 2
fi
game=$1
out=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
delay=${3:-3}

dir=examples/$game
bin=$dir/$game.bin
if [ ! -x "$bin" ]; then
	echo "screenshot: $bin is missing. Run roc scripts/build.roc -- game $game first." >&2
	exit 2
fi

tool=build/wincap
if [ ! -x "$tool" ] || [ scripts/macos/wincap.swift -nt "$tool" ]; then
	mkdir -p build
	swiftc -O scripts/macos/wincap.swift -o "$tool"
fi

# The game runs from its own directory, as roc run does, so it finds assets/.
(cd "$dir" && exec "./$game.bin") &
pid=$!
sleep "$delay"
status=0
"$tool" "$pid" "$out" || status=$?
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
exit $status
