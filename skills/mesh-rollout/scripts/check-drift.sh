#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# check-drift.sh — Compare live mesh state against desired-state
#
# Usage:
#   ./check-drift.sh [--node <hostname>] [--output json|text]
#
# Options:
#   --node      Check only the specified node hostname (default: all nodes in inventory)
#   --output    Output format: text (default) or json
#
# Risk class: Class A — read-only
# No approval required. Safe to run at any time.
# This script never makes changes to any node or configuration file.
#
# What is checked per node:
#   1. SSH reachability (UNREACHABLE if not reached)
#   2. Firmware version — compared against desired-state/mesh/firmware-policy.yaml
#   3. lime-community config presence — community profile must be applied
#
# Exit codes:
#   0 — no drift detected on any checked node
#   1 — drift or unreachability detected on at least one node
#   2 — usage error
#
# Calls validate-node.sh to obtain the live node state per node.
#
# See: desired-state/mesh/firmware-policy.yaml
#      inventories/mesh-nodes.yaml
#      docs/playbooks/firmware-rollout.md

set -euo pipefail

# ---------------------------------------------------------------------------
# Workspace root resolution
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

INVENTORY_FILE="${WORKSPACE_ROOT}/inventories/mesh-nodes.yaml"
FIRMWARE_POLICY="${WORKSPACE_ROOT}/desired-state/mesh/firmware-policy.yaml"
VALIDATE_NODE="${SCRIPT_DIR}/validate-node.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" >&2
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

usage() {
  echo "Usage: $0 [--node <hostname>] [--output json|text]"
  echo ""
  echo "Options:"
  echo "  --node    Check only the specified node (by hostname)"
  echo "  --output  Output format: text (default) or json"
  echo ""
  echo "Examples:"
  echo "  $0"
  echo "  $0 --node porao"
  echo "  $0 --output json"
  echo "  $0 --node yuri --output json"
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

ONLY_NODE=""
OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --node)
    [[ $# -lt 2 ]] && die "--node requires a value"
    ONLY_NODE="$2"
    shift 2
    ;;
  --output)
    [[ $# -lt 2 ]] && die "--output requires a value"
    case "$2" in
    json | text) OUTPUT_FORMAT="$2" ;;
    *) die "Invalid --output value '$2'. Expected: json or text" ;;
    esac
    shift 2
    ;;
  -h | --help)
    usage
    ;;
  *)
    die "Unknown argument: $1"
    ;;
  esac
done

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

[[ -f ${INVENTORY_FILE} ]] || die "Node inventory not found: ${INVENTORY_FILE}"
[[ -f ${FIRMWARE_POLICY} ]] || die "Firmware policy not found: ${FIRMWARE_POLICY}"
[[ -x ${VALIDATE_NODE} ]] || die "validate-node.sh not found or not executable: ${VALIDATE_NODE}"
command -v python3 &>/dev/null || die "python3 is required but not found in PATH"

# ---------------------------------------------------------------------------
# Python: load node inventory and firmware policy
# ---------------------------------------------------------------------------

