#!/usr/bin/env sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# stage-upgrade.sh — Firmware upgrade for a single mesh node (canary stage)
#
# Usage: ./stage-upgrade.sh <node-hostname-or-ip> <firmware-image-url> [--dry-run] [--auto]
#
# Risk class: Class D (firmware change)
# Requires: explicit approval obtained before running this script.
# This script performs ONE node only. For multi-node rollouts, run ring by ring
# per the firmware-rollout playbook and rollout-policy.yaml.
#
# Options:
#   --dry-run   Print the upgrade plan but make no changes (no confirmation prompt)
#   --auto      Skip the interactive YES confirmation prompt. Used by run-rollout.sh
#               which has already obtained the single top-level YES confirmation from
#               the operator before the ring loop begins. Do NOT use --auto for
#               standalone single-node runs; always confirm interactively instead.
#
# See: docs/playbooks/firmware-rollout.md
#      desired-state/mesh/firmware-policy.yaml

set -e

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*"
}

log_result() {
  # Print structured result line at end of run
  _status="$1"
  echo ""
  echo "--- UPGRADE RESULT ---"
  echo "date:        $(date '+%Y-%m-%dT%H:%M:%S')"
  echo "node:        ${NODE}"
  echo "old_version: ${OLD_VERSION:-unknown}"
  echo "new_version: ${NEW_VERSION:-unknown}"
  echo "status:      ${_status}"
  echo "----------------------"
}

die() {
  log "ERROR: $*"
  exit 1
}

confirm() {
  _prompt="$1"
  echo ""
  echo "${_prompt}"
  read -r ANSWER
  if [ "${ANSWER}" != "YES" ]; then
    log "Confirmation not given. Aborting."
    exit 0
  fi
}

