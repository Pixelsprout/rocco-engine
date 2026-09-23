# The Linux build image for rocco. Builds the x64glibc target and runs the
# check. Ubuntu 24.04, x86_64. Build with --platform linux/amd64, as
# scripts/linux/check.sh does. On Apple silicon Docker runs it under emulation.
FROM ubuntu:24.04

ARG ODIN_RELEASE=dev-2026-08
ARG ROC_NIGHTLY=2026-09-12-220fd47

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils \
        build-essential clang llvm binutils \
        libx11-dev libxi-dev libxcursor-dev libgl-dev libglx-mesa0 xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/odin && curl -fsSL \
        "https://github.com/odin-lang/Odin/releases/download/${ODIN_RELEASE}/odin-linux-amd64-${ODIN_RELEASE}.tar.gz" \
    | tar xz -C /opt/odin --strip-components=1

RUN mkdir -p /opt/roc && curl -fsSL \
        "https://github.com/roc-lang/nightlies/releases/download/nightly-${ROC_NIGHTLY}/roc_nightly-linux_x86_64-${ROC_NIGHTLY}.tar.gz" \
    | tar xz -C /opt/roc --strip-components=1

ENV PATH="/opt/odin:/opt/roc:${PATH}"
WORKDIR /work
