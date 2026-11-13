#!/bin/sh
# Runs the native twin under the Bridge, takes frame N and quits.
#
#   sh spikes/web-lit/native-shot.sh <out.png> [N]
#
# Build it first with build.sh native. N defaults to 30, the frame that the
# web host reports.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
steps=${2:-30}
bridge="python3 $root/scripts/bridge.py"
port=$($bridge free-port)
cd "$here/build/native"
ROCCO_BRIDGE=$port ./web-lit.bin > run.log 2>&1 &
pid=$!
$bridge --port "$port" --wait 60 hello > /dev/null
# Lockstep draws one Frame per step, so step N leaves frame N on screen.
$bridge --port "$port" step "$steps" > /dev/null
$bridge --port "$port" screenshot "$out"
$bridge --port "$port" quit > /dev/null
wait "$pid"
cat run.log