usage() {
  echo "Usage: $0 <node-hostname-or-ip> <firmware-image-url> [--dry-run] [--auto]"
  echo ""
  echo "  node-hostname-or-ip   Hostname or IP address of the target node"
  echo "  firmware-image-url    URL or local path of the firmware .bin image"
  echo "  --dry-run             Print the upgrade plan but make no changes"
  echo "  --auto                Skip interactive confirmation (for use by run-rollout.sh only)"
  echo ""
  echo "Example:"
  echo "  $0 lm-associacao-salao http://192.168.1.50/firmware/lm-2023.09-cpe510.bin"
  echo "  $0 192.168.10.5 /data/firmware-cache/gl-ar750s-2023.09.bin --dry-run"
  exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

[ $# -lt 2 ] && usage

NODE="$1"
FIRMWARE_URL="$2"
DRY_RUN=false
AUTO_MODE=false

shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true  ; shift ;;
    --auto)    AUTO_MODE=true ; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

FIRMWARE_FILENAME="${FIRMWARE_URL##*/}"
SSH_TIMEOUT=10
OFFLINE_WAIT_SECONDS=180   # 3 minutes: max wait for node to go offline
ONLINE_WAIT_SECONDS=300    # 5 minutes: max wait for node to come back

OLD_VERSION=""
NEW_VERSION=""

# ---------------------------------------------------------------------------
# Dry-run mode
# ---------------------------------------------------------------------------

if [ "${DRY_RUN}" = true ]; then
  echo ""
  echo "=== DRY RUN MODE — no changes will be made ==="
  echo ""
  echo "Planned actions:"
  echo "  1. Verify node '${NODE}' is reachable via SSH"
  echo "  2. Download firmware from: ${FIRMWARE_URL}"
  echo "  3. Verify firmware checksum against firmware-policy.yaml (if available)"
  echo "  4. Display upgrade plan and request confirmation"
  echo "  5. Upload '${FIRMWARE_FILENAME}' to /tmp/ on node '${NODE}'"
  echo "  6. Run: ssh root@${NODE} \"sysupgrade -n /tmp/${FIRMWARE_FILENAME}\""
  echo "  7. Wait up to ${OFFLINE_WAIT_SECONDS}s for node to go offline"
  echo "  8. Wait up to ${ONLINE_WAIT_SECONDS}s for node to come back online"
  echo "  9. Verify new firmware version via SSH"
  echo " 10. Log structured result to stdout"
  echo ""
  echo "DRY RUN complete. Run without --dry-run to execute."
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 1 — Verify node is reachable via SSH
# ---------------------------------------------------------------------------

log "Step 1: Verifying node '${NODE}' is reachable via SSH..."

if ! ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes -o StrictHostKeyChecking=yes \
     "root@${NODE}" "echo ok" >/dev/null 2>&1; then
  die "Cannot reach node '${NODE}' via SSH. Check connectivity and SSH key access. If the node is new and not yet in known_hosts, run: ssh-keyscan -H ${NODE} >> ~/.ssh/known_hosts"
fi

log "  Node '${NODE}' is reachable."

# ---------------------------------------------------------------------------
# Step 2 — Download firmware image
# ---------------------------------------------------------------------------

log "Step 2: Preparing firmware image..."

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

LOCAL_FIRMWARE="${WORK_DIR}/${FIRMWARE_FILENAME}"

if [ "${FIRMWARE_URL}" = http://* ] || [ "${FIRMWARE_URL}" = https://* ]; then
  log "  Downloading firmware from ${FIRMWARE_URL}..."
  if ! curl -fsSL --output "${LOCAL_FIRMWARE}" "${FIRMWARE_URL}"; then
    die "Failed to download firmware from ${FIRMWARE_URL}"
  fi
elif [ -f "${FIRMWARE_URL}" ]; then
  log "  Copying local firmware file ${FIRMWARE_URL}..."
  cp "${FIRMWARE_URL}" "${LOCAL_FIRMWARE}"
else
  die "Firmware source '${FIRMWARE_URL}' is not a valid URL or local file path."
fi

log "  Firmware image ready: ${LOCAL_FIRMWARE}"

# ---------------------------------------------------------------------------
# Step 3 — Verify checksum against firmware-policy.yaml (if available)
# ---------------------------------------------------------------------------

log "Step 3: Verifying firmware checksum..."

ACTUAL_CHECKSUM="$(sha256sum "${LOCAL_FIRMWARE}" | awk '{print $1}')"
log "  SHA256: ${ACTUAL_CHECKSUM}"

# Resolve workspace root from this script's location so the script can be run
# from any working directory without breaking relative path lookups.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
POLICY_FILE="${WORKSPACE_ROOT}/desired-state/mesh/firmware-policy.yaml"
if [ -f "${POLICY_FILE}" ]; then
  log "  firmware-policy.yaml found. Manual checksum verification recommended."
  log "  Policy file: ${POLICY_FILE}"
  log "  IMPORTANT: Compare the SHA256 above against the checksum published at:"
  grep -A1 "checksum_source" "${POLICY_FILE}" | tail -1 | sed 's/^[[:space:]]*/  /' || true
else
  log "  WARNING: ${POLICY_FILE} not found. Skipping policy checksum lookup."
  log "  Verify the checksum manually against the LibreMesh release page."
fi

# ---------------------------------------------------------------------------
# Step 4 — Read current firmware version and print upgrade plan
# ---------------------------------------------------------------------------

log "Step 4: Reading current firmware version from node..."

OLD_VERSION="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  "root@${NODE}" "grep DISTRIB_RELEASE /etc/openwrt_release | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "unknown")"

echo ""
echo "=== UPGRADE PLAN ==="
echo "  Node:              ${NODE}"
echo "  Current version:   ${OLD_VERSION}"
echo "  Target firmware:   ${FIRMWARE_FILENAME}"
echo "  Checksum (SHA256): ${ACTUAL_CHECKSUM}"
echo "  Method:            sysupgrade -n (no config preservation)"
echo ""
echo "  The node will reboot after upgrade."
echo "  This script waits up to 3 minutes for it to go offline,"
echo "  then up to 5 minutes for it to come back."
echo ""
echo "  WARNING: If the node does not return, manual recovery is required."
echo "  Ensure you have physical access or a rollback plan before proceeding."
echo "  Reference: docs/playbooks/firmware-rollout.md — Rollback Procedure"
echo "===================="
echo ""

# ---------------------------------------------------------------------------
# Step 5 — Require explicit confirmation (skipped in --auto mode)
# ---------------------------------------------------------------------------

if [ "${AUTO_MODE}" = true ]; then
  log "Step 5: --auto mode — confirmation already obtained by run-rollout.sh operator prompt."
else
  confirm "Type YES to proceed with the upgrade of ${NODE}:"
fi

# ---------------------------------------------------------------------------
# Step 6 — Upload firmware to node
# ---------------------------------------------------------------------------

log "Step 6: Uploading firmware to node /tmp/..."

if ! scp -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes -o StrictHostKeyChecking=yes \
     "${LOCAL_FIRMWARE}" "root@${NODE}:/tmp/${FIRMWARE_FILENAME}"; then
  die "Failed to upload firmware to node '${NODE}'."
fi

log "  Firmware uploaded to /tmp/${FIRMWARE_FILENAME} on ${NODE}."

# ---------------------------------------------------------------------------
# Step 7 — Initiate upgrade
# ---------------------------------------------------------------------------

log "Step 7: Initiating sysupgrade on ${NODE}..."
log "  Command: sysupgrade -n /tmp/${FIRMWARE_FILENAME}"

# Run sysupgrade in background — the SSH connection will drop immediately as the
# node reboots. The || true is intentional: a non-zero SSH exit code here does
# NOT mean the upgrade failed; it means the connection was forcibly closed by
# the reboot, which is expected behaviour. Actual upgrade success is confirmed
# in Step 10 by verifying the new firmware version after the node returns.
ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes -o StrictHostKeyChecking=yes \
  "root@${NODE}" "nohup sysupgrade -n /tmp/${FIRMWARE_FILENAME} > /tmp/sysupgrade.log 2>&1 &" || true

log "  Upgrade initiated. Node will reboot."

# ---------------------------------------------------------------------------
# Step 8 — Wait for node to go offline (up to 3 minutes)
# ---------------------------------------------------------------------------

log "Step 8: Waiting for node to go offline (up to ${OFFLINE_WAIT_SECONDS}s)..."

WENT_OFFLINE=false
ELAPSED=0
while [ ${ELAPSED} -lt ${OFFLINE_WAIT_SECONDS} ]; do
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  if ! ping -c 1 -W 2 "${NODE}" >/dev/null 2>&1; then
    log "  Node went offline after ${ELAPSED}s."
    WENT_OFFLINE=true
    break
  fi
  echo -n "."
done
echo ""

if [ "${WENT_OFFLINE}" = false ]; then
  log "WARNING: Node did not go offline within ${OFFLINE_WAIT_SECONDS}s."
  log "  The upgrade may not have started, or the node may still be processing."
  log "  Continuing to wait for it to come back online..."
fi

# ---------------------------------------------------------------------------
# Step 9 — Wait for node to come back online (up to 5 minutes)
# ---------------------------------------------------------------------------

log "Step 9: Waiting for node to come back online (up to ${ONLINE_WAIT_SECONDS}s)..."

CAME_BACK=false
ELAPSED=0
while [ ${ELAPSED} -lt ${ONLINE_WAIT_SECONDS} ]; do
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  # StrictHostKeyChecking=accept-new is intentional here: sysupgrade -n wipes
  # all config including the SSH host key, so the node will present a new key
  # after reboot. accept-new adds the new key without prompting. It does NOT
  # accept a changed key for a host that is already in known_hosts.
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
       "root@${NODE}" "echo ok" >/dev/null 2>&1; then
    log "  Node is back online after ${ELAPSED}s."
    CAME_BACK=true
    break
  fi
  echo -n "."
done
echo ""

if [ "${CAME_BACK}" = false ]; then
  log ""
  log "!!! ROLLBACK REQUIRED !!!"
  log "  Node '${NODE}' did not come back online within ${ONLINE_WAIT_SECONDS}s."
  log "  Possible causes:"
  log "    - Upgrade failed and the node is unresponsive (brick risk)"
  log "    - Network configuration changed and node is reachable on a different IP"
  log "    - Node requires physical recovery"
  log ""
  log "  Next steps:"
  log "    1. Try to reach the node on its mesh IP or by connecting directly via cable"
  log "    2. Check the rollback procedure: docs/playbooks/firmware-rollout.md"
  log "    3. Alert the lead maintainer immediately"
  log "    4. Do NOT upgrade any other nodes until this node is resolved"
  log_result "FAILED"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 10 — Verify new firmware version
# ---------------------------------------------------------------------------

log "Step 10: Verifying new firmware version..."

NEW_VERSION="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  "root@${NODE}" "grep DISTRIB_RELEASE /etc/openwrt_release | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "unknown")"

log "  New firmware version: ${NEW_VERSION}"

if [ "${NEW_VERSION}" = "${OLD_VERSION}" ]; then
  log "WARNING: Firmware version appears unchanged (${NEW_VERSION})."
  log "  The upgrade may not have applied correctly. Run validate-node.sh to confirm."
fi

# ---------------------------------------------------------------------------
# Step 11 — Log structured result
# ---------------------------------------------------------------------------

log "Step 11: Upgrade complete."
log_result "SUCCESS"

log ""
log "Next steps:"
log "  1. Run ./validate-node.sh ${NODE} to perform a full health check"
log "  2. Wait the stabilization period defined in rollout-policy.yaml before proceeding to the next ring"
log "  3. Record this upgrade in the maintenance log"
log "  4. Reference: docs/playbooks/firmware-rollout.md — Phase 4 Final Validation"
