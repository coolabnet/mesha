FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake g++ pkg-config \
    libncurses-dev zlib1g-dev gawk git gettext \
    libssl-dev rsync swig unzip wget python3 \
    libnl-3-dev libnl-genl-3-dev \
    qemu-utils ccache \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY scripts/qemu-testbed/build-libremesh-image.sh /build/build.sh
COPY scripts/qemu-testbed/libremesh-testbed.defconfig /build/defconfig

RUN chmod +x /build/build.sh

ENV OUTPUT_DIR=/output
ENV REPO_ROOT=/build

CMD ["/build/build.sh"]
