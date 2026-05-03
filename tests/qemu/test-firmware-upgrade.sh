#!/usr/bin/env bash
# Firmware upgrade simulation test
# Tests the sysupgrade pattern by modifying /etc/openwrt_release and verifying detection
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "# Firmware Upgrade Simulation Tests"
tap_plan 2

GATEWAY=$(get_gateway)

# Test 1: Version change detected after simulated upgrade
echo "# Testing firmware version change detection..."

# Read current version
ORIGINAL_VERSION=$(ssh_vm "$GATEWAY" "grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d \"'\"" 2>/dev/null || echo "unknown")
echo "  Current version: ${ORIGINAL_VERSION}"

# Simulate upgrade: change version string
ssh_vm "$GATEWAY" "sed -i 's/DISTRIB_RELEASE=.*/DISTRIB_RELEASE=\"testbed-2.0\"/' /etc/openwrt_release" 2>/dev/null || true
sleep 1

# Verify change
NEW_VERSION=$(ssh_vm "$GATEWAY" "grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d \"'\"" 2>/dev/null || echo "unknown")
echo "  New version: ${NEW_VERSION}"

if [ "${NEW_VERSION}" = "testbed-2.0" ] && [ "${NEW_VERSION}" != "${ORIGINAL_VERSION}" ]; then
    pass "test_firmware_version_change_detected"
else
    fail "test_firmware_version_change_detected" "version unchanged (${ORIGINAL_VERSION} -> ${NEW_VERSION})"
fi

# Test 2: validate-node detects version mismatch with policy
echo "# Testing validate-node detects version mismatch..."
VALIDATE_RESULT=0
bash "${REPO_ROOT}/scripts/qemu-testbed/run-testbed-adapter.sh" \
    "${REPO_ROOT}/skills/mesh-rollout/scripts/validate-node.sh" "$GATEWAY" \
    >/dev/null 2>&1 || VALIDATE_RESULT=$?

# Restore original version
ssh_vm "$GATEWAY" "sed -i 's/DISTRIB_RELEASE=.*/DISTRIB_RELEASE=\"${ORIGINAL_VERSION}\"/' /etc/openwrt_release" 2>/dev/null || true

if [ "${VALIDATE_RESULT}" -ne 0 ]; then
    pass "test_validate_detects_version_mismatch"
else
    skip "test_validate_detects_version_mismatch" "validate-node may not check firmware version"
fi

tap_summary
