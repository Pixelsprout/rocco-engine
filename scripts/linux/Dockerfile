# The Linux build image for rocco. Builds the x64glibc target and runs the
# check. Ubuntu 24.04, x86_64. Build with --platform linux/amd64, as
# scripts/linux/check.sh does. On Apple silicon Docker runs it under emulation.
FROM ubuntu:24.04

ARG ODIN_RELEASE=dev-2026-11
# The Roc release tag. `roc version` prints it.
ARG ROC_RELEASE=0.1.0_RC1
# ROC_RELEASE as the `roc` entry of a .roc header spells it. The header
# parser does not accept the tag form.
ARG ROC_PIN=0.1.0-rc1
# The roc-lang/roc commit of ROC_RELEASE. scripts/roc_patches.py applies the
# carried Roc patches to it.
ARG ROC_COMMIT=15177e91f62cafddf5336c455e00e9f05427ac16
# The Zig that builds the Tour compile worker (scripts/tour_worker.py). Roc's
# build.zig.zon asks for it.
ARG ZIG_VERSION=0.17.0

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils \
        build-essential clang llvm binutils \
        libx11-dev libxi-dev libxcursor-dev libgl-dev libglx-mesa0 xvfb \
        python3 git \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/odin && curl -fsSL \
        "https://github.com/odin-lang/Odin/releases/download/${ODIN_RELEASE}/odin-linux-amd64-${ODIN_RELEASE}.tar.gz" \
    | tar xz -C /opt/odin --strip-components=1

RUN mkdir -p /opt/roc && curl -fsSL \
        "https://github.com/roc-lang/roc/releases/download/${ROC_RELEASE}/roc-linux_x86_64-${ROC_RELEASE}.tar.gz" \
    | tar xz -C /opt/roc --strip-components=1

ENV PATH="/opt/odin:/opt/roc:${PATH}"
WORKDIR /work

# The web job and scripts/toolchain.sh read this pin. This image does not
# install emsdk. The pin sits last, so a change does not rebuild the layers above.
ARG EMSDK_VERSION=7.0.0
