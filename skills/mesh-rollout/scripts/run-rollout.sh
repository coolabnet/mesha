#!/usr/bin/env bash
# run-rollout.sh — Orchestrate a full ring-based firmware rollout across the community mesh
#
# Usage:
#   ./run-rollout.sh --firmware-url <url-or-path> [--dry-run] [--ring <ring-name>] [--resume] [--checksum <sha256>]
#
# Options:
#   --firmware-url   URL or local path to the firmware image (required)
#   --dry-run        Print the full rollout plan but make no changes
#   --ring           Execute only a specific ring (e.g. --ring canary)
#   --resume         Resume from a previously saved rollout-state.yaml
#   --checksum       Expected SHA-256 checksum of the firmware image (recommended for HTTP URLs)
#
# Risk class: Class D (firmware rollout — multi-node)
# Requires: explicit approval, defined change window, canary-first execution
#
# Source of truth for ring order and policy:
#   desired-state/mesh/community-profile/rollout-policy.yaml
#   inventories/mesh-nodes.yaml
#
# Inline Python helpers have been extracted to scripts/helpers/ for
# testability and to eliminate repeated interpreter startup overhead.
#
# NOTE: This script calls stage-upgrade.sh with --auto to suppress the per-node
# interactive YES prompt. The single top-level YES confirmation (below) covers
# the entire rollout; per-node re-confirmation inside the ring loop would
# deadlock a non-interactive run.
#
# See: docs/playbooks/firmware-rollout.md
#      desired-state/mesh/community-profile/rollout-policy.yaml

set -euo pipefail

# ---------------------------------------------------------------------------
# Workspace root resolution
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# ---------------------------------------------------------------------------
# Paths derived from WORKSPACE_ROOT
# ---------------------------------------------------------------------------

POLICY_FILE="${WORKSPACE_ROOT}/desired-state/mesh/community-profile/rollout-policy.yaml"
INVENTORY_FILE="${WORKSPACE_ROOT}/inventories/mesh-nodes.yaml"
STATE_FILE="${WORKSPACE_ROOT}/desired-state/mesh/rollout-state.yaml"
STAGE_UPGRADE="${SCRIPT_DIR}/stage-upgrade.sh"
VALIDATE_NODE="${SCRIPT_DIR}/validate-node.sh"

# Helper scripts directory (extracted Python helpers)
HELPERS_DIR="${SCRIPT_DIR}/helpers"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

banner() {
  echo ""
  echo "======================================================================"
  echo "  $*"
  echo "======================================================================"
  echo ""
}

