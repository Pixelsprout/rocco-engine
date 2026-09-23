#!/bin/sh
# Build the Linux image and link examples/bodies for x64glibc inside it.
# Needs Docker.
set -eu
cd "$(dirname "$0")/../.."
docker build --platform linux/amd64 -t rocco-linux scripts/linux
docker run --rm --platform linux/amd64 -v "$PWD":/work rocco-linux sh scripts/linux/in-container.sh
