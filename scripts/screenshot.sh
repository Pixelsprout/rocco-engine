#!/bin/sh
# Usage: scripts/screenshot.sh [--web] <game> <out.png> [steps]
# Runs a built game from examples/ with the Bridge, runs [steps] fixed steps
# with no Input (default: one second of steps), saves the frame to out.png
# and quits the game. ROCCO_* variables pass through to the game. PYTHON
# names the Python 3 to run (default: python3).
#
# --web runs the page from roc scripts/build.roc web <game> instead. It
# starts a Relay, a static server and Chrome on ?bridge=P, and makes the
# same Bridge calls. CHROME names the Chrome program, CHROME_WINDOW the
# window size (default: 960,540) and CHROME_FLAGS adds switches, such as
# the headless WebGPU ones that CI passes. CHROME_LOG names a file for
# Chrome's output, which holds the page's console with --enable-logging=stderr.
# On macOS, headless Chrome stops
# requestAnimationFrame, so leave the window open there.
set -eu

web=0
if [ "${1:-}" = "--web" ]; then
	web=1
	shift
fi
if [ $# -lt 2 ]; then
	echo "usage: scripts/screenshot.sh [--web] <game> <out.png> [steps]" >&2
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

ROCCO_BRIDGE=${ROCCO_BRIDGE:-$("$python" scripts/bridge.py free-port)}
export ROCCO_BRIDGE

if [ "$web" = 1 ]; then
	# tutorial/08-sound builds build/web/08-sound.
	page=build/web/${game##*/}
	if [ ! -f "$page/index.wasm" ]; then
		echo "screenshot: $page/index.wasm is missing. Run roc scripts/build.roc web $game first." >&2
		exit 2
	fi
	if [ -z "${CHROME:-}" ]; then
		case $(uname -s) in
		Darwin) CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ;;
		*) CHROME=google-chrome ;;
		esac
	fi
	http_port=$("$python" scripts/bridge.py free-port)
	profile=$(mktemp -d)
	"$python" scripts/bridge.py relay --port "$ROCCO_BRIDGE" &
	relay=$!
	"$python" -m http.server "$http_port" --bind 127.0.0.1 --directory "$page" > /dev/null 2>&1 &
	server=$!
	# A scale factor of 1 gives the native size on a high-dpi screen.
	# shellcheck disable=SC2086
	"$CHROME" --user-data-dir="$profile" --no-first-run --no-default-browser-check \
		--force-color-profile=srgb --force-device-scale-factor=1 --window-size="${CHROME_WINDOW:-960,540}" \
		${CHROME_FLAGS:-} "http://127.0.0.1:$http_port/index.html?bridge=$ROCCO_BRIDGE" > "${CHROME_LOG:-/dev/null}" 2>&1 &
	browser=$!
	# Chrome's helper processes can still write to the profile after the main
	# one exits, so a failed removal must not fail the screenshot.
	trap 'kill "$relay" "$server" "$browser" 2>/dev/null || true; wait "$browser" 2>/dev/null || true; rm -rf "$profile" 2>/dev/null || true' EXIT
else
	# eval "$(...)" would hide a build.roc failure from set -e.
	target_lines=$(roc scripts/build.roc target)
	eval "$target_lines"

	dir=examples/$game
	# tutorial/01-window builds 01-window.bin.
	name=${game##*/}$suffix
	if [ ! -x "$dir/$name" ]; then
		echo "screenshot: $dir/$name is missing. Run roc scripts/build.roc game $game first." >&2
		exit 2
	fi

	# The game runs from its own directory, as roc run does, so it finds assets/.
	(cd "$dir" && exec "./$name") &
	pid=$!
	trap 'kill "$pid" 2>/dev/null || true' EXIT
fi

hello=$("$python" scripts/bridge.py --wait 60 hello)
if [ -z "$steps" ]; then
	steps=$(echo "$hello" | sed 's/.*"step_hz":\([0-9]*\).*/\1/')
fi
"$python" scripts/bridge.py step "$steps" > /dev/null
"$python" scripts/bridge.py screenshot "$out"
"$python" scripts/bridge.py quit > /dev/null
if [ "$web" = 1 ]; then
	# The Relay exits after it forwards the quit reply.
	wait "$relay"
else
	wait "$pid"
	trap - EXIT
fi
