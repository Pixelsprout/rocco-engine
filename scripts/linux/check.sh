#!/bin/sh
# Build the Linux image, then build and run examples/bodies for x64glibc inside it.
# Needs Docker.
set -eu
cd "$(dirname "$0")/../.."
start=$(date +%s)
docker build --platform linux/amd64 -t rocco-linux scripts/linux
docker run --rm --platform linux/amd64 -v "$PWD":/work rocco-linux sh scripts/linux/in-container.sh
echo "== check.sh took $(( $(date +%s) - start ))s"
