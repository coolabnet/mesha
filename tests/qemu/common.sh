#!/usr/bin/env bash
# Common test functions for QEMU test suite
# TAP-compatible output (Test Anything Protocol)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SSH_CONFIG="${REPO_ROOT}/testbed/config/ssh-config.resolved"
TOPOLOGY_FILE="${REPO_ROOT}/testbed/config/topology.yaml"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# TAP output functions
tap_plan() {
    echo "1..$1"
}

pass() {
    TEST_COUNT=$((TEST_COUNT + 1))
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "ok ${TEST_COUNT} - $1"
}

fail() {
    TEST_COUNT=$((TEST_COUNT + 1))
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "not ok ${TEST_COUNT} - $1"
    [ -n "${2:-}" ] && echo "  # $2" >&2
}

skip() {
    TEST_COUNT=$((TEST_COUNT + 1))
    echo "ok ${TEST_COUNT} - $1 # SKIP ${2:-}"
}

# SSH helper — run command on VM
ssh_vm() {
    local host="$1"; shift
    ssh -F "${SSH_CONFIG}" -o ConnectTimeout=10 -o BatchMode=yes "root@${host}" "$@" 2>/dev/null
}

# Get VM IPs from topology
get_node_ips() {
    if command -v python3 >/dev/null 2>&1 && [ -f "${TOPOLOGY_FILE}" ]; then
        python3 -c "
import yaml, sys
with open('${TOPOLOGY_FILE}') as f:
    topo = yaml.safe_load(f)
for n in topo['mesh']['nodes']:
    print(f\"{n['hostname']} {n['ip']}\")
" 2>/dev/null
    else
        # Fallback defaults
        echo "lm-testbed-node-1 10.99.0.11"
        echo "lm-testbed-node-2 10.99.0.12"
        echo "lm-testbed-node-3 10.99.0.13"
        echo "lm-testbed-tester 10.99.0.14"
    fi
}

# Get gateway hostname
get_gateway() { echo "lm-testbed-node-1"; }

# Wait for SSH on a host (with timeout)
wait_for_ssh() {
    local host="$1"
    local timeout="${2:-90}"
    local start
    start=$(date +%s)
    while true; do
        if ssh_vm "$host" "true" 2>/dev/null; then
            return 0
        fi
        local now
        now=$(date +%s)
        if (( now - start >= timeout )); then
            return 1
        fi
        sleep 5
    done
}

# TCG timeout multiplier support
TIMEOUT_MULTIPLIER="${QEMU_TIMEOUT_MULTIPLIER:-1}"

# Wait until a JSON field meets a condition (polls in a loop)
wait_until_json_gte() {
    local json="$1"
    local field="$2"
    local threshold="$3"
    local timeout="${4:-60}"
    timeout=$((timeout * TIMEOUT_MULTIPLIER))
    local start
    start=$(date +%s)
    while true; do
        local value
        value=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)${field})" 2>/dev/null) || return 1
        if [ "$value" -ge "$threshold" ] 2>/dev/null; then
            return 0
        fi
        local now
        now=$(date +%s)
        if (( now - start >= timeout )); then
            return 1
        fi
        sleep 5
    done
}

# Wait for BMX7 convergence on a node
wait_for_bmx7() {
    local host="$1"
    local min_neighbors="${2:-1}"
    local timeout="${3:-90}"
    local start
    start=$(date +%s)
    while true; do
        local count
        count=$(ssh_vm "$host" "bmx7 -c originators 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null || echo "0")
        count=$(echo "$count" | tr -d '[:space:]')
        if [ "$count" -ge "$min_neighbors" ] 2>/dev/null; then
            return 0
        fi
        local now
        now=$(date +%s)
        if (( now - start >= timeout )); then
            return 1
        fi
        sleep 5
    done
}

# Assert JSON field value
assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local actual
    actual=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)${field})" 2>/dev/null) || return 1
    [ "$actual" = "$expected" ]
}

# Assert JSON field >= threshold
assert_json_gte() {
    local json="$1"
    local field="$2"
    local threshold="$3"
    local actual
    actual=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)${field})" 2>/dev/null) || return 1
    [ "$actual" -ge "$threshold" ] 2>/dev/null
}

# Assert JSON field is not null/empty
assert_json_not_null() {
    local json="$1"
    local field="$2"
    local actual
    actual=$(echo "$json" | python3 -c "import sys,json; v=json.load(sys.stdin); print('NULL' if v is None else str(v))" 2>/dev/null)
    [ "${actual}" != "NULL" ] && [ -n "${actual}" ]
}

# Print test summary
tap_summary() {
    echo "---"
    echo "# Tests: ${TEST_COUNT}, Passed: ${PASS_COUNT}, Failed: ${FAIL_COUNT}"
    if [ "${FAIL_COUNT}" -gt 0 ]; then
        return 1
    fi
    return 0
}
