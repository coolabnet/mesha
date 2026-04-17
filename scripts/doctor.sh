#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# =============================================================================
# scripts/doctor.sh
# Mesha Community Infrastructure Operator — Health Diagnostics
#
# Read-only health check. Never installs or modifies anything.
# Checks tools, workspace structure, key files, inventories, and git state.
#
# Usage:
#   ./scripts/doctor.sh              # run all checks
#   ./scripts/doctor.sh --help       # show this usage
#
# Options:
#   --help, -h   Show this help message and exit
#
# Exit codes:
#   0 — all checks PASS
#   1 — one or more checks FAIL (critical issues)
#   2 — no FAILs, but one or more checks produced a WARNING
#
# Risk class: Class A — read-only, no approval required (see TOOLS.md).
# Make this script executable: chmod +x scripts/doctor.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Perform read-only health checks on the Mesha workspace."
      echo ""
      echo "Options:"
      echo "  --help, -h    Show this help message and exit"
      echo ""
      echo "Exit codes:"
      echo "  0 — all checks PASS"
      echo "  1 — one or more checks FAIL (critical issues)"
      echo "  2 — no FAILs, but one or more checks produced a WARNING"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Run $0 --help for usage information" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve repo root
# ---------------------------------------------------------------------------
REPO_ROOT="$( cd "$(dirname "$0")/.." && pwd )"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

header() { echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }
pass()   { echo -e "  ${GREEN}[PASS]${RESET} $*"; }
warn()   { echo -e "  ${YELLOW}[WARN]${RESET} $*"; }
fail()   { echo -e "  ${RED}[FAIL]${RESET} $*"; }
info()   { echo -e "  ${CYAN}[INFO]${RESET} $*"; }

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
FAIL_COUNT=0
WARN_COUNT=0

record_fail() { FAIL_COUNT=$(( FAIL_COUNT + 1 )); }
record_warn() { WARN_COUNT=$(( WARN_COUNT + 1 )); }

# ---------------------------------------------------------------------------
# Tool checks (read-only — just test existence and version)
# ---------------------------------------------------------------------------

check_tool_required() {
  local name="$1"
  local cmd="$2"
  local version_flag="${3:---version}"
  local ver_output

  if command -v "$cmd" &>/dev/null; then
    ver_output="$("$cmd" "$version_flag" 2>&1 | head -1 || true)"
    pass "$name: $ver_output"
  else
    fail "$name not found"
    record_fail
  fi
}

check_tool_optional() {
  local name="$1"
  local cmd="$2"
  local version_flag="${3:---version}"
  local ver_output

  if command -v "$cmd" &>/dev/null; then
    ver_output="$("$cmd" "$version_flag" 2>&1 | head -1 || true)"
    pass "$name: $ver_output"
  else
    warn "$name not found (recommended)"
    record_warn
  fi
}

# ---------------------------------------------------------------------------
# Section 1: Required tools
# ---------------------------------------------------------------------------
header "Required Tools"

# git
check_tool_required "git" "git" "--version"

# Node.js — additionally check major version
if command -v node &>/dev/null; then
  raw_ver="$(node --version 2>&1)"
  major="$(echo "$raw_ver" | sed 's/v//' | cut -d. -f1)"
  if [[ "$major" -ge 22 ]]; then
    pass "node: $raw_ver (v22+ required — OK)"
  else
    fail "node: $raw_ver — v22 or newer is required"
    record_fail
  fi
else
  fail "node not found (v22+ required)"
  record_fail
fi

# ssh — ssh -V writes to stderr
if command -v ssh &>/dev/null; then
  ssh_ver="$(ssh -V 2>&1 | head -1 || true)"
  pass "ssh: $ssh_ver"
else
  fail "ssh not found"
  record_fail
fi

# curl
check_tool_required "curl" "curl" "--version"

# ---------------------------------------------------------------------------
# Section 2: Recommended tools
# ---------------------------------------------------------------------------
header "Recommended Tools"

check_tool_optional "jq"      "jq"      "--version"
check_tool_optional "python3" "python3" "--version"

# docker — also check daemon
if command -v docker &>/dev/null; then
  docker_ver="$(docker --version 2>&1 | head -1 || true)"
  pass "docker: $docker_ver"
  if ! docker info &>/dev/null; then
    warn "docker daemon not reachable (is Docker running? is \$USER in docker group?)"
    record_warn
  fi
else
  warn "docker not found (recommended for local services)"
  record_warn
fi

# ---------------------------------------------------------------------------
# Section 3: Workspace root
# ---------------------------------------------------------------------------
header "Workspace Root"

if [[ -f "$REPO_ROOT/BOOTSTRAP.md" ]]; then
  pass "BOOTSTRAP.md found at $REPO_ROOT"
else
  fail "BOOTSTRAP.md not found — is this the correct workspace directory?"
  record_fail
fi

# ---------------------------------------------------------------------------
# Section 4: Phase 1 required files
# ---------------------------------------------------------------------------
header "Phase 1 Required Files"

