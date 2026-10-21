#!/bin/sh
# Usage: scripts/screenshot.sh <game> <out.png> [steps]
# Runs a built game from examples/ with the Bridge, runs [steps] fixed steps
# with no Input (default: one second of steps), saves the frame to out.png
# and quits the game. ROCCO_* variables pass through to the game. PYTHON
# names the Python 3 to run (default: python3).
set -eu

if [ $# -lt 2 ]; then
	echo "usage: scripts/screenshot.sh <game> <out.png> [steps]" >&2
	exit 2
fi
game=$1
# bridge.py runs from the repo root, so make out.png absolute first.
case $2 in
/* | [A-Za-z]:*) out=$2 ;;
*) out=$PWD/$2 ;;
esac
steps=${3:-}
python=${PYTHON:-python3}

cd "$(dirname "$0")/.."

# eval "$(...)" would hide a build.roc failure from set -e.
target_lines=$(roc scripts/build.roc -- target)
eval "$target_lines"

dir=examples/$game
# tutorial/01-window builds 01-window.bin.
name=${game##*/}$suffix
if [ ! -x "$dir/$name" ]; then
	echo "screenshot: $dir/$name is missing. Run roc scripts/build.roc -- game $game first." >&2
	exit 2
fi

ROCCO_BRIDGE=${ROCCO_BRIDGE:-$("$python" scripts/bridge.py free-port)}
export ROCCO_BRIDGE

# The game runs from its own directory, as roc run does, so it finds assets/.
(cd "$dir" && exec "./$name") &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT

hello=$("$python" scripts/bridge.py --wait 60 hello)
if [ -z "$steps" ]; then
	steps=$(echo "$hello" | sed 's/.*"step_hz":\([0-9]*\).*/\1/')
fi
"$python" scripts/bridge.py step "$steps" > /dev/null
"$python" scripts/bridge.py screenshot "$out"
"$python" scripts/bridge.py quit > /dev/null
wait "$pid"
trap - EXIT
