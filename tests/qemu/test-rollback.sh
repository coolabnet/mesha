#!/usr/bin/env bash
# Rollback-node integration test — verifies config rollback restores UCI state
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "# Rollback Node Tests"
tap_plan 2

GATEWAY=$(get_gateway)
REPO_ROOT_REAL="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test 1: rollback restores config
# Take a qcow2 snapshot for safety
QCOW2_IMAGE="${REPO_ROOT_REAL}/testbed/run/node-1.qcow2"
SNAPSHOT_NAME="pre-rollback"

cleanup_rollback() {
    # Restore qcow2 snapshot if it exists
    if [ -f "${QCOW2_IMAGE}" ]; then
        qemu-img snapshot -a "${SNAPSHOT_NAME}" "${QCOW2_IMAGE}" 2>/dev/null || true
        qemu-img snapshot -d "${SNAPSHOT_NAME}" "${QCOW2_IMAGE}" 2>/dev/null || true
    fi
    # Clean up temp files
    rm -f /tmp/rollback-backup.uci.gz 2>/dev/null || true
}

if [ ! -f "${QCOW2_IMAGE}" ]; then
    skip "test_rollback_restores_config" "qcow2 image not found at ${QCOW2_IMAGE}"
    skip "test_rollback_snapshot_cleanup" "no snapshot to clean"
    tap_summary
    exit 0
fi

qemu-img snapshot -c "${SNAPSHOT_NAME}" "${QCOW2_IMAGE}" 2>/dev/null || true
trap cleanup_rollback EXIT INT TERM

# Capture current hostname (the config value we'll modify and restore)
ORIGINAL_HOSTNAME=$(ssh_vm "$GATEWAY" "uci get system.@system[0].hostname" 2>/dev/null || echo "unknown")

if [ "${ORIGINAL_HOSTNAME}" = "unknown" ]; then
    skip "test_rollback_restores_config" "could not read current hostname from gateway"
    tap_summary
    exit 0
fi

# Capture current UCI state as backup
ssh_vm "$GATEWAY" "uci export | gzip" > /tmp/rollback-backup.uci.gz 2>/dev/null

if [ ! -s /tmp/rollback-backup.uci.gz ]; then
    skip "test_rollback_restores_config" "failed to capture UCI backup"
    tap_summary
    exit 0
fi

# Modify a known config value
ssh_vm "$GATEWAY" "uci set system.@system[0].hostname='modified-test'" 2>/dev/null || true
ssh_vm "$GATEWAY" "uci commit system" 2>/dev/null || true

# Verify modification took effect
MODIFIED=$(ssh_vm "$GATEWAY" "uci get system.@system[0].hostname" 2>/dev/null || echo "unknown")
if [ "${MODIFIED}" != "modified-test" ]; then
    fail "test_rollback_restores_config" "could not modify hostname for test setup (got: ${MODIFIED})"
    tap_summary
    exit 0
fi

# Run rollback via adapter wrapper with --yes flag
ROLLBACK_EXIT=0
bash "${REPO_ROOT_REAL}/scripts/qemu-testbed/run-testbed-adapter.sh" \
    "${REPO_ROOT_REAL}/skills/mesh-rollout/scripts/rollback-node.sh" \
    "$GATEWAY" "/tmp/rollback-backup.uci.gz" --yes >/dev/null 2>&1 || ROLLBACK_EXIT=$?

if [ "${ROLLBACK_EXIT}" -eq 0 ]; then
    # Verify hostname was restored
    RESTORED=$(ssh_vm "$GATEWAY" "uci get system.@system[0].hostname" 2>/dev/null || echo "unknown")
    if [ "${RESTORED}" = "${ORIGINAL_HOSTNAME}" ]; then
        pass "test_rollback_restores_config"
    else
        fail "test_rollback_restores_config" "hostname after rollback: '${RESTORED}', expected: '${ORIGINAL_HOSTNAME}'"
    fi
else
    fail "test_rollback_restores_config" "rollback-node.sh exited with code ${ROLLBACK_EXIT}"
fi

# Test 2: --yes flag skips interactive prompt (verified by non-interactive execution above)
if [ "${ROLLBACK_EXIT}" -eq 0 ]; then
    pass "test_rollback_yes_flag_skips_prompt"
else
    skip "test_rollback_yes_flag_skips_prompt" "rollback did not succeed, cannot verify --yes flag"
fi

tap_summary