# These are the files listed in BOOTSTRAP.md §"What the initial repo should contain"
REQUIRED_FILES=(
  "AGENTS.md"
  "SOUL.md"
  "TOOLS.md"
  "MEMORY.md"
  "WORKING.md"
  "inventories/mesh-nodes.yaml"
  "inventories/sites.yaml"
  "inventories/local-services.yaml"
  "desired-state/mesh/community-profile/rollout-policy.yaml"
  "desired-state/server/service-catalog.yaml"
  "docs/architecture.md"
  "docs/deployment.md"
  "docs/troubleshooting.md"
  "docs/playbooks/node-onboarding.md"
  "docs/playbooks/firmware-rollout.md"
  "docs/playbooks/local-service-install.md"
  "skills/community-ops-frontdesk/SKILL.md"
  "skills/mesh-readonly/SKILL.md"
  "skills/server-readonly/SKILL.md"
  "skills/incident-triage/SKILL.md"
  "skills/knowledge-curator/SKILL.md"
  "skills/voice-friendly-response/SKILL.md"
)

for rel_path in "${REQUIRED_FILES[@]}"; do
  full_path="$REPO_ROOT/$rel_path"
  if [[ -f "$full_path" ]]; then
    pass "$rel_path"
  else
    warn "Missing: $rel_path"
    record_warn
  fi
done

# ---------------------------------------------------------------------------
# Section 5: inventories/ and desired-state/ directories populated?
# ---------------------------------------------------------------------------
header "Inventory & Desired-State Population"

INV_DIR="$REPO_ROOT/inventories"
DS_DIR="$REPO_ROOT/desired-state"

if [[ -d "$INV_DIR" ]]; then
  inv_count="$(find "$INV_DIR" -maxdepth 2 \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$inv_count" -gt 0 ]]; then
    pass "inventories/ present with $inv_count YAML file(s)"
  else
    warn "inventories/ exists but contains no YAML files — fill in mesh-nodes.yaml, sites.yaml, etc."
    record_warn
  fi
else
  fail "inventories/ directory not found"
  record_fail
fi

if [[ -d "$DS_DIR" ]]; then
  ds_count="$(find "$DS_DIR" -maxdepth 4 -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$ds_count" -gt 0 ]]; then
    pass "desired-state/ present with $ds_count file(s)"
  else
    warn "desired-state/ exists but is empty — populate mesh and server desired-state files"
    record_warn
  fi
else
  fail "desired-state/ directory not found"
  record_fail
fi

# ---------------------------------------------------------------------------
# Section 6: Git repository state
# ---------------------------------------------------------------------------
header "Git Repository"

if git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
  pass "git repository initialized at $REPO_ROOT"
  # Check for at least one commit
  if git -C "$REPO_ROOT" rev-parse HEAD &>/dev/null; then
    commit="$(git -C "$REPO_ROOT" log --oneline -1 2>/dev/null || echo '(no log)')"
    pass "last commit: $commit"
  else
    warn "no commits yet in this repository"
    record_warn
  fi
else
  fail "no git repository found at $REPO_ROOT"
  record_fail
fi

# ---------------------------------------------------------------------------
# Section 7: logs/ directory
# ---------------------------------------------------------------------------
header "Logs Directory"

LOGS_DIR="$REPO_ROOT/logs"
if [[ -d "$LOGS_DIR" ]]; then
  pass "logs/ directory present"
  # Check sub-directories
  for subdir in incidents maintenance decisions; do
    if [[ -d "$LOGS_DIR/$subdir" ]]; then
      pass "logs/$subdir/ present"
    else
      warn "logs/$subdir/ not found — run activate-workspace.sh to create it"
      record_warn
    fi
  done
else
  warn "logs/ directory not found — run activate-workspace.sh to create it"
  record_warn
fi

# ---------------------------------------------------------------------------
# Section 8: exports/ directory
# ---------------------------------------------------------------------------
header "Exports Directory"

EXPORTS_DIR="$REPO_ROOT/exports"
if [[ -d "$EXPORTS_DIR" ]]; then
  pass "exports/ directory present"
else
  warn "exports/ directory not found — run activate-workspace.sh to create it"
  record_warn
fi

# ---------------------------------------------------------------------------
# Section 9: secrets/ sanity check (read-only — just check README exists)
# ---------------------------------------------------------------------------
header "Secrets Directory"

SECRETS_DIR="$REPO_ROOT/secrets"
if [[ -d "$SECRETS_DIR" ]]; then
  if [[ -f "$SECRETS_DIR/README.md" ]]; then
    pass "secrets/README.md present"
  else
    warn "secrets/ exists but README.md is missing"
    record_warn
  fi
  # Warn if anything other than README.md is present (crude secret detection)
  secret_files="$(find "$SECRETS_DIR" -maxdepth 1 -type f ! -name "README.md" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$secret_files" -gt 0 ]]; then
    warn "secrets/ contains $secret_files file(s) other than README.md — make sure no real secrets are committed"
    record_warn
  fi
else
  warn "secrets/ directory not found"
  record_warn
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Health Report"

echo ""
if [[ "$FAIL_COUNT" -eq 0 && "$WARN_COUNT" -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All checks passed. Workspace looks healthy.${RESET}"
elif [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}No failures, but $WARN_COUNT warning(s) detected.${RESET}"
  echo -e "  ${YELLOW}Review the warnings above before proceeding.${RESET}"
else
  echo -e "  ${RED}${BOLD}$FAIL_COUNT failure(s) and $WARN_COUNT warning(s) detected.${RESET}"
  echo -e "  ${RED}Fix the failures before activating the workspace.${RESET}"
fi
echo ""

# ---------------------------------------------------------------------------
# Exit code logic
# ---------------------------------------------------------------------------
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
elif [[ "$WARN_COUNT" -gt 0 ]]; then
  exit 2
fi
exit 0
