#!/bin/sh
# Screenshots a web build in the CI web job's browser setup, from any machine
# with Docker:
#
#   sh scripts/linux/web-shot.sh <game> <out.png> [steps]
#
# Build the page on the host first with roc scripts/build.roc web <game>. The
# image runs headless Chrome with WebGPU on lavapipe, so a run that fails in
# CI fails here too. On Apple silicon, Docker emulates x86_64 and Chrome draws
# slowly. out.png must be inside the repository, which the image mounts.
set -eu
cd "$(dirname "$0")/../.."
docker build --platform linux/amd64 -t rocco-web-shot -f scripts/linux/web.Dockerfile scripts/linux
docker run --rm --platform linux/amd64 -v "$PWD":/work rocco-web-shot sh scripts/web/headless-shot.sh "$@"
