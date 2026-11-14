#!/bin/sh
# Screenshots a web build in headless Chrome on Linux, as CI does:
#
#   sh scripts/web/headless-shot.sh <game> <out.png> [steps]
#
# Build the page first with roc scripts/build.roc web <game>. It needs
# google-chrome and a Vulkan device with VK_KHR_surface, such as Mesa's
# lavapipe (mesa-vulkan-drivers). The CI web job and scripts/linux/web-shot.sh
# run it. Chrome's log goes next to out.png, and a failed run prints its
# console and its WebGPU lines. On macOS, use scripts/screenshot.sh --web.
set -eu
if [ $# -lt 2 ]; then
	echo "usage: scripts/web/headless-shot.sh <game> <out.png> [steps]" >&2
	exit 2
fi
mkdir -p "$(dirname "$2")"
log=$(cd "$(dirname "$2")" && pwd)/chrome.log
# Ubuntu 24.04 blocks the user namespaces that Chrome's sandbox needs.
CHROME_FLAGS="--headless=new --no-sandbox --enable-unsafe-webgpu --enable-features=Vulkan --use-angle=vulkan --disable-vulkan-surface --enable-logging=stderr --v=0"
CHROME_LOG=$log
# Headless Chrome keeps 143 pixels of the window height for its own UI, so
# this gives the 960x540 page of a native run.
CHROME_WINDOW=${CHROME_WINDOW:-960,683}
export CHROME_FLAGS CHROME_LOG CHROME_WINDOW
google-chrome --version
timeout 180 sh "$(dirname "$0")/../screenshot.sh" --web "$@" || {
	grep -E 'CONSOLE|ERROR|WebGPU|Vulkan' "$log" | tail -60
	exit 1
}