# Outputs: hostname|display_name|approved_firmware per line
# Uses per-model overrides from firmware-policy.yaml when available.
get_node_list() {
  python3 - "${INVENTORY_FILE}" "${FIRMWARE_POLICY}" "${ONLY_NODE}" <<'PYEOF'
import sys, re

inv_path    = sys.argv[1]
policy_path = sys.argv[2]
only_node   = sys.argv[3]  # empty string = all nodes

# --- Parse firmware policy ---
with open(policy_path) as f:
    pcontent = f.read()

# Global approved version
global_approved = ""
gm = re.search(r'^global:\s*\n(?:[^\n]*\n)*?\s+approved_version:\s*"?([^"\n]+)"?', pcontent, re.MULTILINE)
if not gm:
    # Simpler search
    gm = re.search(r'approved_version:\s*"?([^"\n"]+)"?', pcontent)
global_approved = gm.group(1).strip().strip('"') if gm else "unknown"

# Per-model overrides: model_slug -> approved_version
model_overrides = {}
in_overrides = False
cur_model = None
for line in pcontent.splitlines():
    if re.match(r'^model_overrides:', line):
        in_overrides = True
        continue
    if in_overrides:
        if line and not line.startswith(' ') and not line.startswith('\t') and not line.startswith('-'):
            in_overrides = False
            continue
        mm = re.match(r'\s+-\s+model:\s*"?([^"\n]+)"?', line)
        if mm:
            cur_model = mm.group(1).strip().strip('"')
        if cur_model:
            avm = re.match(r'\s+approved_version:\s*"?([^"\n"]+)"?', line)
            if avm:
                model_overrides[cur_model] = avm.group(1).strip().strip('"')

# --- Parse inventory ---
with open(inv_path) as f:
    icontent = f.read()

in_nodes = False
cur = {}

def flush(c):
    if not c.get('hostname'):
        return
    host = c['hostname']
    if only_node and host != only_node:
        return
    model = c.get('model', '')
    approved = model_overrides.get(model, global_approved)
    name = c.get('name', host)
    print(f"{host}|{name}|{approved}")

for line in icontent.splitlines():
    stripped = line.strip()
    if stripped == 'nodes:':
        in_nodes = True
        continue
    if in_nodes:
        nm = re.match(r'\s*-\s+name:\s*"([^"]+)"', line)
        if not nm:
            nm = re.match(r"\s*-\s+name:\s*'([^']+)'", line)
        if nm:
            flush(cur)
            cur = {'name': nm.group(1).strip().strip('"\'')}
            continue
        hm = re.match(r'\s+hostname:\s*"?([^\s"]+)"?', line)
        if hm:
            cur['hostname'] = hm.group(1).strip().strip('"')
        modm = re.match(r'\s+model:\s*"?([^"\n]+)"?', line)
        if modm:
            cur['model'] = modm.group(1).strip().strip('"')

flush(cur)
PYEOF
}

# ---------------------------------------------------------------------------
# Per-node drift check function
#
# Invokes validate-node.sh (Class A — read-only) to obtain live node state,
# then compares its output against the approved firmware version from policy.
#
# validate-node.sh exit codes:
#   0  — all checks PASS (or only WARNs)
#   1  — at least one FAIL (includes SSH unreachable)
#   2  — usage error
#
# Outputs key:value lines:
#   result:MATCH | DRIFT | UNREACHABLE
#   firmware_live:<version>
#   firmware_approved:<version>
#   lime_community:present | missing | UNREACHABLE
#   drift_reasons:<semicolon-separated list, may be empty>
# ---------------------------------------------------------------------------

