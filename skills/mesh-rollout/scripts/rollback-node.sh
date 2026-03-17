#!/usr/bin/env bash
# rollback-node.sh — Restore a node to a previous configuration state (UCI config rollback)
#
# Usage: ./rollback-node.sh <node-hostname-or-ip> <backup-file.uci.gz>
#
# NOTE: This script performs a CONFIG rollback (UCI settings), NOT a firmware rollback.
# For firmware rollback, follow: docs/playbooks/firmware-rollout.md — Rollback Procedure
#
# The backup file is a gzipped UCI export created with:
#   ssh root@<node> "uci export | gzip" > backup.uci.gz
# or as described in the firmware-rollout playbook (Step 8).
#
# Risk class: Class C/D depending on node role.
# Requires: explicit approval obtained before running this script.
#
# See: docs/playbooks/firmware-rollout.md — Config restore after rollback
#      desired-state/mesh/community-profile/rollout-policy.yaml

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*"
}

log_result() {
  local status="$1"
  echo ""
  echo "--- ROLLBACK RESULT ---"
  echo "date:      $(date '+%Y-%m-%dT%H:%M:%S')"
  echo "node:      ${NODE}"
  echo "backup:    ${BACKUP_FILE}"
  echo "status:    ${status}"
  echo "-----------------------"
}

die() {
  log "ERROR: $*"
  log_result "FAILED"
  exit 1
}

confirm() {
  local prompt="$1"
  echo ""
  echo "${prompt}"
  read -r ANSWER
  if [[ "${ANSWER}" != "YES" ]]; then
    log "Confirmation not given. Aborting."
    exit 0
  fi
}

