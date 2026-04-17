#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# =============================================================================
# scripts/activate-workspace.sh
# Mesha Community Infrastructure Operator — Workspace Activation
#
# Verifies the workspace is healthy, creates missing runtime directories,
# prints the workspace summary, and displays the OpenClaw activation prompt
# that you paste into your OpenClaw session to start the operator.
#
# Usage:
#   ./scripts/activate-workspace.sh
#
# Risk class: Class B — run on a trusted host (creates local runtime directories
# only, no infrastructure changes — see TOOLS.md §Bootstrap and Maintenance
# Scripts).
#
# Make this script executable: chmod +x scripts/activate-workspace.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve repo root
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

header() {
  echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${CYAN}  $*${RESET}"
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
}
section() { echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }
pass() { echo -e "  ${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${RESET} $*"; }
fail() { echo -e "  ${RED}[FAIL]${RESET} $*"; }
info() { echo -e "  ${CYAN}[INFO]${RESET} $*"; }
created() { echo -e "  ${GREEN}[CREATED]${RESET} $*"; }

# ---------------------------------------------------------------------------
# Step 1: Run doctor.sh first
# ---------------------------------------------------------------------------
header "Mesha Community Infrastructure Operator — Activation"

section "Step 1: Pre-activation health check"

DOCTOR="$SCRIPTS_DIR/doctor.sh"

if [[ ! -f $DOCTOR ]]; then
  fail "scripts/doctor.sh not found at $DOCTOR"
  echo ""
  echo "  Cannot run the health check. Make sure all scripts are present."
  exit 1
fi

echo ""
echo "  Running doctor.sh — checking workspace health..."
echo ""

# Run doctor.sh; capture its exit code without triggering set -e
doctor_exit=0
bash "$DOCTOR" || doctor_exit=$?

if [[ $doctor_exit -eq 1 ]]; then
  echo ""
  fail "doctor.sh reported critical failures."
  echo ""
  echo "  Fix the failures reported above before activating the workspace."
  echo "  Then run this script again."
  echo ""
  exit 1
elif [[ $doctor_exit -eq 2 ]]; then
  echo ""
  warn "doctor.sh completed with warnings. Activation will proceed, but"
  warn "review the warnings above and resolve them when possible."
fi

# ---------------------------------------------------------------------------
# Step 2: Print workspace summary
# ---------------------------------------------------------------------------
section "Step 2: Workspace summary"

echo ""
echo -e "  ${BOLD}Repo root:${RESET}  $REPO_ROOT"
echo ""

