#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# tests/lib.sh — Shared test library for the Mesha QA suite.
# Source this file from test scripts; do NOT execute directly.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# NOTE: This library intentionally does NOT set -euo pipefail.
#       Each test script controls its own shell options.

# ---------------------------------------------------------------------------
# Workspace root
# ---------------------------------------------------------------------------
# Idempotency guard — safe to source multiple times from test files and runner.
if [[ -n "${_MESHA_LIB_LOADED:-}" ]]; then
    return 0
fi
_MESHA_LIB_LOADED=1

if [[ -z "${WORKSPACE_ROOT:-}" ]]; then
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export WORKSPACE_ROOT

# ---------------------------------------------------------------------------
# State variables
# ---------------------------------------------------------------------------
QA_PASS=0
QA_FAIL=0
QA_SKIP=0
QA_ERRORS=()

# ---------------------------------------------------------------------------
# Color constants — disabled when stdout is not a tty
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    RESET=''
fi

# ---------------------------------------------------------------------------
# Core result functions
# ---------------------------------------------------------------------------

# qa_pass <description>
qa_pass() {
    local desc="${1:-}"
    QA_PASS=$(( QA_PASS + 1 ))
    printf "${GREEN}PASS${RESET}  %s\n" "$desc"
}

# qa_fail <description>
qa_fail() {
    local desc="${1:-}"
    QA_FAIL=$(( QA_FAIL + 1 ))
    QA_ERRORS+=( "FAIL: ${desc}" )
    printf "${RED}FAIL${RESET}  %s\n" "$desc"
}

# qa_skip <description> [reason]
qa_skip() {
    local desc="${1:-}"
    local reason="${2:-}"
    QA_SKIP=$(( QA_SKIP + 1 ))
    if [[ -n "$reason" ]]; then
        printf "${YELLOW}SKIP${RESET}  %s  (${reason})\n" "$desc"
    else
        printf "${YELLOW}SKIP${RESET}  %s\n" "$desc"
    fi
}

# qa_info <message>
qa_info() {
    printf "${BLUE}INFO${RESET}  %s\n" "${1:-}"
}

# qa_section <title>
qa_section() {
    printf "\n${BOLD}%s${RESET}\n" "${1:-}"
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

# assert_file_exists <path> [description]
assert_file_exists() {
    local path="${1:-}"
    local desc="${2:-file exists: ${path}}"
    if [[ -e "$path" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc"
    fi
}

# assert_file_executable <path> [description]
assert_file_executable() {
    local path="${1:-}"
    local desc="${2:-file is executable: ${path}}"
    if [[ -x "$path" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc"
    fi
}

# assert_file_nonempty <path> [description]
assert_file_nonempty() {
    local path="${1:-}"
    local desc="${2:-file is non-empty: ${path}}"
    if [[ -s "$path" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc"
    fi
}

# assert_exit_zero <description> <cmd...>
# Runs the command; passes if exit code is 0, fails with captured stderr otherwise.
assert_exit_zero() {
    local desc="${1:-}"
    shift
    local stderr_out
    stderr_out="$(  "$@" 2>&1 1>/dev/null )" && local rc=0 || local rc=$?
    if [[ $rc -eq 0 ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc"
        if [[ -n "$stderr_out" ]]; then
            printf "       ${RED}stderr:${RESET} %s\n" "$stderr_out"
        fi
    fi
}

# assert_exit_nonzero <description> <cmd...>
# Passes if the command exits with a non-zero code.
assert_exit_nonzero() {
    local desc="${1:-}"
    shift
    "$@" >/dev/null 2>&1 && local rc=0 || local rc=$?
    if [[ $rc -ne 0 ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc"
    fi
}

# assert_contains <file> <pattern> [description]
# Passes if grep -q finds <pattern> in <file>.
assert_contains() {
    local file="${1:-}"
    local pattern="${2:-}"
    local desc="${3:-file contains '${pattern}': ${file}}"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        qa_pass "$desc"
    else
        qa_fail "$desc"
    fi
}

# assert_not_contains <file> <pattern> [description]
# Passes if grep -q does NOT find <pattern> in <file>.
assert_not_contains() {
    local file="${1:-}"
    local pattern="${2:-}"
    local desc="${3:-file does not contain '${pattern}': ${file}}"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        qa_fail "$desc"
    else
        qa_pass "$desc"
    fi
}

# ---------------------------------------------------------------------------
# Command availability helpers
# ---------------------------------------------------------------------------

# check_command <cmd>
# Returns 0 if cmd exists in PATH, 1 otherwise. Produces no output.
check_command() {
    command -v "${1:-}" >/dev/null 2>&1
}

# require_command <cmd> <skip_reason>
# If cmd is missing, calls qa_skip with skip_reason and returns 1.
# Caller pattern:
#   require_command docker "docker not installed" || return 0
require_command() {
    local cmd="${1:-}"
    local reason="${2:-${cmd} not available}"
    if ! check_command "$cmd"; then
        qa_skip "$cmd required" "$reason"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

# qa_summary
# Prints a final results table and exits 0 (all pass/skip) or 1 (any failures).
qa_summary() {
    local divider="───────────────────────────────"
    printf "\n${BOLD}%s${RESET}\n" "$divider"
    printf "${BOLD}  QA Results${RESET}\n"
    printf "  ${GREEN}PASS: %d${RESET}   ${RED}FAIL: %d${RESET}   ${YELLOW}SKIP: %d${RESET}\n" \
        "$QA_PASS" "$QA_FAIL" "$QA_SKIP"
    printf "${BOLD}%s${RESET}\n" "$divider"

    if [[ ${#QA_ERRORS[@]} -gt 0 ]]; then
        printf "${BOLD}  FAILED TESTS:${RESET}\n"
        local err
        for err in "${QA_ERRORS[@]}"; do
            printf "  ${RED}- %s${RESET}\n" "$err"
        done
        printf "${BOLD}%s${RESET}\n" "$divider"
    fi

    if [[ $QA_FAIL -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}
