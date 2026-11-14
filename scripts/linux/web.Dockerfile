# The web shot image: headless Chrome with WebGPU on Mesa's lavapipe, as on
# the CI web runner. scripts/linux/web-shot.sh builds and runs it. It runs a
# page that the host has built, so it needs no Odin, Roc or emsdk.
FROM ubuntu:24.04

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl python3 mesa-vulkan-drivers libvulkan1 && \
    curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/chrome.deb && \
    rm -rf /tmp/chrome.deb /var/lib/apt/lists/*

WORKDIR /work
