#!/usr/bin/env bash
# build-libremesh-image.sh — Build a LibreMesh x86-64 image for QEMU test bed
#
# This script clones the lime-packages SDK builder, adds the vwifi feed,
# and produces a bootable disk image suitable for QEMU.
#
# Usage:
#   ./build-libremesh-image.sh [OPTIONS]
#
# Environment variables:
#   BUILD_DIR        — Working directory for the build (default: /tmp/libremesh-build)
#   OUTPUT_DIR       — Where to copy the final image (default: <repo-root>/testbed/images)
#   REPO_ROOT        — Root of the mesha repository (auto-detected if unset)
#   VWIFI_FEED_URL   — Git URL for the vwifi feed (default: https://github.com/javierbrk/vwifi_cli_package.git)
#   VWIFI_FEED_COMMIT — Git ref for the vwifi feed (default: HEAD)
#
# Options:
#   -h, --help       — Show this help text
#   --skip-if-cached — Skip build if build-inputs.hash matches (default behaviour when hash exists)
#   --force          — Force rebuild even if hash matches
#
# Docker usage:
#   docker build -t mesha-qemu-builder -f docker/qemu-builder/Dockerfile .
#   docker run --rm -v $(pwd)/testbed/images:/output mesha-qemu-builder
#
# The build produces:
#   - libremesh-x86-64-<short-hash>-<date>.img.gz  — Compressed disk image
#   - build-manifest.yaml                           — Build metadata
#   - build-inputs.hash                             — Input hash for caching

set -euo pipefail

# ─── Help ───────────────────────────────────────────────────────────────────────
show_help() {
    sed -n '3,/^$/s/^# \?//p' "$0"
    exit 0
}

FORCE_REBUILD=false
for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
        --force) FORCE_REBUILD=true ;;
        --skip-if-cached) ;; # default behaviour
    esac
done

# ─── Configuration ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-detect REPO_ROOT: walk up from script dir until we find a marker
if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="${SCRIPT_DIR}"
    while [[ "${REPO_ROOT}" != "/" ]]; do
        if [[ -f "${REPO_ROOT}/.git" || -d "${REPO_ROOT}/.git" ]]; then
            break
        fi
        REPO_ROOT="$(dirname "${REPO_ROOT}")"
    done
fi

BUILD_DIR="${BUILD_DIR:-/tmp/libremesh-build}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/testbed/images}"
VWIFI_FEED_URL="${VWIFI_FEED_URL:-https://github.com/javierbrk/vwifi_cli_package.git}"
VWIFI_FEED_COMMIT="${VWIFI_FEED_COMMIT:-HEAD}"

LIME_REPO_URL="https://github.com/libremesh/lime-packages.git"
DEFCONFIG="${REPO_ROOT}/scripts/qemu-testbed/libremesh-testbed.defconfig"
DOCKERFILE="${REPO_ROOT}/docker/qemu-builder/Dockerfile"

# ─── Helpers ────────────────────────────────────────────────────────────────────
log()   { echo "[build] $*"; }
err()   { echo "[ERROR] $*" >&2; }
die()   { err "$*"; exit 1; }

# ─── Preflight checks ──────────────────────────────────────────────────────────
[[ -f "${DEFCONFIG}" ]]  || die "Defconfig not found: ${DEFCONFIG}"
[[ -f "${DOCKERFILE}" ]] || die "Dockerfile not found: ${DOCKERFILE}"

command -v git >/dev/null   || die "git is required"
command -v make >/dev/null  || die "make is required"

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

# ─── Step 1: Clone lime-packages ───────────────────────────────────────────────
log "Step 1: Cloning lime-packages..."
if [[ ! -d "${BUILD_DIR}/lime-packages" ]]; then
    git clone "${LIME_REPO_URL}" "${BUILD_DIR}/lime-packages"
else
    log "  lime-packages already cloned, pulling latest..."
    (cd "${BUILD_DIR}/lime-packages" && git pull --ff-only || true)
fi

LIME_COMMIT="$(cd "${BUILD_DIR}/lime-packages" && git rev-parse HEAD)"
log "  lime-packages commit: ${LIME_COMMIT:0:12}"

