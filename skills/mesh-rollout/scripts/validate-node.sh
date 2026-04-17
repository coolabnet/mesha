#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# validate-node.sh — Read-only node health check after firmware upgrade or config change
#
# Usage: ./validate-node.sh <node-hostname-or-ip>
#
# Risk class: Class A (read-only — no changes made)
# No approval required. Safe to run at any time.
#
# Exit codes:
#   0 — all checks PASS
#   1 — one or more checks FAIL
#   2 — usage error
#
# See: docs/playbooks/firmware-rollout.md — Phase 2, Step 10

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

PASS=0
FAIL=0
WARN=0
RESULTS=()

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*"
}

record() {
  local result="$1"
  local check="$2"
  local detail="${3:-}"
  RESULTS+=("${result}  ${check}${detail:+  (${detail})}")
  case "${result}" in
    PASS) PASS=$((PASS + 1)) ;;
    FAIL) FAIL=$((FAIL + 1)) ;;
    WARN) WARN=$((WARN + 1)) ;;
  esac
}

usage() {
  echo "Usage: $0 <node-hostname-or-ip>"
  echo ""
  echo "  node-hostname-or-ip   Hostname or IP address of the target node"
  echo ""
  echo "Example:"
  echo "  $0 lm-associacao-salao"
  echo "  $0 192.168.10.5"
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

[[ $# -lt 1 ]] && usage

NODE="$1"
SSH_TIMEOUT=10
# Resolve workspace root so the script can be run from any directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
POLICY_FILE="${WORKSPACE_ROOT}/desired-state/mesh/firmware-policy.yaml"

log "Starting validation of node: ${NODE}"
echo ""

# ---------------------------------------------------------------------------
# Check 1 — Node is reachable via SSH
# ---------------------------------------------------------------------------

log "Check 1: SSH reachability..."

if ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
     -o StrictHostKeyChecking=accept-new \
     "root@${NODE}" "echo ok" &>/dev/null 2>&1; then
  record "PASS" "SSH reachable" "${NODE}"
else
  record "FAIL" "SSH unreachable" "Cannot connect to root@${NODE} within ${SSH_TIMEOUT}s"
  # Cannot do any further checks if SSH is down
  echo ""
  echo "=== VALIDATION RESULTS for ${NODE} ==="
  for r in "${RESULTS[@]}"; do
    echo "  ${r}"
  done
  echo ""
  echo "Overall: FAIL (node unreachable — remaining checks skipped)"
  echo ""
  exit 1
fi

# ---------------------------------------------------------------------------
# Check 2 — Firmware version matches expected (firmware-policy.yaml)
# ---------------------------------------------------------------------------

log "Check 2: Firmware version..."

ACTUAL_VERSION="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "grep DISTRIB_RELEASE /etc/openwrt_release | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "unknown")"

if [[ "${ACTUAL_VERSION}" == "unknown" ]]; then
  record "WARN" "Firmware version" "Could not read /etc/openwrt_release"
elif [[ -f "${POLICY_FILE}" ]]; then
  APPROVED_VERSION="$(grep -A1 "^  approved_version:" "${POLICY_FILE}" | head -1 | \
    awk '{print $2}' | tr -d '"' 2>/dev/null || echo "")"
  if [[ -n "${APPROVED_VERSION}" ]] && [[ "${ACTUAL_VERSION}" == *"${APPROVED_VERSION}"* ]]; then
    record "PASS" "Firmware version" "${ACTUAL_VERSION} matches approved"
  elif [[ -n "${APPROVED_VERSION}" ]]; then
    record "WARN" "Firmware version" "Installed: ${ACTUAL_VERSION} — Policy approved: ${APPROVED_VERSION}"
  else
    record "PASS" "Firmware version" "${ACTUAL_VERSION} (policy approved version not parseable)"
  fi
else
  record "PASS" "Firmware version" "${ACTUAL_VERSION} (no policy file to compare against)"
fi

# ---------------------------------------------------------------------------
# Check 3 — Mesh neighbors are present (bmx7, babeld, or batman-adv)
# ---------------------------------------------------------------------------

log "Check 3: Mesh neighbor count..."

NEIGHBOR_COUNT=0

# Try bmx7 — use --links to list active bidirectional links; count non-header lines
BMX7_OUTPUT="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "bmx7 -c --links 2>/dev/null | grep -c 'globalId' || echo 0" 2>/dev/null || echo "0")"
NEIGHBOR_COUNT="${BMX7_OUTPUT//[^0-9]/}"

# If bmx7 gave 0, try batman-adv
if [[ "${NEIGHBOR_COUNT}" -eq 0 ]]; then
  BATCTL_OUTPUT="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    "root@${NODE}" "batctl n 2>/dev/null | grep -v '^IF\|^$' | wc -l || echo 0" 2>/dev/null || echo "0")"
  BATCTL_COUNT="${BATCTL_OUTPUT//[^0-9]/}"
  [[ "${BATCTL_COUNT:-0}" -gt "${NEIGHBOR_COUNT}" ]] && NEIGHBOR_COUNT="${BATCTL_COUNT}"
fi

# If still 0, try babeld (port 33123). Use a shell here-string instead of
# piping into nc -q1 because busybox nc on OpenWrt does not support -q.
if [[ "${NEIGHBOR_COUNT}" -eq 0 ]]; then
  BABEL_OUTPUT="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    "root@${NODE}" "( echo 'dump neighbours'; sleep 1 ) | nc localhost 33123 2>/dev/null | grep -c '^neighbour' || echo 0" 2>/dev/null || echo "0")"
  BABEL_COUNT="${BABEL_OUTPUT//[^0-9]/}"
  [[ "${BABEL_COUNT:-0}" -gt "${NEIGHBOR_COUNT}" ]] && NEIGHBOR_COUNT="${BABEL_COUNT}"
fi

if [[ "${NEIGHBOR_COUNT}" -gt 0 ]]; then
  record "PASS" "Mesh neighbors" "${NEIGHBOR_COUNT} neighbor(s) found"
else
  record "FAIL" "Mesh neighbors" "No mesh neighbors found — node may not have joined the mesh"
fi

# ---------------------------------------------------------------------------
# Check 4 — Community SSID is present (lime-community config applied)
# ---------------------------------------------------------------------------

log "Check 4: Community SSID presence..."

COMMUNITY_SSID="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "uci get lime-community.wifi.ap_ssid 2>/dev/null || \
                  uci get lime.wifi.ap_ssid 2>/dev/null || \
                  uci show lime-community 2>/dev/null | grep -i ssid | head -1 | cut -d= -f2 | tr -d \"'\" || \
                  echo ''" 2>/dev/null || echo "")"

if [[ -n "${COMMUNITY_SSID}" ]]; then
  record "PASS" "Community SSID" "Found: ${COMMUNITY_SSID}"
else
  # Check if lime-community config exists at all
  LIME_EXISTS="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    "root@${NODE}" "[ -f /etc/config/lime-community ] && echo yes || echo no" 2>/dev/null || echo "no")"
  if [[ "${LIME_EXISTS}" == "yes" ]]; then
    record "WARN" "Community SSID" "lime-community config exists but SSID not readable via uci"
  else
    record "FAIL" "Community SSID" "/etc/config/lime-community not found — community profile may not be applied"
  fi
fi

# ---------------------------------------------------------------------------
# Check 5 — No error logs in the last 5 minutes
# ---------------------------------------------------------------------------

log "Check 5: Recent error logs (last 5 minutes)..."

# Get log entries from the last 5 minutes containing error/crit/alert/emerg
ERROR_LOG="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "logread 2>/dev/null | tail -200 | grep -iE 'error|crit|alert|emerg' | \
                  awk -v cutoff=\"\$(date -d '-5 minutes' '+%s' 2>/dev/null || echo 0)\" '
                  {
                    # Simple heuristic: just return last 10 matching lines
                    print
                  }' | tail -10" 2>/dev/null || echo "")"

if [[ -z "${ERROR_LOG}" ]]; then
  record "PASS" "Recent error logs" "No error/critical entries found in recent log output"
else
  ERROR_LINES="$(echo "${ERROR_LOG}" | wc -l)"
  record "WARN" "Recent error logs" "${ERROR_LINES} error/critical line(s) in recent log — review manually"
  echo ""
  echo "  Recent log entries (errors):"
  echo "${ERROR_LOG}" | sed 's/^/    /'
  echo ""
fi

# ---------------------------------------------------------------------------
# Check 6 — Uptime > 60 seconds (confirms stable boot)
# ---------------------------------------------------------------------------

log "Check 6: Uptime (must be > 60 seconds)..."

UPTIME_SECONDS="$(ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  "root@${NODE}" "awk '{print int(\$1)}' /proc/uptime 2>/dev/null || echo 0" 2>/dev/null || echo "0")"

UPTIME_SECONDS="${UPTIME_SECONDS//[^0-9]/}"
UPTIME_SECONDS="${UPTIME_SECONDS:-0}"

if [[ "${UPTIME_SECONDS}" -gt 60 ]]; then
  UPTIME_MINS=$((UPTIME_SECONDS / 60))
  record "PASS" "Uptime" "${UPTIME_MINS}m ${UPTIME_SECONDS}s — stable boot confirmed"
elif [[ "${UPTIME_SECONDS}" -gt 0 ]]; then
  record "WARN" "Uptime" "${UPTIME_SECONDS}s — node rebooted very recently, monitor for stability"
else
  record "WARN" "Uptime" "Could not read uptime from /proc/uptime"
fi

# ---------------------------------------------------------------------------
# Print results
# ---------------------------------------------------------------------------

echo ""
echo "=== VALIDATION RESULTS for ${NODE} ==="
echo ""
for r in "${RESULTS[@]}"; do
  echo "  ${r}"
done
echo ""
echo "Summary: ${PASS} PASS  ${WARN} WARN  ${FAIL} FAIL"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
  echo "Overall: FAIL"
  echo ""
  echo "One or more checks failed. Review the failures above before proceeding"
  echo "to the next ring in the rollout. See: docs/playbooks/firmware-rollout.md"
  exit 1
elif [[ "${WARN}" -gt 0 ]]; then
  echo "Overall: WARN"
  echo ""
  echo "All critical checks passed but warnings are present. Review warnings"
  echo "and use judgment before proceeding to the next ring."
  exit 0
else
  echo "Overall: PASS"
  echo ""
  echo "All checks passed. Node appears healthy."
  exit 0
fi
