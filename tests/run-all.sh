#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# tests/run-all.sh — Mesha QA master runner
#
# Runs all test categories in sequence and prints an aggregate summary.
# Individual test files can also be run standalone.
#
# Usage:
#   ./tests/run-all.sh                        # run all categories
#   ./tests/run-all.sh --category 01          # run category 01 only
#   ./tests/run-all.sh --category 01,02,03    # run specific categories
#   ./tests/run-all.sh --list                 # list available categories
#   ./tests/run-all.sh --help
#
# Exit codes:
#   0  all tests passed (or skipped)
#   1  one or more tests failed

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source shared library (sets WORKSPACE_ROOT, helpers, counters)
# ---------------------------------------------------------------------------
# shellcheck source=tests/lib.sh
source "${TESTS_DIR}/lib.sh"

# ---------------------------------------------------------------------------
# Category registry
# ---------------------------------------------------------------------------
declare -A CATEGORY_NAME=(
  [01]="File Inventory"
  [02]="Syntax Checks"
  [03]="Schema & Cross-References"
  [04]="Dry-Run Smoke Tests"
  [05]="Service Healthchecks"
  [06]="UCI Validation"
  [07]="Inline Python"
  [08]="Python Unit Tests"
)

declare -A CATEGORY_FILE=(
  [01]="${TESTS_DIR}/01-file-inventory.sh"
  [02]="${TESTS_DIR}/02-syntax.sh"
  [03]="${TESTS_DIR}/03-schema.sh"
  [04]="${TESTS_DIR}/04-dryrun.sh"
  [05]="${TESTS_DIR}/05-healthchecks.sh"
  [06]="${TESTS_DIR}/06-uci-validate.sh"
  [07]="${TESTS_DIR}/07-inline-python.sh"
  [08]="${TESTS_DIR}/08-unit-tests.sh"
)

declare -A CATEGORY_FN=(
  [01]="run_file_inventory"
  [02]="run_syntax_checks"
  [03]="run_schema_checks"
  [04]="run_dryrun_checks"
  [05]="run_healthchecks"
  [06]="run_uci_checks"
  [07]="run_inline_python_checks"
  [08]="run_unit_tests"
)

ALL_CATEGORIES=(01 02 03 04 05 06 07 08)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SELECTED_CATEGORIES=()
SHOW_HELP=0
LIST_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --category | -c)
    shift
    IFS=',' read -ra cats <<<"${1:-}"
    SELECTED_CATEGORIES+=("${cats[@]}")
    ;;
  --list | -l)
    LIST_ONLY=1
    ;;
  --help | -h)
    SHOW_HELP=1
    ;;
  *)
    printf "Unknown option: %s\n" "$1" >&2
    exit 1
    ;;
  esac
  shift
done

if [[ $SHOW_HELP -eq 1 ]]; then
  cat <<'EOF'
Usage: tests/run-all.sh [OPTIONS]

Options:
  --category, -c <ids>   Comma-separated category IDs to run (e.g. 01,02,03)
  --list, -l             List available categories and exit
  --help, -h             Show this help

Categories:
  01   File Inventory           — all expected files exist, are non-empty, executable
  02   Syntax Checks            — bash -n, python compile, node ESM, YAML parse
  03   Schema & Cross-References — YAML structure, node/gateway/site cross-refs
  04   Dry-Run Smoke Tests      — doctor.sh, run-rollout --dry-run, normalize.py
  05   Service Healthchecks     — HTTP health probes (skipped if services not running)
  06   UCI Validation            — UCI syntax, hostname cross-refs, secret detection
  07   Inline Python             — Python embedded in shell heredocs
  08   Python Unit Tests       — unittest discover tests/unit/

Examples:
  ./tests/run-all.sh                   # run everything
  ./tests/run-all.sh -c 01,02          # file + syntax only (fast, no docker needed)
  ./tests/run-all.sh -c 03             # schema validation only
  ./tests/run-all.sh -c 05             # live service health probes
EOF
  exit 0
fi

if [[ $LIST_ONLY -eq 1 ]]; then
  printf "\nAvailable QA categories:\n\n"
  for id in "${ALL_CATEGORIES[@]}"; do
    printf "  %s   %s\n" "$id" "${CATEGORY_NAME[$id]}"
  done
  printf "\n"
  exit 0
fi

# Default: run all
if [[ ${#SELECTED_CATEGORIES[@]} -eq 0 ]]; then
  SELECTED_CATEGORIES=("${ALL_CATEGORIES[@]}")
fi

# Validate selected categories
for cat in "${SELECTED_CATEGORIES[@]}"; do
  if [[ -z ${CATEGORY_FILE[$cat]:-} ]]; then
    printf "Unknown category: %s (run --list to see valid categories)\n" "$cat" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
printf "\n${BOLD}═══════════════════════════════════════${RESET}\n"
printf "${BOLD}  Mesha QA Suite${RESET}\n"
printf "${BOLD}  Workspace: %s${RESET}\n" "$WORKSPACE_ROOT"
printf "${BOLD}═══════════════════════════════════════${RESET}\n\n"

# ---------------------------------------------------------------------------
# Source all selected test files (defines their run_* functions)
# lib.sh idempotency guard ensures counters are NOT reset on re-source.
# ---------------------------------------------------------------------------
for cat in "${SELECTED_CATEGORIES[@]}"; do
  file="${CATEGORY_FILE[$cat]}"
  if [[ ! -f $file ]]; then
    qa_fail "test file missing: $file"
    continue
  fi
  # shellcheck disable=SC1090
  source "$file"
done

# ---------------------------------------------------------------------------
# Run each category in order
# ---------------------------------------------------------------------------
for cat in "${SELECTED_CATEGORIES[@]}"; do
  fn="${CATEGORY_FN[$cat]}"
  name="${CATEGORY_NAME[$cat]}"

  printf "\n${BOLD}━━━  Category %s — %s  ━━━${RESET}\n\n" "$cat" "$name"

  if declare -f "$fn" >/dev/null 2>&1; then
    "$fn"
  else
    qa_fail "run function not found: ${fn} (sourcing ${CATEGORY_FILE[$cat]} may have failed)"
  fi
done

# ---------------------------------------------------------------------------
# Aggregate summary
# ---------------------------------------------------------------------------
printf "\n${BOLD}═══════════════════════════════════════${RESET}\n"
printf "${BOLD}  Aggregate QA Results${RESET}\n"
printf "  ${GREEN}PASS: %d${RESET}   ${RED}FAIL: %d${RESET}   ${YELLOW}SKIP: %d${RESET}\n" \
  "$QA_PASS" "$QA_FAIL" "$QA_SKIP"
printf "${BOLD}═══════════════════════════════════════${RESET}\n"

if [[ ${#QA_ERRORS[@]} -gt 0 ]]; then
  printf "\n${BOLD}${RED}  FAILED TESTS:${RESET}\n"
  for err in "${QA_ERRORS[@]}"; do
    printf "  ${RED}✗ %s${RESET}\n" "$err"
  done
  printf "${BOLD}═══════════════════════════════════════${RESET}\n"
fi

if [[ $QA_FAIL -eq 0 ]]; then
  printf "\n${GREEN}${BOLD}  All tests passed.${RESET}\n\n"
  exit 0
else
  printf "\n${RED}${BOLD}  %d test(s) failed.${RESET}\n\n" "$QA_FAIL"
  exit 1
fi