# Print the Purpose line from BOOTSTRAP.md (first non-blank line after "## Purpose")
if [[ -f "$REPO_ROOT/BOOTSTRAP.md" ]]; then
  purpose=""
  in_purpose=false
  while IFS= read -r line; do
    if [[ $line =~ ^##[[:space:]]+Purpose ]]; then
      in_purpose=true
      continue
    fi
    if $in_purpose && [[ -n $line ]]; then
      purpose="$line"
      break
    fi
  done <"$REPO_ROOT/BOOTSTRAP.md"
  if [[ -n $purpose ]]; then
    echo -e "  ${BOLD}Purpose:${RESET}"
    echo -e "  ${DIM}$purpose${RESET}"
    echo ""
  fi
fi

# Count files in key directories
count_files() {
  local dir="$REPO_ROOT/$1"
  if [[ -d $dir ]]; then
    find "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

echo -e "  ${BOLD}Workspace contents:${RESET}"
echo "    inventories/    — $(count_files inventories) file(s)"
echo "    desired-state/  — $(count_files desired-state) file(s)"
echo "    skills/         — $(count_files skills) file(s)"
echo "    docs/           — $(count_files docs) file(s)"
echo "    logs/           — $(count_files logs) file(s)"

# ---------------------------------------------------------------------------
# Step 3: Create missing runtime directories
# ---------------------------------------------------------------------------
section "Step 3: Runtime directory setup"
echo ""

RUNTIME_DIRS=(
  "logs/incidents"
  "logs/maintenance"
  "logs/decisions"
  "exports"
)

for rel_dir in "${RUNTIME_DIRS[@]}"; do
  full_dir="$REPO_ROOT/$rel_dir"
  if [[ -d $full_dir ]]; then
    pass "$rel_dir/ already exists"
  else
    mkdir -p "$full_dir"
    created "$rel_dir/ created"
  fi
done

# Add a .gitkeep to each empty runtime dir so it can be committed to the repo
for rel_dir in "${RUNTIME_DIRS[@]}"; do
  full_dir="$REPO_ROOT/$rel_dir"
  if [[ -z "$(find "$full_dir" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
    touch "$full_dir/.gitkeep"
  fi
done

# ---------------------------------------------------------------------------
# Step 4: Display the activation prompt
# ---------------------------------------------------------------------------
section "Step 4: OpenClaw Activation Prompt"

echo ""
echo -e "  ${BOLD}The workspace is ready to be activated in OpenClaw.${RESET}"
echo ""
echo -e "  ${BOLD}What to do next:${RESET}"
echo ""
echo "    1. Open your OpenClaw CLI or chat interface."
echo "    2. Make sure OpenClaw is configured to use this workspace:"
echo ""
echo -e "       ${CYAN}openclaw config set agents.defaults.workspace \"$REPO_ROOT\"${RESET}"
echo ""
echo "    3. Copy and paste the activation prompt below into your OpenClaw"
echo "       session and press Enter."
echo ""
echo -e "  ${YELLOW}${BOLD}───────────── ACTIVATION PROMPT (copy everything below) ─────────────${RESET}"
echo ""

# Print the activation prompt from BOOTSTRAP.md verbatim
# It lives between the last ```text block and the closing ``` in the file.
if [[ -f "$REPO_ROOT/BOOTSTRAP.md" ]]; then
  # shellcheck disable=SC2034
  in_activation_block=false
  # Find the block that follows the "## Activation prompt" heading
  in_activation_section=false
  in_code_block=false

  while IFS= read -r line; do
    if [[ $line =~ ^##[[:space:]]Activation[[:space:]]prompt ]]; then
      in_activation_section=true
      continue
    fi
    if $in_activation_section; then
      if [[ $line == '```text' || $line == '```' ]] && ! $in_code_block; then
        in_code_block=true
        continue
      fi
      if $in_code_block; then
        if [[ $line == '```' ]]; then
          break
        fi
        echo "  $line"
      fi
    fi
  done <"$REPO_ROOT/BOOTSTRAP.md"
else
  # Fallback: print the prompt inline if BOOTSTRAP.md is missing
  echo "  Read BOOTSTRAP.md, AGENTS.md, SOUL.md, TOOLS.md, MEMORY.md, and WORKING.md"
  echo "  from the workspace root and activate this project as a Community Infrastructure"
  echo "  Operator for LibreMesh/OpenWrt networks and local offline-first servers."
  echo ""
  echo "  Follow these rules:"
  echo "  1. Treat BOOTSTRAP.md as the source of truth for architecture and priorities."
  echo "  2. Do not start with full autonomous control; start with read-only visibility."
  echo "  3. Prefer creating or updating concrete repo files over giving abstract advice."
  echo "  4. Use a planner + guarded executors model."
  echo "  5. Keep risky actions behind approval gates."
  echo "  6. Prefer desired-state files over ad hoc fixes."
  echo "  7. Keep all explanations simple and practical."
  echo "  8. Produce the smallest useful next steps first."
fi

echo ""
echo -e "  ${YELLOW}${BOLD}──────────────────────────────────────────────────────────────────────${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Final status
# ---------------------------------------------------------------------------
section "Activation complete"
echo ""
pass "Runtime directories are ready."
pass "Activation prompt printed above."
echo ""
echo -e "  ${BOLD}After pasting the prompt, the operator will:${RESET}"
echo "    • Summarize the mission in one paragraph"
echo "    • List available agents and skills"
echo "    • Identify missing files or inventories"
echo "    • Propose the smallest safe next steps"
echo ""
echo -e "  ${BOLD}Fastest path to first real mesh status:${RESET}"
echo "    1. If connected to LibreMesh: bash scripts/discover-from-thisnode.sh --plan"
echo "    2. Review exports/discovery/latest-candidate-node.yaml and latest-candidate-gateway.yaml"
echo "    3. Test live reads: bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --plan"
echo "    4. Start cache refresh: bash scripts/mesh-heartbeat.sh"
echo ""
echo -e "  ${BOLD}For full deployment instructions, see:${RESET} docs/deployment.md"
echo ""