# ─── Step 2: Run lime-packages make (clones OpenWrt, sets up feeds) ────────────
log "Step 2: Running lime-packages make (this clones OpenWrt and sets up feeds)..."
cd "${BUILD_DIR}/lime-packages"
make

# After make, the OpenWrt tree is at lime-packages/openwrt
OPENWRT_DIR="${BUILD_DIR}/lime-packages/openwrt"
[[ -d "${OPENWRT_DIR}" ]] || die "OpenWrt directory not found after make: ${OPENWRT_DIR}"

OPENWRT_VERSION=""
if [[ -f "${OPENWRT_DIR}/.git/refs/heads/main" ]]; then
    OPENWRT_VERSION="$(cat "${OPENWRT_DIR}/.git/refs/heads/main")"
elif [[ -f "${OPENWRT_DIR}/.git/refs/heads/master" ]]; then
    OPENWRT_VERSION="$(cat "${OPENWRT_DIR}/.git/refs/heads/master")"
else
    OPENWRT_VERSION="$(cd "${OPENWRT_DIR}" && git rev-parse HEAD)"
fi
log "  OpenWrt version: ${OPENWRT_VERSION:0:12}"

cd "${OPENWRT_DIR}"

# ─── Step 3: Add vwifi feed ────────────────────────────────────────────────────
log "Step 3: Adding vwifi feed..."
if ! grep -q "src-git vwifi" feeds.conf 2>/dev/null; then
    echo "src-git vwifi ${VWIFI_FEED_URL}" >> feeds.conf
else
    log "  vwifi feed already in feeds.conf"
fi

# ─── Step 4: Update and install feeds ──────────────────────────────────────────
log "Step 4: Updating and installing feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# Pin vwifi feed to specific commit if requested
if [[ -n "${VWIFI_FEED_COMMIT}" && "${VWIFI_FEED_COMMIT}" != "HEAD" ]]; then
    log "  Pinning vwifi feed to commit: ${VWIFI_FEED_COMMIT}"
    (cd "${OPENWRT_DIR}/feeds/vwifi" && git checkout "${VWIFI_FEED_COMMIT}" 2>/dev/null) || \
        log "  WARN: Could not pin vwifi feed to ${VWIFI_FEED_COMMIT}"
fi

