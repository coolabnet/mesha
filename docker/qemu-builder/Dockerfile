FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake g++ pkg-config \
    libncurses-dev zlib1g-dev gawk git gettext \
    libssl-dev rsync swig unzip wget python3 \
    libnl-3-dev libnl-genl-3-dev \
    qemu-utils ccache ca-certificates file \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy files preserving directory structure matching REPO_ROOT-relative paths
# so that build-libremesh-image.sh can find them at /build/scripts/... etc.
COPY scripts/qemu-testbed/build-libremesh-image.sh /build/scripts/qemu-testbed/build-libremesh-image.sh
COPY scripts/qemu-testbed/libremesh-testbed.defconfig /build/scripts/qemu-testbed/libremesh-testbed.defconfig
COPY docker/qemu-builder/Dockerfile /build/docker/qemu-builder/Dockerfile

RUN chmod +x /build/scripts/qemu-testbed/build-libremesh-image.sh

ENV OUTPUT_DIR=/output
ENV REPO_ROOT=/build

CMD ["/build/scripts/qemu-testbed/build-libremesh-image.sh"]
