#!/bin/sh
# Serves a web build, opens it in a Chrome window and saves a screenshot.
# Headless Chrome on macOS stops requestAnimationFrame after one frame, so
# this needs a window.
#
#   sh scripts/web/shot.sh <page dir> <out.png> [seconds]
#
# Build the page first with roc scripts/build.roc web <game>. CHROME and NODE
# override the programs. CHROME_FLAGS adds Chrome switches, such as
# --disable-gpu to see the message a browser with no WebGPU adapter shows.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
page=$(cd "$1" && pwd)
out=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
seconds=${3:-8}
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
node=${NODE:-$(ls -d "$HOME"/tools/emsdk/node/*/bin/node | tail -n 1)}
http_port=$(python3 "$root/scripts/bridge.py" free-port)
devtools_port=$(python3 "$root/scripts/bridge.py" free-port)
profile=$(mktemp -d)

python3 -m http.server "$http_port" --bind 127.0.0.1 --directory "$page" > /dev/null 2>&1 &
server=$!
"$chrome" --user-data-dir="$profile" --remote-debugging-port="$devtools_port" \
	--no-first-run --no-default-browser-check --force-color-profile=srgb --window-size=1400,900 ${CHROME_FLAGS:-} about:blank > /dev/null 2>&1 &
browser=$!
trap 'kill $server $browser 2> /dev/null || true; wait $browser 2> /dev/null || true; rm -rf "$profile"' EXIT

tries=0
until curl -s "http://127.0.0.1:$devtools_port/json/version" > /dev/null; do
	tries=$((tries + 1))
	[ "$tries" -lt 50 ] || { echo "Chrome did not open its DevTools port" >&2; exit 1; }
	sleep 0.2
done
"$node" "$here/shot.mjs" "$devtools_port" "http://127.0.0.1:$http_port/index.html" "$out" "$seconds"
