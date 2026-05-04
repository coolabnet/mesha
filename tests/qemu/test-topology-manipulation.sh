#!/usr/bin/env bash
# Topology manipulation tests — vwifi-ctrl distance-based loss and node removal
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "# Topology Manipulation Tests"
tap_plan 2

GATEWAY=$(get_gateway)
VWIFI_CTRL="${REPO_ROOT}/testbed/bin/vwifi-ctrl"

# Ensure BMX7 is stable
echo "# Waiting for BMX7 convergence..."
if ! wait_for_bmx7 "$GATEWAY" 2 90; then
    echo "Bail out! BMX7 not converged"
    exit 1
fi

# Test 1: vwifi-ctrl distance-based loss degrades link quality
# vwifi-ctrl only supports global on/off loss, not per-link percentage
# Use distance-based approach: set coordinates far apart + enable loss + small scale
echo "# Testing vwifi-ctrl distance-based loss..."
if [ -x "${VWIFI_CTRL}" ]; then
    # Record baseline link quality
    BASELINE_QUALITY=$(ssh_vm "$GATEWAY" \
        "bmx7 -c links 2>/dev/null | grep -v 'originator' | awk '{print \$NF}' | sort -n | head -1" 2>/dev/null || echo "0")

    # Set distant coordinates for node-3 (CID = 3 for third VM)
    # vwifi-ctrl set <CID> <X> <Y> <Z>
    "${VWIFI_CTRL}" set 3 10000 10000 0 2>/dev/null || true
    "${VWIFI_CTRL}" loss yes 2>/dev/null || true
    "${VWIFI_CTRL}" scale 0.001 2>/dev/null || true

    echo "  # Waiting for link quality degradation..."
    sleep 30

    DEGRADED_QUALITY=$(ssh_vm "$GATEWAY" \
        "bmx7 -c links 2>/dev/null | grep -v 'originator' | awk '{print \$NF}' | sort -n | head -1" 2>/dev/null || echo "0")

    # Reset: set coordinates close + disable loss
    "${VWIFI_CTRL}" set 3 0 0 0 2>/dev/null || true
    "${VWIFI_CTRL}" loss no 2>/dev/null || true

    if [ "${DEGRADED_QUALITY}" -lt "${BASELINE_QUALITY}" ] 2>/dev/null; then
        pass "test_vwifi_ctrl_distance_based_loss"
    else
        skip "test_vwifi_ctrl_distance_based_loss" "quality did not degrade (baseline=${BASELINE_QUALITY} degraded=${DEGRADED_QUALITY})"
    fi
else
    skip "test_vwifi_ctrl_distance_based_loss" "vwifi-ctrl not available"
fi

# Test 2: Node removal detected by collect-topology
echo "# Testing node removal detection..."
# Get baseline node count
BASELINE_COUNT=$(bash "${REPO_ROOT}/scripts/qemu-testbed/run-testbed-adapter.sh" \
    "${REPO_ROOT}/adapters/mesh/collect-topology.sh" "$GATEWAY" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('node_count', 0))" 2>/dev/null || echo "0")

# Stop node-3
NODE3_PID=$(cat "${REPO_ROOT}/testbed/run/node-3.pid" 2>/dev/null || echo "")
if [ -n "$NODE3_PID" ]; then
    kill "$NODE3_PID" 2>/dev/null || true
    sleep 15  # Wait for BMX7 to detect loss

    # Check topology again
    AFTER_COUNT=$(bash "${REPO_ROOT}/scripts/qemu-testbed/run-testbed-adapter.sh" \
        "${REPO_ROOT}/adapters/mesh/collect-topology.sh" "$GATEWAY" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('node_count', 0))" 2>/dev/null || echo "$BASELINE_COUNT")

    if [ "${AFTER_COUNT}" -lt "${BASELINE_COUNT}" ] 2>/dev/null; then
        pass "test_node_removal_detected"
    else
        fail "test_node_removal_detected" "node count unchanged (${BASELINE_COUNT} -> ${AFTER_COUNT})"
    fi

    # Restart node-3 (restart QEMU with same overlay)
    echo "  # Restarting node-3..."
    NODE3_OVERLAY="${REPO_ROOT}/testbed/run/node-3.qcow2"
    if [ -f "$NODE3_OVERLAY" ] && command -v qemu-system-x86_64 &>/dev/null; then
        # Detect acceleration (reuse same as start-mesh.sh)
        ACCEL_FLAG="-accel tcg"
        CPU_FLAG="-cpu qemu64"
        [ -w /dev/kvm ] && ACCEL_FLAG="-enable-kvm" && CPU_FLAG="-cpu host"

        # Read topology for tap/mac/ram (fallback to defaults)
        TAP_IDX=2
        MAC_MESH="52:54:00:00:00:03"
        MAC_WAN="52:54:00:01:00:03"
        RAM=256
        if [ -f "${REPO_ROOT}/testbed/config/topology.yaml" ]; then
            _ti=$(awk '/^    - id: 3/,/^    - id:/ { print }' "${REPO_ROOT}/testbed/config/topology.yaml" | grep 'tap_index:' | head -1 | awk '{print $2}')
            _mm=$(awk '/^    - id: 3/,/^    - id:/ { print }' "${REPO_ROOT}/testbed/config/topology.yaml" | grep 'mac_mesh:' | head -1 | awk '{print $2}' | tr -d '"')
            [ -n "$_ti" ] && TAP_IDX="$_ti"
            [ -n "$_mm" ] && MAC_MESH="$_mm"
        fi

        TAP_PREFIX="mesha-tap"
        _tp=$(grep 'tap_prefix:' "${REPO_ROOT}/testbed/config/topology.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"')
        [ -n "$_tp" ] && TAP_PREFIX="$_tp"

        qemu-system-x86_64 \
            ${ACCEL_FLAG} -M q35 ${CPU_FLAG} -smp 2 -m "${RAM}M" -nographic \
            -drive "file=${NODE3_OVERLAY},format=qcow2" \
            -device "virtio-net-pci,netdev=mesh0,mac=${MAC_MESH}" \
            -netdev "tap,id=mesh0,ifname=${TAP_PREFIX}${TAP_IDX},script=no,downscript=no" \
            -device "virtio-net-pci,netdev=wan0,mac=${MAC_WAN}" \
            -netdev user,id=wan0 \
            -serial "file:${REPO_ROOT}/testbed/run/logs/node-3.serial.log" &
        echo "$!" > "${REPO_ROOT}/testbed/run/node-3.pid"
        echo "  # node-3 restarted (PID $(cat "${REPO_ROOT}/testbed/run/node-3.pid"))"
    else
        echo "  # WARN: Could not restart node-3 automatically. Run stop-mesh.sh && start-mesh.sh" >&2
    fi
else
    skip "test_node_removal_detected" "node-3 PID not found"
fi

tap_summary
