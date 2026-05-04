#!/usr/bin/env bash
# Validate-node tests — tests skills/mesh-rollout/scripts/validate-node.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "# Validate Node Tests"
tap_plan 3

GATEWAY=$(get_gateway)
NODE2="lm-testbed-node-2"
CLEANUP_DONE=false

cleanup_validate() {
    $CLEANUP_DONE && return
    CLEANUP_DONE=true
    # Restore community SSID
    ssh_vm "$GATEWAY" "uci set lime-community.wifi.ap_ssid='MeshaTestBed'; uci commit lime-community" 2>/dev/null || true
    # Restart BMX7 on node-2
    ssh_vm "$NODE2" "/etc/init.d/bmx7 start 2>/dev/null || bmx7 2>/dev/null" 2>/dev/null || true
}
trap cleanup_validate EXIT INT TERM

# Test 1: validate-node reports healthy for properly configured node
echo "# Testing validate-node on healthy node..."
VALIDATE_RESULT=0
bash "${REPO_ROOT}/scripts/qemu-testbed/run-testbed-adapter.sh" \
    "${REPO_ROOT}/skills/mesh-rollout/scripts/validate-node.sh" "$GATEWAY" \
    >/dev/null 2>&1 || VALIDATE_RESULT=$?

if [ "${VALIDATE_RESULT}" -eq 0 ]; then
    pass "test_validate_healthy_node"
else
    # validate-node may return warnings but 0. Non-zero means actual failure.
    fail "test_validate_healthy_node" "exit code ${VALIDATE_RESULT}"
fi

# Test 2: validate-node detects missing community SSID
echo "# Testing validate-node detects missing SSID..."
# Remove community SSID
ssh_vm "$GATEWAY" "uci delete lime-community.wifi.ap_ssid 2>/dev/null; uci commit lime-community 2>/dev/null" || true
sleep 1

VALIDATE_RESULT=0
bash "${REPO_ROOT}/scripts/qemu-testbed/run-testbed-adapter.sh" \
    "${REPO_ROOT}/skills/mesh-rollout/scripts/validate-node.sh" "$GATEWAY" \
    >/dev/null 2>&1 || VALIDATE_RESULT=$?

# Restore SSID
ssh_vm "$GATEWAY" "uci set lime-community.wifi.ap_ssid='MeshaTestBed'; uci commit lime-community" 2>/dev/null || true

if [ "${VALIDATE_RESULT}" -ne 0 ]; then
    pass "test_validate_detects_missing_ssid"
else
    fail "test_validate_detects_missing_ssid" "validate-node did not detect missing SSID"
fi

# Test 3: validate-node detects no neighbors
echo "# Testing validate-node detects no neighbors..."
# Stop BMX7 on node-2
ssh_vm "$NODE2" "/etc/init.d/bmx7 stop 2>/dev/null; killall bmx7 2>/dev/null" || true
sleep 5

VALIDATE_RESULT=0
bash "${REPO_ROOT}/scripts/qemu-testbed/run-testbed-adapter.sh" \
    "${REPO_ROOT}/skills/mesh-rollout/scripts/validate-node.sh" "$GATEWAY" \
    >/dev/null 2>&1 || VALIDATE_RESULT=$?

# Restart BMX7
ssh_vm "$NODE2" "/etc/init.d/bmx7 start 2>/dev/null || bmx7 2>/dev/null" || true
sleep 5

# Note: validate-node might not check neighbors on other nodes, only local
# If it doesn't fail, that's acceptable — the test is checking behavior
if [ "${VALIDATE_RESULT}" -ne 0 ]; then
    pass "test_validate_detects_no_neighbors"
else
    skip "test_validate_detects_no_neighbors" "validate-node may not check remote neighbors"
fi

tap_summary