check_node_drift() {
  local hostname="$1"
  local approved_firmware="$2"

  log "Checking node: ${hostname} (approved firmware: ${approved_firmware})"

  # Run validate-node.sh; capture stdout (human-readable results) and exit code.
  # validate-node.sh is Class A — it makes no writes to any node.
  local validate_output
  local validate_exit=0
  validate_output="$("${VALIDATE_NODE}" "${hostname}" 2>/dev/null)" || validate_exit=$?

  # Detect unreachable: validate-node.sh prints "SSH unreachable" in its result
  # and exits 1 when the node cannot be reached.
  if echo "${validate_output}" | grep -q "SSH unreachable"; then
    echo "result:UNREACHABLE"
    echo "firmware_live:UNREACHABLE"
    echo "firmware_approved:${approved_firmware}"
    echo "lime_community:UNREACHABLE"
    return
  fi

  # Parse live firmware version from validate-node.sh output.
  # validate-node.sh prints lines like:
  #   PASS  Firmware version  LibreMesh 2023.09 matches approved
  #   WARN  Firmware version  Installed: LibreMesh 2022.12 — Policy approved: LibreMesh 2023.09
  local live_fw="unknown"
  local fw_line
  fw_line="$(echo "${validate_output}" | grep -i "Firmware version" | head -1 || true)"
  if [[ -n ${fw_line} ]]; then
    # Extract "Installed: <version>" if present (WARN case)
    if echo "${fw_line}" | grep -q "Installed:"; then
      live_fw="$(echo "${fw_line}" | sed 's/.*Installed:[[:space:]]*//' | sed 's/[[:space:]]*—.*//')"
    else
      # PASS case: extract version from "(<version> matches approved)"
      live_fw="$(echo "${fw_line}" | sed 's/.*(\([^)]*\) matches.*/\1/' | sed 's/[[:space:]]*(no policy.*//')"
      # If the sed didn't produce a clean version, use the approved as a fallback label
      [[ ${live_fw} == "${fw_line}" ]] && live_fw="unknown"
    fi
  fi
  live_fw="${live_fw%% }" # trim trailing space

  # Parse lime-community presence from validate-node.sh output.
  # validate-node.sh prints lines like:
  #   PASS  Community SSID  Found: ...
  #   WARN  Community SSID  lime-community config exists but SSID not readable
  #   FAIL  Community SSID  /etc/config/lime-community not found
  local lime_status="missing"
  if echo "${validate_output}" | grep -qi "Community SSID.*PASS\|PASS.*Community SSID\|Found:"; then
    lime_status="present"
  elif echo "${validate_output}" | grep -qi "Community SSID.*WARN\|WARN.*Community SSID\|lime-community config exists"; then
    lime_status="present" # file exists, SSID unreadable — treat as present for drift purposes
  fi

  # Determine drift
  local has_drift=false
  local drift_reasons=()

  # Firmware drift: compare live version against approved.
  # We also honour the validate-node.sh FAIL/WARN verdict for firmware.
  # shellcheck disable=SC2034
  local fw_fail=false
  # shellcheck disable=SC2034
  echo "${validate_output}" | grep -i "Firmware version" | grep -qiE "^[[:space:]]*FAIL|WARN" && fw_fail=true || true

  if [[ ${live_fw} == "${approved_firmware}" ]] || echo "${validate_output}" | grep -i "Firmware version" | grep -qi "PASS"; then
    echo "firmware_match:yes"
  else
    echo "firmware_match:no"
    has_drift=true
    drift_reasons+=("firmware: live='${live_fw}' approved='${approved_firmware}'")
  fi

  echo "firmware_live:${live_fw}"
  echo "firmware_approved:${approved_firmware}"

  # lime-community drift
  if [[ ${lime_status} == "present" ]]; then
    echo "lime_community:present"
  else
    echo "lime_community:missing"
    has_drift=true
    drift_reasons+=("lime-community config not found on node")
  fi

  # Any FAIL from validate-node.sh counts as drift even if not captured above
  if [[ ${validate_exit} -ne 0 ]] && echo "${validate_output}" | grep -q "^  FAIL"; then
    has_drift=true
    local extra_fails
    extra_fails="$(echo "${validate_output}" | grep "^  FAIL" | sed 's/^  FAIL[[:space:]]*//' | tr '\n' ';' | sed 's/;$//')"
    drift_reasons+=("validate-node FAIL: ${extra_fails}")
  fi

  if [[ ${has_drift} == true ]]; then
    echo "result:DRIFT"
    echo "drift_reasons:$(
      IFS=';'
      echo "${drift_reasons[*]}"
    )"
  else
    echo "result:MATCH"
    echo "drift_reasons:"
  fi
}

# ---------------------------------------------------------------------------
# Main — iterate over nodes and collect results
# ---------------------------------------------------------------------------

NODE_LIST="$(get_node_list)"

