#!/usr/bin/env bash
# skills/mesh-readonly/scripts/run-mesh-readonly.sh
#
# Runs the real mesh read-only adapters over the current inventory and emits a
# single JSON document that OpenClaw can summarize without inventing status
# fields from stub inventories.
#
# Usage:
#   bash skills/mesh-readonly/scripts/run-mesh-readonly.sh
#   bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --hostname lm-node-1
#   bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --plan
#
# Exit codes:
#   0 - command completed and emitted JSON
#   1 - usage or local prerequisite error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
NODES_FILE="$REPO_ROOT/inventories/mesh-nodes.yaml"
GATEWAYS_FILE="$REPO_ROOT/inventories/gateways.yaml"
COLLECT_NODES="$REPO_ROOT/adapters/mesh/collect-nodes.sh"
COLLECT_TOPOLOGY="$REPO_ROOT/adapters/mesh/collect-topology.sh"

PLAN_ONLY=false
SKIP_TOPOLOGY=false
REQUESTED_HOSTNAME=""
COLLECTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

usage() {
    cat <<EOF >&2
Usage: $0 [--hostname <node-hostname>] [--plan] [--skip-topology]

Options:
  --hostname <node-hostname>  Limit collection to a single hostname from inventory
  --plan                      Show selected targets without running live adapters
  --skip-topology             Skip the topology adapter even in live mode
  -h, --help                  Show this help
EOF
    exit 1
}

trim_quotes() {
    local value="$1"
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    printf '%s\n' "$value"
}

extract_yaml_values() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            line = $0
            sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
            sub("[[:space:]]+#.*$", "", line)
            print line
        }
    ' "$file" | while IFS= read -r raw_value; do
        trim_quotes "$raw_value"
    done | awk 'NF && !seen[$0]++'
}

emit_json_error() {
    local message="$1"
    python3 - "$COLLECTED_AT" "$REQUESTED_HOSTNAME" "$message" <<'PYEOF'
import json
import sys

collected_at, requested_hostname, message = sys.argv[1:4]
print(json.dumps({
    "collected_at": collected_at,
    "mode": "live",
    "requested_hostname": requested_hostname or None,
    "error": message,
    "inventory_targets": [],
    "topology_target": None,
    "nodes": [],
    "topology": None,
    "summary": {
        "overall": "No live mesh data was collected.",
        "confirmed_findings": [message],
        "possible_causes": [],
        "recommended_next_steps": [
            "Confirm inventories/mesh-nodes.yaml contains real reachable hostnames or IPs.",
            "Confirm SSH credentials are configured for the mesh adapters.",
            "Re-run mesh-readonly after connectivity is available."
        ]
    }
}, indent=2))
PYEOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)
            [[ $# -ge 2 ]] || usage
            REQUESTED_HOSTNAME="$2"
            shift 2
            ;;
        --plan)
            PLAN_ONLY=true
            shift
            ;;
        --skip-topology)
            SKIP_TOPOLOGY=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

[[ -x "$COLLECT_NODES" ]] || {
    emit_json_error "Mesh node adapter not executable: $COLLECT_NODES"
    exit 0
}

[[ -x "$COLLECT_TOPOLOGY" ]] || {
    emit_json_error "Mesh topology adapter not executable: $COLLECT_TOPOLOGY"
    exit 0
}

if [[ ! -f "$NODES_FILE" ]]; then
    emit_json_error "Node inventory not found: $NODES_FILE"
    exit 0
fi

mapfile -t INVENTORY_HOSTS < <(extract_yaml_values "$NODES_FILE" "hostname")