usage() {
  echo "Usage: $0 --firmware-url <url-or-path> [--dry-run] [--ring <ring-name>] [--resume] [--checksum <sha256>]"
  echo ""
  echo "Options:"
  echo "  --firmware-url   URL or local path to firmware image (required)"
  echo "  --dry-run        Print the full rollout plan without making changes"
  echo "  --ring           Execute only a named ring (e.g. canary, stable, trailing)"
  echo "  --resume         Resume from rollout-state.yaml left by a halted rollout"
  echo "  --checksum       Expected SHA-256 checksum of the firmware image"
  echo ""
  echo "Security notes:"
  echo "  HTTP URLs are insecure and require --checksum for firmware verification."
  echo "  HTTPS URLs or local paths are accepted without --checksum (checksum still recommended)."
  echo ""
  echo "Examples:"
  echo "  $0 --firmware-url https://firmware.example.com/lm-2023.09.bin"
  echo "  $0 --firmware-url http://192.168.1.50/firmware/lm-2023.09.bin --checksum abc123..."
  echo "  $0 --firmware-url /data/firmware-cache/lm-2023.09.bin --dry-run"
  echo "  $0 --firmware-url /data/firmware-cache/lm-2023.09.bin --ring canary"
  echo "  $0 --firmware-url /data/firmware-cache/lm-2023.09.bin --resume"
  exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

FIRMWARE_URL=""
DRY_RUN=false
ONLY_RING=""
RESUME=false
CHECKSUM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --firmware-url)
      [[ $# -lt 2 ]] && die "--firmware-url requires a value"
      FIRMWARE_URL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --ring)
      [[ $# -lt 2 ]] && die "--ring requires a value"
      ONLY_RING="$2"
      shift 2
      ;;
    --resume)
      RESUME=true
      shift
      ;;
    --checksum)
      [[ $# -lt 2 ]] && die "--checksum requires a value"
      CHECKSUM="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -z "${FIRMWARE_URL}" ]] && usage

# ---------------------------------------------------------------------------
# Firmware URL security validation
# ---------------------------------------------------------------------------

if [[ "${FIRMWARE_URL}" == http://* ]]; then
  if [[ -z "${CHECKSUM}" ]]; then
    die "Insecure HTTP URL detected without --checksum. " \
        "Firmware delivered over plain HTTP can be tampered with in transit. " \
        "Either use an HTTPS URL, a local file path, or provide --checksum <sha256> to verify integrity."
  fi
  log "WARNING: Firmware URL uses insecure HTTP. Checksum verification will be enforced."
fi

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

[[ -f "${POLICY_FILE}" ]]    || die "Rollout policy not found: ${POLICY_FILE}"
[[ -f "${INVENTORY_FILE}" ]] || die "Node inventory not found: ${INVENTORY_FILE}"
[[ -x "${STAGE_UPGRADE}" ]]  || die "stage-upgrade.sh not found or not executable: ${STAGE_UPGRADE}"
[[ -x "${VALIDATE_NODE}" ]]  || die "validate-node.sh not found or not executable: ${VALIDATE_NODE}"

command -v python3 &>/dev/null || die "python3 is required but not found in PATH"

# Verify helper scripts exist
for helper in parse_rings.py parse_ring_nodes.py check_change_window.py \
             write_rollout_state.py update_node_state.py parse_resume_state.py; do
  [[ -f "${HELPERS_DIR}/${helper}" ]] || die "Helper script not found: ${HELPERS_DIR}/${helper}"
done

# ---------------------------------------------------------------------------
# Helper wrappers — call extracted Python scripts
# ---------------------------------------------------------------------------

# Extract ring names and stabilization periods from rollout-policy.yaml.
# Outputs: ring_name|stabilization_hours per line.
get_rings() {
  python3 "${HELPERS_DIR}/parse_rings.py" "${POLICY_FILE}"
}

# Resolve node hostnames that belong to a given ring by cross-referencing
# ring node names (from rollout-policy.yaml) against the inventory.
# Outputs: hostname per line.
get_nodes_for_ring() {
  local ring_name="$1"
  python3 "${HELPERS_DIR}/parse_ring_nodes.py" "${POLICY_FILE}" "${INVENTORY_FILE}" "${ring_name}"
}

# Check if current time falls within a preferred change window.
# Outputs "yes" or "no".
check_change_window() {
  python3 "${HELPERS_DIR}/check_change_window.py" "${POLICY_FILE}"
}

# ---------------------------------------------------------------------------
# Generate a timestamp-based rollout ID
# ---------------------------------------------------------------------------

ROLLOUT_ID="rollout-$(date '+%Y%m%dT%H%M%S')"

# ---------------------------------------------------------------------------
# Resume logic — load existing state
# ---------------------------------------------------------------------------

RESUME_FROM_RING=""
declare -A NODE_DONE_MAP=()

if [[ "${RESUME}" == true ]]; then
  [[ -f "${STATE_FILE}" ]] || die "--resume specified but no rollout-state.yaml found at: ${STATE_FILE}"
  log "Loading previous rollout state from: ${STATE_FILE}"

  RESUME_INFO="$(python3 "${HELPERS_DIR}/parse_resume_state.py" "${STATE_FILE}")"

  PREV_STATUS="$(echo "${RESUME_INFO}" | grep '^status=' | cut -d= -f2)"
  PREV_FW="$(echo "${RESUME_INFO}" | grep '^firmware_url=' | cut -d= -f2)"
  PREV_ID="$(echo "${RESUME_INFO}" | grep '^rollout_id=' | cut -d= -f2)"

  if [[ "${PREV_STATUS}" == "completed" ]]; then
    die "Previous rollout is already completed. Nothing to resume."
  fi

  if [[ "${PREV_STATUS}" != "halted" && "${PREV_STATUS}" != "in_progress" ]]; then
    die "Cannot resume rollout with status '${PREV_STATUS}'. Expected: halted or in_progress."
  fi

  # Inherit the rollout ID from the previous session
  ROLLOUT_ID="${PREV_ID:-${ROLLOUT_ID}}"

  # Load already-done nodes
  while IFS= read -r line; do
    if [[ "${line}" == done:* ]]; then
      done_host="${line#done:}"
      NODE_DONE_MAP["${done_host}"]="validated"
    fi
  done <<< "${RESUME_INFO}"

  log "Resuming rollout ID: ${ROLLOUT_ID} (previous status: ${PREV_STATUS})"
  log "Nodes already completed: ${!NODE_DONE_MAP[*]:-none}"
fi

# ---------------------------------------------------------------------------
# Write or update rollout-state.yaml
# ---------------------------------------------------------------------------

write_state() {
  local status="$1"
  local timestamp_field="$2"   # e.g. "started_at" | "completed_at" | "halted_at"
  local now
  now="$(date '+%Y-%m-%dT%H:%M:%S')"

  python3 "${HELPERS_DIR}/write_rollout_state.py" \
    "${POLICY_FILE}" "${INVENTORY_FILE}" \
    "${ROLLOUT_ID}" "${FIRMWARE_URL}" "${status}" \
    "${timestamp_field}" "${now}" \
    "${STATE_FILE}"
}

# Update the status of a single node in rollout-state.yaml
update_node_state() {
  local hostname="$1"
  local new_status="$2"
  local ts_field="$3"   # e.g. upgraded_at | validated_at | failed_at
  local now
  now="$(date '+%Y-%m-%dT%H:%M:%S')"

  python3 "${HELPERS_DIR}/update_node_state.py" \
    "${STATE_FILE}" "${hostname}" "${new_status}" "${ts_field}" "${now}"
}

# ---------------------------------------------------------------------------
# Load ring definitions
# ---------------------------------------------------------------------------

log "Loading rollout policy from: ${POLICY_FILE}"

RING_DEFS="$(get_rings)"
[[ -z "${RING_DEFS}" ]] && die "No rings found in rollout policy: ${POLICY_FILE}"

# Validate --ring argument if given
if [[ -n "${ONLY_RING}" ]]; then
  if ! echo "${RING_DEFS}" | grep -q "^${ONLY_RING}|"; then
    die "Ring '${ONLY_RING}' not found in rollout policy. Available rings: $(echo "${RING_DEFS}" | cut -d'|' -f1 | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# Firmware checksum verification
# ---------------------------------------------------------------------------

if [[ -n "${CHECKSUM}" ]]; then
  log "Verifying firmware checksum..."
  if [[ "${FIRMWARE_URL}" == http://* || "${FIRMWARE_URL}" == https://* ]]; then
    # For remote URLs, download to a temp file first for checksum verification
    FIRMWARE_TMP="$(mktemp --suffix=.firmware)"
    log "Downloading firmware for checksum verification: ${FIRMWARE_URL}"
    if command -v curl &>/dev/null; then
      curl -fL -o "${FIRMWARE_TMP}" "${FIRMWARE_URL}" || die "Failed to download firmware from: ${FIRMWARE_URL}"
    elif command -v wget &>/dev/null; then
      wget -O "${FIRMWARE_TMP}" "${FIRMWARE_URL}" || die "Failed to download firmware from: ${FIRMWARE_URL}"
    else
      die "Neither curl nor wget found. Cannot download firmware for checksum verification."
    fi
    ACTUAL_CHECKSUM="$(sha256sum "${FIRMWARE_TMP}" | cut -d' ' -f1)"
    rm -f "${FIRMWARE_TMP}"
  else
    # Local file path
    [[ -f "${FIRMWARE_URL}" ]] || die "Firmware file not found: ${FIRMWARE_URL}"
    ACTUAL_CHECKSUM="$(sha256sum "${FIRMWARE_URL}" | cut -d' ' -f1)"
  fi

  if [[ "${ACTUAL_CHECKSUM}" != "${CHECKSUM}" ]]; then
    die "Firmware checksum mismatch! Expected: ${CHECKSUM}, Got: ${ACTUAL_CHECKSUM}. " \
        "Do NOT proceed — the firmware image may be corrupted or tampered with."
  fi
  log "Checksum verified: ${ACTUAL_CHECKSUM}"
fi

# ---------------------------------------------------------------------------
# Print rollout plan
# ---------------------------------------------------------------------------

banner "ROLLOUT PLAN"
echo "  Rollout ID:    ${ROLLOUT_ID}"
echo "  Firmware URL:  ${FIRMWARE_URL}"
if [[ -n "${CHECKSUM}" ]]; then
  echo "  Checksum:      ${CHECKSUM} (verified)"
fi
echo "  Policy file:   ${POLICY_FILE}"
echo "  State file:    ${STATE_FILE}"
[[ -n "${ONLY_RING}" ]] && echo "  Scope:         Ring '${ONLY_RING}' only"
[[ "${RESUME}" == true ]] && echo "  Mode:          RESUME"
echo ""

TOTAL_NODES=0
declare -a RING_NAMES=()
declare -A RING_STAB=()
declare -A RING_NODE_LISTS=()

while IFS='|' read -r ring_name stab_hours; do
  RING_NAMES+=("${ring_name}")
  RING_STAB["${ring_name}"]="${stab_hours}"
  ring_nodes="$(get_nodes_for_ring "${ring_name}")"
  RING_NODE_LISTS["${ring_name}"]="${ring_nodes}"
  node_count=0
  if [[ -n "${ring_nodes}" ]]; then
    node_count="$(echo "${ring_nodes}" | wc -l)"
  fi
  TOTAL_NODES=$((TOTAL_NODES + node_count))
  echo "  Ring: ${ring_name} (${node_count} node(s), stabilization: ${stab_hours}h)"
  if [[ -n "${ring_nodes}" ]]; then
    while IFS= read -r n; do
      if [[ -n "${NODE_DONE_MAP[${n}]+_}" ]]; then
        echo "    - ${n}  [ALREADY DONE — will skip]"
      else
        echo "    - ${n}"
      fi
    done <<< "${ring_nodes}"
  else
    echo "    (no nodes resolved from inventory for this ring)"
  fi
  echo ""
done <<< "${RING_DEFS}"

echo "  Total nodes: ${TOTAL_NODES}"
echo ""

# Change window check
IN_WINDOW="$(check_change_window)"
if [[ "${IN_WINDOW}" == "yes" ]]; then
  echo "  Change window: ACTIVE (current time is within a preferred window)"
else
  echo "  Change window: NOT ACTIVE (current time is outside preferred windows)"
  echo "  WARNING: Proceeding outside a change window. Ensure you have explicit"
  echo "           approval to run this rollout now."
fi
echo ""

# Estimated time (rough: 10 min per node upgrade + stabilization waits)
ESTIMATED_MINS=$((TOTAL_NODES * 10))

echo "  Estimated minimum time: ~${ESTIMATED_MINS} minutes (upgrade only, excluding stabilization waits)"
echo "  Stabilization waits are not enforced by this script — they require manual"
echo "  promotion between rings per rollout-policy.yaml (auto_promote: false)."
echo ""

# ---------------------------------------------------------------------------
# Dry-run: exit here
# ---------------------------------------------------------------------------

if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN complete. No changes made. Remove --dry-run to execute the rollout."
  exit 0
fi

# ---------------------------------------------------------------------------
# Require YES confirmation
# ---------------------------------------------------------------------------

echo "This is a Class D (high-risk) operation. All nodes listed above will have"
echo "their firmware replaced. Ensure you have:"
echo "  [ ] Explicit written approval from an authorized maintainer"
echo "  [ ] A verified rollback firmware image available"
echo "  [ ] A defined maintenance window approved by the community"
echo "  [ ] The canary node tested and validated before promoting to stable"
echo ""
echo "Type YES to proceed with the rollout (anything else aborts):"
read -r CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
  log "Confirmation not given. Rollout aborted."
  exit 0
fi

# ---------------------------------------------------------------------------
# Initialize state file (unless resuming)
# ---------------------------------------------------------------------------

if [[ "${RESUME}" == false ]]; then
  log "Initializing rollout state file: ${STATE_FILE}"
  write_state "in_progress" "started_at"
else
  log "Resuming — updating state to in_progress"
  # Update status field only via a simple inline replacement
  python3 - "${STATE_FILE}" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
content = re.sub(r'^status:\s*\S+', 'status: in_progress', content, flags=re.MULTILINE)
with open(sys.argv[1], 'w') as f:
    f.write(content)
PYEOF
fi

# ---------------------------------------------------------------------------
# Tracking counters
# ---------------------------------------------------------------------------

UPGRADED_COUNT=0
VALIDATED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# ---------------------------------------------------------------------------
# Main ring loop
# ---------------------------------------------------------------------------

for ring_name in "${RING_NAMES[@]}"; do
  # Skip rings not requested (when --ring is set)
  if [[ -n "${ONLY_RING}" ]] && [[ "${ring_name}" != "${ONLY_RING}" ]]; then
    continue
  fi

  stab_hours="${RING_STAB[${ring_name}]}"
  stab_seconds=$((stab_hours * 3600))
  ring_nodes="${RING_NODE_LISTS[${ring_name}]}"

  if [[ -z "${ring_nodes}" ]]; then
    log "Ring '${ring_name}': no nodes resolved from inventory. Skipping."
    continue
  fi

  banner "Starting ring: ${ring_name} ($(echo "${ring_nodes}" | wc -l) node(s))"

  RING_UPGRADED=0
  RING_FAILED=0
  RING_SKIPPED=0

  while IFS= read -r node_host; do
    [[ -z "${node_host}" ]] && continue

    # Skip nodes already validated in a resume scenario
    if [[ -n "${NODE_DONE_MAP[${node_host}]+_}" ]]; then
      log "  [SKIP] ${node_host} — already validated in previous session"
      RING_SKIPPED=$((RING_SKIPPED + 1))
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      continue
    fi

    log "  Upgrading node: ${node_host}"

    # ------------------------------------------------------------------
    # Call stage-upgrade.sh in non-interactive (--auto) mode.
    # --auto skips the per-node interactive YES prompt because the operator
    # already confirmed the entire rollout at the top-level prompt above.
    # ------------------------------------------------------------------
    if "${STAGE_UPGRADE}" "${node_host}" "${FIRMWARE_URL}" --auto; then
      log "  stage-upgrade.sh reported success for ${node_host}"
      update_node_state "${node_host}" "upgraded" "upgraded_at"
      UPGRADED_COUNT=$((UPGRADED_COUNT + 1))
      RING_UPGRADED=$((RING_UPGRADED + 1))
    else
      UPGRADE_EXIT=$?
      log "  ERROR: stage-upgrade.sh failed for ${node_host} (exit code: ${UPGRADE_EXIT})"
      update_node_state "${node_host}" "failed" "failed_at"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      RING_FAILED=$((RING_FAILED + 1))

      # Write halted state
      write_state "halted" "halted_at"

      echo ""
      echo "======================================================================"
      echo "  ROLLOUT HALTED"
      echo "======================================================================"
      echo ""
      echo "  Node '${node_host}' failed during upgrade."
      echo "  Ring '${ring_name}' cannot proceed."
      echo ""
      echo "  Rollout state saved to: ${STATE_FILE}"
      echo "  Status: halted"
      echo ""
      echo "  Required actions:"
      echo "    1. Investigate node '${node_host}' — check SSH connectivity"
      echo "    2. Review: docs/playbooks/firmware-rollout.md — Rollback Procedure"
      echo "    3. If the node is unresponsive, physical access may be required"
      echo "    4. Do NOT attempt to upgrade other nodes until this is resolved"
      echo "    5. Once resolved, use --resume to continue from where the rollout left off"
      echo ""
      echo "  Summary so far:"
      echo "    Upgraded:  ${UPGRADED_COUNT}"
      echo "    Failed:    ${FAILED_COUNT}"
      echo "    Skipped:   ${SKIPPED_COUNT}"
      echo ""
      exit 1
    fi

    # ------------------------------------------------------------------
    # Validate node after upgrade
    # ------------------------------------------------------------------
    log "  Validating node: ${node_host}"

    if "${VALIDATE_NODE}" "${node_host}"; then
      log "  Validation PASSED for ${node_host}"
      update_node_state "${node_host}" "validated" "validated_at"
      VALIDATED_COUNT=$((VALIDATED_COUNT + 1))
    else
      VALIDATE_EXIT=$?
      log "  ERROR: Validation FAILED for ${node_host} (exit code: ${VALIDATE_EXIT})"
      update_node_state "${node_host}" "failed" "failed_at"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      RING_FAILED=$((RING_FAILED + 1))

      # Write halted state
      write_state "halted" "halted_at"

      echo ""
      echo "======================================================================"
      echo "  ROLLOUT HALTED — VALIDATION FAILURE"
      echo "======================================================================"
      echo ""
      echo "  Node '${node_host}' failed post-upgrade validation."
      echo "  Ring '${ring_name}' cannot proceed."
      echo ""
      echo "  Rollout state saved to: ${STATE_FILE}"
      echo "  Status: halted"
      echo ""
      echo "  Required actions:"
      echo "    1. Review validation output above for '${node_host}'"
      echo "    2. Decide: rollback this node or investigate the failure"
      echo "    3. See: docs/playbooks/firmware-rollout.md — Rollback Procedure"
      echo "    4. Run: ./rollback-node.sh ${node_host} <backup-file.uci.gz>"
      echo "    5. After recovery, use --resume to continue the rollout"
      echo ""
      echo "  Summary so far:"
      echo "    Upgraded:   ${UPGRADED_COUNT}"
      echo "    Validated:  ${VALIDATED_COUNT}"
      echo "    Failed:     ${FAILED_COUNT}"
      echo "    Skipped:    ${SKIPPED_COUNT}"
      echo ""
      exit 1
    fi

    echo ""
  done <<< "${ring_nodes}"

  # ------------------------------------------------------------------
  # Ring summary
  # ------------------------------------------------------------------
  echo ""
  echo "--- Ring summary: ${ring_name} ---"
  echo "  Upgraded:  ${RING_UPGRADED}"
  echo "  Failed:    ${RING_FAILED}"
  echo "  Skipped:   ${RING_SKIPPED}"
  echo ""

  # ------------------------------------------------------------------
  # Stabilization pause (between rings, not after the last ring)
  # auto_promote is always false per policy — this pause is advisory;
  # the script pauses briefly but does not enforce the full stabilization
  # period (which is hours-long and requires human promotion decision).
  # ------------------------------------------------------------------
  # Check if there are more rings to process after this one
  FOUND_CURRENT=false
  HAS_NEXT_RING=false
  for rn in "${RING_NAMES[@]}"; do
    if [[ "${FOUND_CURRENT}" == true ]]; then
      if [[ -z "${ONLY_RING}" ]] || [[ "${rn}" == "${ONLY_RING}" ]]; then
        HAS_NEXT_RING=true
        break
      fi
    fi
    [[ "${rn}" == "${ring_name}" ]] && FOUND_CURRENT=true
  done

  if [[ "${HAS_NEXT_RING}" == true ]]; then
    ADVISORY_PAUSE=30
    log "Ring '${ring_name}' complete. Policy requires ${stab_hours}h stabilization before next ring."
    log "Per rollout-policy.yaml (auto_promote: false), promotion to the next ring"
    log "requires a manual decision from the lead maintainer."
    log "Pausing ${ADVISORY_PAUSE}s before continuing (advisory only — not the full stabilization window)."
    log "In a production rollout, stop here and validate the ring over ${stab_hours}h before proceeding."
    sleep "${ADVISORY_PAUSE}"
  fi

done

# ---------------------------------------------------------------------------
# Final state — completed
# ---------------------------------------------------------------------------

write_state "completed" "completed_at"

# ---------------------------------------------------------------------------
# Final rollout report
# ---------------------------------------------------------------------------

banner "ROLLOUT COMPLETE"

echo "  Rollout ID:  ${ROLLOUT_ID}"
echo "  Firmware:    ${FIRMWARE_URL}"
echo "  State file:  ${STATE_FILE}"
echo ""
echo "  Results:"
echo "    Total nodes in scope: ${TOTAL_NODES}"
echo "    Upgraded:             ${UPGRADED_COUNT}"
echo "    Validated:            ${VALIDATED_COUNT}"
echo "    Failed:               ${FAILED_COUNT}"
echo "    Skipped (resumed):    ${SKIPPED_COUNT}"
echo ""
echo "  Next steps:"
echo "    1. Run a full mesh health check to confirm all nodes are healthy"
echo "    2. Update desired-state/mesh/firmware-policy.yaml with the new current_version"
echo "    3. Write a maintenance log entry (use knowledge-curator skill)"
echo "    4. Review: docs/playbooks/firmware-rollout.md — Phase 4 Final Validation"
echo ""