usage() {
  echo "Usage: $0 <node-hostname-or-ip> <backup-file.uci.gz>"
  echo ""
  echo "  node-hostname-or-ip   Hostname or IP address of the target node"
  echo "  backup-file.uci.gz    Path to the gzipped UCI config backup file"
  echo ""
  echo "The backup file should be a gzipped UCI export, created on the node with:"
  echo "  ssh root@<node> \"uci export | gzip\" > config-backup-<node>-<date>.uci.gz"
  echo ""
  echo "Example:"
  echo "  $0 lm-associacao-salao backups/config-backup-lm-associacao-salao-20260316.uci.gz"
  exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

[[ $# -lt 2 ]] && usage

NODE="$1"
BACKUP_FILE="$2"
SSH_TIMEOUT=10

# ---------------------------------------------------------------------------
# Step 1 — Verify node is reachable
# ---------------------------------------------------------------------------

log "Step 1: Verifying node '${NODE}' is reachable via SSH..."

if ! ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
     -o StrictHostKeyChecking=yes \
     "root@${NODE}" "echo ok" &>/dev/null 2>&1; then
  die "Cannot reach node '${NODE}' via SSH. Check connectivity and SSH key access."
fi

log "  Node '${NODE}' is reachable."

# ---------------------------------------------------------------------------
# Step 2 — Verify backup file exists locally
# ---------------------------------------------------------------------------

log "Step 2: Verifying backup file..."

if [[ ! -f "${BACKUP_FILE}" ]]; then
  die "Backup file not found: ${BACKUP_FILE}"
fi

BACKUP_SIZE="$(du -h "${BACKUP_FILE}" | cut -f1)"
log "  Backup file found: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Test that the file is a valid gzip
if ! gzip -t "${BACKUP_FILE}" 2>/dev/null; then
  die "Backup file is not a valid gzip file: ${BACKUP_FILE}"
fi

log "  Gzip integrity check passed."

# Show a preview of what is in the backup
BACKUP_PACKAGES="$(gunzip -c "${BACKUP_FILE}" 2>/dev/null | grep "^package " | sort -u | head -20 || echo "(could not preview)")"

# ---------------------------------------------------------------------------
# Step 3 — Read current node state and print rollback plan
# ---------------------------------------------------------------------------

log "Step 3: Reading current node state..."

CURRENT_HOSTNAME="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "hostname" 2>/dev/null || echo "unknown")"

CURRENT_VERSION="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "grep DISTRIB_RELEASE /etc/openwrt_release | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "unknown")"

BACKUP_FILENAME="$(basename "${BACKUP_FILE}")"

echo ""
echo "=== ROLLBACK PLAN ==="
echo "  Node:              ${NODE}"
echo "  Current hostname:  ${CURRENT_HOSTNAME}"
echo "  Current firmware:  ${CURRENT_VERSION}"
echo ""
echo "  Backup file:       ${BACKUP_FILENAME}"
echo "  Backup packages:   "
echo "${BACKUP_PACKAGES}" | sed 's/^/    /'
echo ""
echo "  Actions that will be taken:"
echo "    1. Upload backup to /tmp/ on the node"
echo "    2. Run: gunzip -c /tmp/${BACKUP_FILENAME} | uci import"
echo "    3. Run: uci commit"
echo "    4. Run: reload_config"
echo "    5. Verify the config was applied via SSH"
echo ""
echo "  NOTE: This restores UCI configuration only. It does NOT change firmware."
echo "  If the node misbehaves after config rollback, a firmware rollback may also"
echo "  be needed — see: docs/playbooks/firmware-rollout.md"
echo ""
echo "  WARNING: Some config changes (e.g., IP address changes) may cause"
echo "  the node to become unreachable on its current address after reload."
echo "  Ensure you have a fallback access method (cable, physical access)."
echo "===================="
echo ""

# ---------------------------------------------------------------------------
# Step 4 — Require explicit confirmation
# ---------------------------------------------------------------------------

confirm "Type YES to proceed with config rollback on ${NODE}:"

# ---------------------------------------------------------------------------
# Step 5 — Upload backup to node
# ---------------------------------------------------------------------------

log "Step 5: Uploading backup file to /tmp/ on node..."

if ! scp -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes -o StrictHostKeyChecking=yes \
     "${BACKUP_FILE}" "root@${NODE}:/tmp/${BACKUP_FILENAME}"; then
  die "Failed to upload backup file to node '${NODE}'."
fi

log "  Backup uploaded to /tmp/${BACKUP_FILENAME} on ${NODE}."

# ---------------------------------------------------------------------------
# Step 6 — Apply config rollback
# ---------------------------------------------------------------------------

log "Step 6: Applying config rollback..."
log "  Running: gunzip -c /tmp/${BACKUP_FILENAME} | uci import"

APPLY_RESULT="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "gunzip -c /tmp/${BACKUP_FILENAME} | uci import 2>&1" || echo "APPLY_FAILED")"

if echo "${APPLY_RESULT}" | grep -q "APPLY_FAILED"; then
  die "uci import failed. Output: ${APPLY_RESULT}"
fi

if [[ -n "${APPLY_RESULT}" ]]; then
  log "  uci import output: ${APPLY_RESULT}"
fi

log "  Running: uci commit"

COMMIT_RESULT="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "uci commit 2>&1" || echo "COMMIT_FAILED")"

if echo "${COMMIT_RESULT}" | grep -q "COMMIT_FAILED"; then
  die "uci commit failed. The config may be partially applied. Manual review required."
fi

log "  Running: reload_config"

# reload_config triggers service restarts without a full reboot. This is
# sufficient for most UCI changes. For changes that affect the hostname,
# network interfaces, or LibreMesh mesh parameters, a full reboot is
# required — see docs/playbooks/firmware-rollout.md Rollback Procedure.
# Running in the background because some services (e.g. network) can briefly
# drop the SSH connection. The || true is intentional — a dropped SSH
# connection here does not mean the reload failed. Success is verified in
# Step 7 by reconnecting to the node.
ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes -o StrictHostKeyChecking=yes \
  "root@${NODE}" "reload_config > /dev/null 2>&1 &" || true

sleep 5

log "  Config reload initiated. Waiting for services to settle..."
log "  NOTE: If the rollback changed network interfaces, hostname, or mesh"
log "  parameters, run: ssh root@${NODE} reboot — after Step 7 verification."

# ---------------------------------------------------------------------------
# Step 7 — Verify config is applied
# ---------------------------------------------------------------------------

log "Step 7: Verifying config was applied..."

# Give reload_config a moment to settle
sleep 5

# Try to re-connect to the node. This is a config rollback (not firmware),
# so the SSH host key does not change — use StrictHostKeyChecking=yes.
if ssh -o ConnectTimeout=15 -o BatchMode=yes \
     -o StrictHostKeyChecking=yes \
     "root@${NODE}" "echo ok" &>/dev/null 2>&1; then

  # Verify a key config element — hostname and lime-community presence
  NEW_HOSTNAME="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    "root@${NODE}" "hostname" 2>/dev/null || echo "unknown")"

  LIME_EXISTS="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    "root@${NODE}" "[ -f /etc/config/lime-community ] && echo yes || echo no" 2>/dev/null || echo "unknown")"

  log "  Node still reachable after reload."
  log "  Hostname: ${NEW_HOSTNAME}"
  log "  lime-community config present: ${LIME_EXISTS}"

  # Clean up the backup file from /tmp on the node
  ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    "root@${NODE}" "rm -f /tmp/${BACKUP_FILENAME}" 2>/dev/null || true

  log_result "SUCCESS"

  echo ""
  log "Next steps:"
  log "  1. Run ./validate-node.sh ${NODE} to perform a full health check"
  log "  2. Verify the node appears in the mesh and link quality is acceptable"
  log "  3. Update inventories/mesh-nodes.yaml with the current node status"
  log "  4. Write a maintenance log entry documenting this rollback"

else
  log ""
  log "WARNING: Node '${NODE}' is no longer reachable at this address after reload."
  log "  This may be expected if the backup config changes the node's IP address."
  log "  Possible recovery steps:"
  log "    - Try connecting directly via ethernet cable to the node's LAN port"
  log "    - Check if the node is reachable on a different IP (check mesh topology)"
  log "    - If the node is completely unreachable, physical access may be required"
  log "    - Reference: docs/playbooks/firmware-rollout.md — Rollback Procedure"
  log_result "UNCERTAIN"
  exit 1
fi
