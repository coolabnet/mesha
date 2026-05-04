#!/usr/bin/env bash
# Run all QEMU integration tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional: wait time for BMX7 convergence (seconds)
CONVERGE_WAIT="${CONVERGE_WAIT:-30}"

echo "=========================================="
echo "Mesha QEMU Integration Test Suite"
echo "=========================================="
echo ""

OVERALL_RESULT=0
FAILED_TESTS=""
TOTAL_PASS=0
TOTAL_FAIL=0

run_test_file() {
    local name="$1"
    local file="$2"
    shift 2
    echo "--- Running: ${name} ---"
    if bash "$file" "$@" 2>&1; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
        echo "  [PASS] ${name}"
    else
        OVERALL_RESULT=1
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        FAILED_TESTS="${FAILED_TESTS} ${name}"
        echo "  [FAIL] ${name}"
    fi
    echo ""
}

# Run each test file
run_test_file "Adapter Contract" "${SCRIPT_DIR}/test-adapters.sh" "${CONVERGE_WAIT}"
run_test_file "Mesh Protocols" "${SCRIPT_DIR}/test-mesh-protocols.sh"
run_test_file "Validate Node" "${SCRIPT_DIR}/test-validate-node.sh"
run_test_file "Config Drift" "${SCRIPT_DIR}/test-config-drift.sh"
run_test_file "Topology Manipulation" "${SCRIPT_DIR}/test-topology-manipulation.sh"
run_test_file "Firmware Upgrade" "${SCRIPT_DIR}/test-firmware-upgrade.sh"
run_test_file "Multi-Hop Mesh" "${SCRIPT_DIR}/test-multi-hop.sh"

echo "=========================================="
echo "Results: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
if [ -n "${FAILED_TESTS}" ]; then
    echo "Failed:${FAILED_TESTS}"
fi
echo "=========================================="

exit $OVERALL_RESULT
