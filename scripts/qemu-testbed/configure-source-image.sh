#!/usr/bin/env bash
# configure-source-image.sh — Configure source-built OpenWrt image for testbed
#
# Mounts the rootfs partition of a source-built OpenWrt image and configures:
#   - Network: DHCP on br-lan (so dnsmasq on the bridge can assign IPs)
#   - SSH: injects authorized_keys for root login
#   - Drops root password
#
# Usage:
#   ./configure-source-image.sh [OPTIONS]
#
# Options:
#   -h, --help          — Show this help text
#   --image <path>      — Source-built image path (default: auto-detect)
#   --ssh-key <path>    — SSH public key (default: testbed/run/ssh-keys/id_rsa.pub)
#
# This script is the source-built equivalent of convert-prebuilt.sh.
# It must be run once after building the image with build-libremesh-image.sh.

set -euo pipefail

# ─── Help ───────────────────────────────────────────────────────────────────────
show_help() {
    sed -n '3,/^$/s/^# \?//p' "$0"
    exit 0
}

IMAGE_PATH=""
SSH_KEY_PATH=""

for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
        --image)
            shift
            IMAGE_PATH="${1:-}"
            [[ -z "${IMAGE_PATH}" ]] && { echo "[ERROR] --image requires a value" >&2; exit 1; }
            ;;
        --ssh-key)
            shift
            SSH_KEY_PATH="${1:-}"
            [[ -z "${SSH_KEY_PATH}" ]] && { echo "[ERROR] --ssh-key requires a value" >&2; exit 1; }
            ;;
    esac
done

# ─── Configuration ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-detect REPO_ROOT
if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="${SCRIPT_DIR}"
    while [[ "${REPO_ROOT}" != "/" ]]; do
        if [[ -f "${REPO_ROOT}/.git" || -d "${REPO_ROOT}/.git" ]]; then
            break
        fi
        REPO_ROOT="$(dirname "${REPO_ROOT}")"
    done
fi

IMAGE_DIR="${REPO_ROOT}/testbed/images"
IMAGE_PATH="${IMAGE_PATH:-${IMAGE_DIR}/libremesh-x86-64-source-built.img}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${REPO_ROOT}/testbed/run/ssh-keys/id_rsa.pub}"

# ─── Helpers ────────────────────────────────────────────────────────────────────
log() { echo "[configure-source] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() { err "$*"; exit 1; }

# ─── Preflight ──────────────────────────────────────────────────────────────────
[[ -f "${IMAGE_PATH}" ]] || die "Image not found: ${IMAGE_PATH}"
command -v fdisk >/dev/null || die "fdisk is required (install fdisk)"

# ─── Cleanup trap ───────────────────────────────────────────────────────────────
MOUNT_POINT=""

cleanup() {
    if [[ -n "${MOUNT_POINT}" ]] && mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        log "Unmounting ${MOUNT_POINT}..."
        sudo umount "${MOUNT_POINT}" || true
    fi
    if [[ -n "${MOUNT_POINT}" ]] && [[ -d "${MOUNT_POINT}" ]]; then
        rmdir "${MOUNT_POINT}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ─── Find rootfs partition offset ───────────────────────────────────────────────
# Source-built images are MBR with partition 1 = boot, partition 2 = rootfs
log "Analyzing partition table of ${IMAGE_PATH}..."

# Parse fdisk output to find partition 2 (rootfs) start sector
PART2_START=$(fdisk -l "${IMAGE_PATH}" 2>/dev/null | awk '
    /^\/dev/ && $1 ~ /2$/ {
        print $2
    }
')

if [[ -z "${PART2_START}" ]]; then
    die "Could not find partition 2 (rootfs) in ${IMAGE_PATH}. Is this a source-built combined image?"
fi

# Sector size is typically 512
SECTOR_SIZE=512
ROOTFS_OFFSET=$((PART2_START * SECTOR_SIZE))
log "Rootfs partition at sector ${PART2_START} (offset ${ROOTFS_OFFSET} bytes)"

# ─── Mount rootfs ───────────────────────────────────────────────────────────────
MOUNT_POINT="$(mktemp -d /tmp/source-rootfs.XXXXXX)"
log "Mounting rootfs at ${MOUNT_POINT}..."
sudo mount -o loop,offset="${ROOTFS_OFFSET}" "${IMAGE_PATH}" "${MOUNT_POINT}"

# ─── Configure network ─────────────────────────────────────────────────────────
log "Configuring network (DHCP on br-lan)..."

# Replace board.d/99-default_network to use DHCP instead of static 192.168.1.1
sudo tee "${MOUNT_POINT}/etc/board.d/99-default_network" > /dev/null << 'BOARDSCRIPT'
. /lib/functions/uci-defaults.sh

board_config_update

json_is_a network object && exit 0

ucidef_set_interface 'lan' device 'eth0' protocol 'dhcp'
[ -d /sys/class/net/eth1 ] && ucidef_set_interface 'wan' device 'eth1' protocol 'dhcp'

board_config_flush

exit 0
BOARDSCRIPT
sudo chmod +x "${MOUNT_POINT}/etc/board.d/99-default_network"

# Remove any existing network config so board.d regenerates it on first boot
sudo rm -f "${MOUNT_POINT}/etc/config/network"

# Also remove uci-defaults that might interfere
sudo rm -f "${MOUNT_POINT}/etc/uci-defaults/11_network-migrate-bridges" 2>/dev/null || true

log "  Network: DHCP on br-lan (eth0)"

# ─── Configure SSH ─────────────────────────────────────────────────────────────
if [[ -f "${SSH_KEY_PATH}" ]]; then
    log "Injecting SSH public key..."
    sudo mkdir -p "${MOUNT_POINT}/root/.ssh"
    sudo tee "${MOUNT_POINT}/root/.ssh/authorized_keys" > /dev/null < "${SSH_KEY_PATH}"
    sudo chmod 700 "${MOUNT_POINT}/root/.ssh"
    sudo chmod 600 "${MOUNT_POINT}/root/.ssh/authorized_keys"
    log "  SSH key: $(sudo head -1 "${MOUNT_POINT}/root/.ssh/authorized_keys" | cut -c1-40)..."
else
    log "  WARNING: SSH key not found at ${SSH_KEY_PATH}, skipping"
fi

# ─── Clear root password ───────────────────────────────────────────────────────
log "Clearing root password..."
sudo sed -i 's|^root:.*|root::0:0:99999:7:::|' "${MOUNT_POINT}/etc/shadow"

# ─── Ensure dropbear allows root login ─────────────────────────────────────────
if [[ -f "${MOUNT_POINT}/etc/config/dropbear" ]]; then
    if ! sudo grep -q "PasswordAuth 'off'" "${MOUNT_POINT}/etc/config/dropbear"; then
        log "  Ensuring dropbear allows password auth for initial setup..."
        # configure-vms.sh will lock this down later
    fi
fi

# ─── Done ───────────────────────────────────────────────────────────────────────
sync
sudo umount "${MOUNT_POINT}"
MOUNT_POINT=""  # prevent double-unmount in trap

log ""
log "Source-built image configured successfully."
log "  Image: ${IMAGE_PATH}"
log ""
log "To boot:"
log "  sudo bash scripts/qemu-testbed/start-mesh.sh"
log ""
log "The VMs will get IPs via DHCP from dnsmasq on the bridge."
log "Then run: bash scripts/qemu-testbed/configure-vms.sh"