if [[ -z ${NODE_LIST} ]]; then
  if [[ -n ${ONLY_NODE} ]]; then
    die "Node '${ONLY_NODE}' not found in inventory: ${INVENTORY_FILE}"
  else
    die "No nodes found in inventory: ${INVENTORY_FILE}"
  fi
fi

# Accumulate results
declare -a RESULTS_HOSTNAME=()
declare -a RESULTS_DISPLAY=()
declare -a RESULTS_STATUS=()
declare -a RESULTS_FIRMWARE_LIVE=()
declare -a RESULTS_FIRMWARE_APPROVED=()
declare -a RESULTS_LIME=()
declare -a RESULTS_REASONS=()

MATCH_COUNT=0
DRIFT_COUNT=0
UNREACHABLE_COUNT=0

while IFS='|' read -r hostname display_name approved_firmware; do
  [[ -z ${hostname} ]] && continue

  # Run per-node check
  node_output="$(check_node_drift "${hostname}" "${approved_firmware}")"

  result=""
  fw_live=""
  fw_approved=""
  lime_status=""
  reasons=""

  while IFS=: read -r key val; do
    case "${key}" in
    result) result="${val}" ;;
    firmware_live) fw_live="${val}" ;;
    firmware_approved) fw_approved="${val}" ;;
    lime_community) lime_status="${val}" ;;
    drift_reasons) reasons="${val}" ;;
    esac
  done <<<"${node_output}"

  RESULTS_HOSTNAME+=("${hostname}")
  RESULTS_DISPLAY+=("${display_name}")
  RESULTS_STATUS+=("${result}")
  RESULTS_FIRMWARE_LIVE+=("${fw_live}")
  RESULTS_FIRMWARE_APPROVED+=("${fw_approved}")
  RESULTS_LIME+=("${lime_status}")
  RESULTS_REASONS+=("${reasons}")

  case "${result}" in
  MATCH) MATCH_COUNT=$((MATCH_COUNT + 1)) ;;
  DRIFT) DRIFT_COUNT=$((DRIFT_COUNT + 1)) ;;
  UNREACHABLE) UNREACHABLE_COUNT=$((UNREACHABLE_COUNT + 1)) ;;
  esac

done <<<"${NODE_LIST}"

