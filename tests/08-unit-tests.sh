#!/usr/bin/env bash
# tests/08-unit-tests.sh — Python unit tests
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run_unit_tests() {
  cd "$WORKSPACE_ROOT" || exit 1

  qa_section "Python unit tests"

  require_command python3 "python3 required for unit tests" || return 0

  # Check that unittest module is available (always present in stdlib)
  if ! python3 -m unittest --help >/dev/null 2>&1; then
    qa_skip "unit tests" "unittest module not available"
    return 0
  fi

  # Check that the test directory exists
  if [[ ! -d tests/unit ]]; then
    qa_skip "unit tests" "tests/unit/ directory not found"
    return 0
  fi

  local unit_output
  unit_output=$(python3 -m unittest discover -s tests/unit -v 2>&1) && local rc=0 || local rc=$?

  if [[ $rc -eq 0 ]]; then
    # Count tests from output
    local test_count
    test_count=$(echo "$unit_output" | grep -cE '^test_' || true)
    qa_pass "Python unit tests passed (${test_count} tests)"
    # Show verbose output
    echo "$unit_output" | grep -E '^(test_|Ran |OK)' || true
  else
    qa_fail "Python unit tests failed"
    printf '%s\n' "$unit_output"
  fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  run_unit_tests
  qa_summary
fi
