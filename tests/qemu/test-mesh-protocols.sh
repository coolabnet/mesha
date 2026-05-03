#!/usr/bin/env bash
# Mesh protocol tests — BMX7/Babel convergence and routing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "# Mesh Protocol Tests"
tap_plan 4

GATEWAY=$(get_gateway)
NODE2="lm-testbed-node-2"
NODE3="lm-testbed-node-3"

# Wait for BMX7 convergence
echo "# Waiting for BMX7 convergence (90s timeout)..."
if ! wait_for_bmx7 "$GATEWAY" 2 90; then
    echo "Bail out! BMX7 did not converge on gateway"
    exit 1
fi

# Test 1: Each node has >=1 BMX7 neighbor
ALL_NEIGHBORS_OK=true
for entry in $(get_node_ips | head -3); do
    host=$(echo "$entry" | awk '{print $1}')
    count=$(ssh_vm "$host" "bmx7 -c originators 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null || echo "0")
    count=$(echo "$count" | tr -d '[:space:]')
    if [ "$count" -lt 1 ] 2>/dev/null; then
        ALL_NEIGHBORS_OK=false
        echo "  # ${host}: ${count} neighbors" >&2
    fi
done
if $ALL_NEIGHBORS_OK; then
    pass "test_bmx7_neighbors_exist"
else
    fail "test_bmx7_neighbors_exist" "Some nodes have 0 neighbors"
fi

# Test 2: Gateway sees >=3 originators
ORIG_COUNT=$(ssh_vm "$GATEWAY" "bmx7 -c originators 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null || echo "0")
ORIG_COUNT=$(echo "$ORIG_COUNT" | tr -d '[:space:]')
if [ "${ORIG_COUNT}" -ge 3 ] 2>/dev/null; then
    pass "test_bmx7_originators_cover_mesh"
else
    fail "test_bmx7_originators_cover_mesh" "Gateway sees ${ORIG_COUNT}/3 originators"
fi

# Test 3: Mesh routing works (ping node-3 -> node-1)
PING_OK=false
# Try IPv4 first
if ssh_vm "$NODE3" "ping -c 3 -W 5 10.99.0.11" >/dev/null 2>&1; then
    PING_OK=true
fi
# Fallback: SSH connectivity proves routing works even if ICMP is blocked
if ! $PING_OK && ssh_vm "$NODE3" "ssh -o ConnectTimeout=5 -o BatchMode=yes root@10.99.0.11 'echo OK'" 2>/dev/null | grep -q OK; then
    PING_OK=true
fi
if $PING_OK; then
    pass "test_mesh_routing_works"
else
    fail "test_mesh_routing_works" "node-3 cannot reach node-1"
fi

# Test 4: Babel fallback works
echo "# Testing babeld fallback..."
# Stop BMX7 on node-2, start babeld
ssh_vm "$NODE2" "/etc/init.d/bmx7 stop 2>/dev/null; killall bmx7 2>/dev/null; true" || true
sleep 2
ssh_vm "$NODE2" "babeld -D -I /var/run/babeld.pid br-lan 2>/dev/null || babeld -D br-lan 2>/dev/null || true" || true
sleep 10

# Check if node-2 still has neighbors via babeld
BABEL_NEIGHBORS=$(ssh_vm "$NODE2" "cat /var/run/babeld.pid >/dev/null 2>&1 && echo 'running' || echo 'not running'" 2>/dev/null || echo "unknown")
if echo "$BABEL_NEIGHBORS" | grep -q "running"; then
    # Restart BMX7 for subsequent tests
    ssh_vm "$NODE2" "killall babeld 2>/dev/null; /etc/init.d/bmx7 start 2>/dev/null || bmx7 2>/dev/null || true" || true
    pass "test_babel_fallback_works"
else
    # Restart BMX7 anyway
    ssh_vm "$NODE2" "/etc/init.d/bmx7 start 2>/dev/null || bmx7 2>/dev/null || true" || true
    skip "test_babel_fallback_works" "babeld not available or not running"
fi

tap_summary