TOTAL_COUNT=${#RESULTS_HOSTNAME[@]}

# ---------------------------------------------------------------------------
# Output — text format
# ---------------------------------------------------------------------------

output_text() {
  local check_time
  check_time="$(date '+%Y-%m-%dT%H:%M:%S')"

  echo ""
  echo "======================================================================"
  echo "  MESH DRIFT REPORT"
  echo "  Checked at: ${check_time}"
  echo "  Policy:     ${FIRMWARE_POLICY}"
  echo "======================================================================"
  echo ""
  printf "  %-30s  %-12s  %-35s  %-12s\n" "Node" "Status" "Live Firmware" "lime-community"
  printf "  %-30s  %-12s  %-35s  %-12s\n" "------------------------------" "------------" "-----------------------------------" "------------"

  local i
  for ((i = 0; i < TOTAL_COUNT; i++)); do
    printf "  %-30s  %-12s  %-35s  %-12s\n" \
      "${RESULTS_HOSTNAME[i]}" \
      "${RESULTS_STATUS[i]}" \
      "${RESULTS_FIRMWARE_LIVE[i]}" \
      "${RESULTS_LIME[i]}"
  done

  echo ""
  echo "  Summary: ${TOTAL_COUNT} checked — ${MATCH_COUNT} MATCH  ${DRIFT_COUNT} DRIFT  ${UNREACHABLE_COUNT} UNREACHABLE"
  echo ""

  # Print drift details
  if [[ ${DRIFT_COUNT} -gt 0 ]]; then
    echo "  --- Drift details ---"
    for ((i = 0; i < TOTAL_COUNT; i++)); do
      if [[ ${RESULTS_STATUS[i]} == "DRIFT" ]]; then
        echo ""
        echo "  Node: ${RESULTS_HOSTNAME[i]} (${RESULTS_DISPLAY[i]})"
        echo "    Firmware live:     ${RESULTS_FIRMWARE_LIVE[i]}"
        echo "    Firmware approved: ${RESULTS_FIRMWARE_APPROVED[i]}"
        echo "    lime-community:    ${RESULTS_LIME[i]}"
        if [[ -n ${RESULTS_REASONS[i]} ]]; then
          echo "    Reasons:"
          # Split reasons by semicolon
          IFS=';' read -ra reason_list <<<"${RESULTS_REASONS[i]}"
          for r in "${reason_list[@]}"; do
            echo "      - ${r}"
          done
        fi
      fi
    done
    echo ""
  fi

  if [[ ${UNREACHABLE_COUNT} -gt 0 ]]; then
    echo "  --- Unreachable nodes ---"
    for ((i = 0; i < TOTAL_COUNT; i++)); do
      if [[ ${RESULTS_STATUS[i]} == "UNREACHABLE" ]]; then
        echo "  Node: ${RESULTS_HOSTNAME[i]} (${RESULTS_DISPLAY[i]}) — SSH unreachable"
      fi
    done
    echo ""
  fi

  if [[ ${DRIFT_COUNT} -gt 0 ]] || [[ ${UNREACHABLE_COUNT} -gt 0 ]]; then
    echo "  Recommended actions:"
    [[ ${DRIFT_COUNT} -gt 0 ]] \
      && echo "    - Review firmware drift: schedule an upgrade via run-rollout.sh"
    [[ ${DRIFT_COUNT} -gt 0 ]] \
      && echo "    - Missing lime-community: re-apply community profile per mesh-rollout skill"
    [[ ${UNREACHABLE_COUNT} -gt 0 ]] \
      && echo "    - Unreachable nodes: check power, SSH keys, and network connectivity"
    echo "    - See: docs/playbooks/firmware-rollout.md"
    echo ""
  fi

  echo "======================================================================"
}

# ---------------------------------------------------------------------------
# Output — JSON format
# ---------------------------------------------------------------------------

output_json() {
  python3 - <<PYEOF
import json, sys
from datetime import datetime

results = []
$(
    for ((i = 0; i < TOTAL_COUNT; i++)); do
      echo "results.append({"
      echo "  'hostname': '${RESULTS_HOSTNAME[i]}', 'display_name': '${RESULTS_DISPLAY[i]}',"
      echo "  'status': '${RESULTS_STATUS[i]}', 'firmware_live': '${RESULTS_FIRMWARE_LIVE[i]}',"
      echo "  'firmware_approved': '${RESULTS_FIRMWARE_APPROVED[i]}',"
      echo "  'lime_community': '${RESULTS_LIME[i]}',"
      echo "  'drift_reasons': [r for r in '${RESULTS_REASONS[i]}'.split(';') if r],"
      echo "})"
    done
  )

report = {
    "checked_at": datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
    "total": ${TOTAL_COUNT},
    "match": ${MATCH_COUNT},
    "drift": ${DRIFT_COUNT},
    "unreachable": ${UNREACHABLE_COUNT},
    "has_drift": ${DRIFT_COUNT} > 0 or ${UNREACHABLE_COUNT} > 0,
    "nodes": results,
}

print(json.dumps(report, indent=2))
PYEOF
}

# ---------------------------------------------------------------------------
# Emit output
# ---------------------------------------------------------------------------

case "${OUTPUT_FORMAT}" in
text) output_text ;;
json) output_json ;;
esac

# ---------------------------------------------------------------------------
# Exit code: 0 = no drift/unreachable, 1 = drift or unreachable detected
# ---------------------------------------------------------------------------

if [[ ${DRIFT_COUNT} -gt 0 ]] || [[ ${UNREACHABLE_COUNT} -gt 0 ]]; then
  exit 1
else
  exit 0
fi