# ─── Compute input hash AFTER feeds are cloned/updated ─────────────────────────
compute_input_hash() {
    local hash_input=""
    hash_input+="$(cat "$0")"
    hash_input+=$(cat "${DEFCONFIG}")
    hash_input+=$(cat "${DOCKERFILE}")

    # Include feed commit hashes (now available after clone/update)
    hash_input+=$(cd "${BUILD_DIR}/lime-packages" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    hash_input+=$(cd "${OPENWRT_DIR}" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    if [[ -d "${OPENWRT_DIR}/feeds/vwifi" ]]; then
        hash_input+=$(cd "${OPENWRT_DIR}/feeds/vwifi" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    fi

    echo -n "${hash_input}" | sha256sum | awk '{print $1}'
}

CURRENT_HASH="$(compute_input_hash)"
CACHED_HASH_FILE="${OUTPUT_DIR}/build-inputs.hash"

if [[ "${FORCE_REBUILD}" == "false" ]] && [[ -f "${CACHED_HASH_FILE}" ]]; then
    CACHED_HASH="$(cat "${CACHED_HASH_FILE}")"
    if [[ "${CURRENT_HASH}" == "${CACHED_HASH}" ]]; then
        log "Build inputs unchanged (hash: ${CURRENT_HASH:0:12}). Skipping build."
        log "Use --force to rebuild."
        exit 0
    fi
fi

log "Build input hash: ${CURRENT_HASH:0:12}"

# ─── Step 5: Copy defconfig ────────────────────────────────────────────────────
log "Step 5: Applying defconfig..."
cp "${DEFCONFIG}" .config

# ─── Step 6: Expand defconfig ──────────────────────────────────────────────────
log "Step 6: Expanding defconfig..."
make defconfig

# ─── Step 7: Verify vwifi is enabled ───────────────────────────────────────────
log "Step 7: Verifying vwifi-client package..."
VWIFI_LINE="$(grep 'CONFIG_PACKAGE_vwifi-client' .config || true)"
if echo "${VWIFI_LINE}" | grep -q 'is not set' || [[ -z "${VWIFI_LINE}" ]]; then
    err "vwifi-client is NOT enabled in .config!"
    err "  Got: ${VWIFI_LINE:-'(not found)'}"
    die "Cannot build without vwifi-client. Check that the vwifi feed was added correctly."
fi
log "  vwifi-client: ${VWIFI_LINE}"

# ─── Step 8: Build ─────────────────────────────────────────────────────────────
log "Step 8: Building (this will take a while)..."
make -j"$(nproc)"

# ─── Post-build: copy image ────────────────────────────────────────────────────
log "Copying image to output directory..."
SOURCE_IMG="${OPENWRT_DIR}/bin/targets/x86/64/openwrt-x86-64-generic-ext4-rootfs.img.gz"
if [[ ! -f "${SOURCE_IMG}" ]]; then
    # Try alternative names
    SOURCE_IMG="$(find "${OPENWRT_DIR}/bin/targets/x86/64/" -name '*-ext4-rootfs.img.gz' -o -name '*-combined-ext4.img.gz' | head -1)"
fi
[[ -f "${SOURCE_IMG}" ]] || die "Built image not found in bin/targets/x86/64/"

SHORT_HASH="${CURRENT_HASH:0:12}"
DATE_STAMP="$(date +%Y%m%d)"
DEST_NAME="libremesh-x86-64-${SHORT_HASH}-${DATE_STAMP}.img.gz"

cp "${SOURCE_IMG}" "${OUTPUT_DIR}/${DEST_NAME}"
log "Image copied: ${OUTPUT_DIR}/${DEST_NAME}"

# ─── Image size verification (Gate 1.1: must be >50MB) ────────────────────────
IMAGE_SIZE=$(stat -c%s "${OUTPUT_DIR}/${DEST_NAME}" 2>/dev/null || stat -f%z "${OUTPUT_DIR}/${DEST_NAME}")
MIN_IMAGE_SIZE=$((50 * 1024 * 1024))  # 50 MB
if [[ "${IMAGE_SIZE}" -lt "${MIN_IMAGE_SIZE}" ]]; then
    die "Image size verification FAILED: ${IMAGE_SIZE} bytes < 50MB minimum (Gate 1.1)"
fi
log "Image size verification passed: $((IMAGE_SIZE / 1024 / 1024)) MB >= 50 MB"

# ─── Generate build-manifest.yaml ──────────────────────────────────────────────
log "Generating build-manifest.yaml..."

# Get vwifi commit
VWIFI_COMMIT="unknown"
VWIFI_FEED_DIR="${OPENWRT_DIR}/feeds/vwifi"
if [[ -d "${VWIFI_FEED_DIR}" ]]; then
    VWIFI_COMMIT="$(cd "${VWIFI_FEED_DIR}" && git rev-parse HEAD 2>/dev/null || echo "unknown")"
fi

PACKAGE_LIST="$(grep '=y' .config | sort)"

cat > "${OUTPUT_DIR}/build-manifest.yaml" <<EOF
# LibreMesh QEMU test bed — build manifest
# Auto-generated by build-libremesh-image.sh

build_date: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
image_file: "${DEST_NAME}"
lime_packages_commit: "${LIME_COMMIT}"
openwrt_version: "${OPENWRT_VERSION}"
vwifi_commit: "${VWIFI_COMMIT}"
build_input_hash: "${CURRENT_HASH}"

package_list:
$(echo "${PACKAGE_LIST}" | sed 's/^/  - /')
EOF

log "Manifest written: ${OUTPUT_DIR}/build-manifest.yaml"

# ─── Write build-inputs.hash ───────────────────────────────────────────────────
echo "${CURRENT_HASH}" > "${CACHED_HASH_FILE}"
log "Hash file written: ${CACHED_HASH_FILE}"

log "Build complete!"
log "  Image: ${OUTPUT_DIR}/${DEST_NAME}"
log "  Manifest: ${OUTPUT_DIR}/build-manifest.yaml"
