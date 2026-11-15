#!/bin/sh
# Screenshots a web build in the CI web job's browser setup, from any machine
# with Docker:
#
#   sh scripts/linux/web-shot.sh <game> <out.png> [steps]
#
# Build the page on the host first with roc scripts/build.roc web <game>. The
# image runs headless Chrome with WebGPU on lavapipe, so a run that fails in
# CI fails here too. On Apple silicon, Docker emulates x86_64 and Chrome draws
# slowly. A relative out.png is read from the repository root.
set -eu
if [ $# -lt 2 ]; then
	echo "usage: sh scripts/linux/web-shot.sh <game> <out.png> [steps]" >&2
	exit 2
fi
cd "$(dirname "$0")/../.."
root=$(pwd -P)
game=$1
out=$2
shift 2

# The image mounts only the repository, so a PNG outside it never reaches the host.
mkdir -p "$(dirname "$out")"
dir=$(cd "$(dirname "$out")" && pwd -P)
case "$dir/" in
"$root"/*) ;;
*)
	echo "web-shot.sh: $out is outside $root. The image mounts only the repository." >&2
	exit 2
	;;
esac
rel=${dir#"$root"}/$(basename "$out")
rel=${rel#/}
rm -f "$rel"

docker build --platform linux/amd64 -t rocco-web-shot -f scripts/linux/web.Dockerfile scripts/linux
docker run --rm --platform linux/amd64 -v "$root":/work rocco-web-shot sh scripts/web/headless-shot.sh "$game" "$rel" "$@"
if [ ! -s "$rel" ]; then
	echo "web-shot.sh: the run ended but wrote no $rel." >&2
	exit 1
fi
echo "web-shot.sh: wrote $rel"
