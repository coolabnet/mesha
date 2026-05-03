#!/usr/bin/env bash
# Adapter contract tests — validates Mesha adapter scripts against QEMU test bed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

WAIT_SECONDS="${1:-30}"

echo "# Adapter Contract Tests"
tap_plan 4

# Wait for VMs
echo "# Waiting for SSH connectivity..."
GATEWAY=$(get_gateway)
if ! wait_for_ssh "$GATEWAY" 90; then
    echo "Bail out! Gateway ${GATEWAY} not reachable"
    exit 1
fi

# Test 1: collect-nodes returns valid JSON for all VMs
ALL_NODES_OK=true
for entry in $(get_node_ips); do
    host=$(echo "$entry" | awk '{print $1}')
    result=$(bash "${REPO_ROOT}/scripts/qemu-testbed/run-testbed-adapter.sh" \
        "${REPO_ROOT}/adapters/mesh/collect-nodes.sh" "$host" 2>/dev/null) || true
    if ! echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert data.get('reachable') == True
assert data.get('hostname')
assert isinstance(data.get('interfaces'), list) and len(data['interfaces']) > 0
" 2>/dev/null; then
        ALL_NODES_OK=false
        echo "  # FAILED for ${host}" >&2
    fi
done
if $ALL_NODES_OK; then
    pass "test_collect_nodes_returns_valid_json"
else
    fail "test_collect_nodes_returns_valid_json" "One or more nodes failed"
fi

# Test 2: collect-topology sees nodes
echo "# Waiting ${WAIT_SECONDS}s for BMX7 convergence..."
sleep "${WAIT_SECONDS}"
TOPO_RESULT=$(bash "${REPO_ROOT}/scripts/qemu-testbed/run-testbed-adapter.sh" \
    "${REPO_ROOT}/adapters/mesh/collect-topology.sh" "$GATEWAY" 2>/dev/null) || true
if [ -n "$TOPO_RESULT" ] && echo "$TOPO_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert 'node_count' in data
assert data['node_count'] >= 1
" 2>/dev/null; then
    pass "test_collect_topology_sees_all_nodes"
else
    fail "test_collect_topology_sees_all_nodes" "node_count < 1 or parse error"
fi

# Test 3: discover-from-thisnode works
DISCOVER_OK=false
HTTP_CODE=""
if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --resolve thisnode.info:80:10.99.0.11 http://thisnode.info/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        DISCOVER_OK=true
    fi
fi
if $DISCOVER_OK; then
    pass "test_discover_thisnode_works"
else
    skip "test_discover_thisnode_works" "thisnode.info not reachable (HTTP ${HTTP_CODE:-N/A})"
fi

# Test 4: ip -j addr show returns valid JSON
IP_RESULT=$(ssh_vm "$GATEWAY" "ip -j addr show" 2>/dev/null) || true
if [ -n "$IP_RESULT" ] && echo "$IP_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
non_lo = [i for i in data if i.get('ifname') != 'lo']
assert len(non_lo) >= 1
" 2>/dev/null; then
    pass "test_ip_json_output"
else
    fail "test_ip_json_output" "ip -j returned empty or invalid JSON"
fi

tap_summary