if [[ ${#INVENTORY_HOSTS[@]} -eq 0 ]]; then
    emit_json_error "Node inventory has no hostnames to query."
    exit 0
fi

TARGET_HOSTS=()
if [[ -n "$REQUESTED_HOSTNAME" ]]; then
    found_match=false
    for host in "${INVENTORY_HOSTS[@]}"; do
        if [[ "$host" == "$REQUESTED_HOSTNAME" ]]; then
            TARGET_HOSTS+=("$host")
            found_match=true
            break
        fi
    done

    if [[ "$found_match" == false ]]; then
        emit_json_error "Requested hostname not found in inventory: $REQUESTED_HOSTNAME"
        exit 0
    fi
else
    TARGET_HOSTS=("${INVENTORY_HOSTS[@]}")
fi

TOPOLOGY_TARGET=""
if [[ "$SKIP_TOPOLOGY" == false ]]; then
    while IFS= read -r gateway; do
        TOPOLOGY_TARGET="$gateway"
        break
    done < <(extract_yaml_values "$GATEWAYS_FILE" "hostname")

    if [[ -z "$TOPOLOGY_TARGET" && ${#TARGET_HOSTS[@]} -gt 0 ]]; then
        TOPOLOGY_TARGET="${TARGET_HOSTS[0]}"
    fi
fi

if [[ "$PLAN_ONLY" == true ]]; then
    python3 - "$COLLECTED_AT" "$REQUESTED_HOSTNAME" "$TOPOLOGY_TARGET" "${TARGET_HOSTS[@]}" <<'PYEOF'
import json
import sys

collected_at = sys.argv[1]
requested_hostname = sys.argv[2] or None
topology_target = sys.argv[3] or None
targets = sys.argv[4:]

print(json.dumps({
    "collected_at": collected_at,
    "mode": "plan",
    "requested_hostname": requested_hostname,
    "inventory_targets": targets,
    "topology_target": topology_target,
    "summary": {
        "overall": "Plan-only mode: no live mesh adapters were executed.",
        "confirmed_findings": [
            f"{len(targets)} node target(s) selected from inventory."
        ],
        "possible_causes": [],
        "recommended_next_steps": [
            "Run without --plan to execute the live mesh adapters."
        ]
    }
}, indent=2))
PYEOF
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/nodes"

index=0
for host in "${TARGET_HOSTS[@]}"; do
    bash "$COLLECT_NODES" "$host" > "$TMP_DIR/nodes/$(printf '%03d' "$index").json"
    index=$((index + 1))
done

if [[ -n "$TOPOLOGY_TARGET" ]]; then
    bash "$COLLECT_TOPOLOGY" "$TOPOLOGY_TARGET" > "$TMP_DIR/topology.json"
fi

python3 - "$TMP_DIR" "$COLLECTED_AT" "$REQUESTED_HOSTNAME" "$TOPOLOGY_TARGET" "${TARGET_HOSTS[@]}" <<'PYEOF'
import json
import pathlib
import sys

tmp_dir = pathlib.Path(sys.argv[1])
collected_at = sys.argv[2]
requested_hostname = sys.argv[3] or None
topology_target = sys.argv[4] or None
inventory_targets = sys.argv[5:]

nodes = []
for path in sorted((tmp_dir / "nodes").glob("*.json")):
    with path.open("r", encoding="utf-8") as handle:
        nodes.append(json.load(handle))

topology = None
topology_path = tmp_dir / "topology.json"
if topology_path.exists():
    with topology_path.open("r", encoding="utf-8") as handle:
        topology = json.load(handle)

reachable_nodes = [node for node in nodes if node.get("reachable") is True]
unreachable_nodes = [node for node in nodes if node.get("reachable") is not True]
confirmed_findings = []
possible_causes = []
recommended_next_steps = []

if reachable_nodes:
    confirmed_findings.append(
        f"{len(reachable_nodes)} of {len(nodes)} node checks returned live data."
    )
else:
    confirmed_findings.append("No node checks returned live data.")

if unreachable_nodes:
    unreachable_labels = [
        node.get("hostname") or node.get("node_ip") or "unknown-node"
        for node in unreachable_nodes
    ]
    confirmed_findings.append(
        "Unreachable nodes: " + ", ".join(unreachable_labels) + "."
    )
    possible_causes.append(
        "DNS for inventory hostnames is missing, SSH credentials are not configured, or the nodes are offline."
    )
    recommended_next_steps.append(
        "Confirm each inventory hostname resolves from the OpenClaw host, or replace it with a reachable management IP."
    )
    recommended_next_steps.append(
        "Confirm SSH key-based access is configured for the mesh adapters."
    )

if topology is not None and topology.get("reachable") is True:
    gateway_label = topology.get("gateway_hostname") or topology.get("gateway_ip") or topology_target
    confirmed_findings.append(f"Topology snapshot collected from {gateway_label}.")
elif topology_target:
    confirmed_findings.append(f"Topology snapshot failed from {topology_target}.")
    possible_causes.append(
        "The selected gateway is unreachable or does not expose BMX7/Babel status to the adapter."
    )
    recommended_next_steps.append(
        "Verify the gateway target in inventories/gateways.yaml is correct and reachable."
    )

if not reachable_nodes and not (topology is not None and topology.get("reachable") is True):
    overall = (
        "No live mesh data was collected. Treat this as an adapter failure, not as current mesh status."
    )
else:
    overall = (
        f"Live mesh collection completed for {len(reachable_nodes)} reachable node(s)"
        f" out of {len(nodes)} requested target(s)."
    )
    if unreachable_nodes:
        overall += " Some nodes could not be reached."

result = {
    "collected_at": collected_at,
    "mode": "live",
    "requested_hostname": requested_hostname,
    "inventory_targets": inventory_targets,
    "topology_target": topology_target,
    "nodes": nodes,
    "topology": topology,
    "summary": {
        "overall": overall,
        "confirmed_findings": confirmed_findings,
        "possible_causes": possible_causes,
        "recommended_next_steps": recommended_next_steps,
    },
}

print(json.dumps(result, indent=2))
PYEOF
