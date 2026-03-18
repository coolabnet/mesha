#!/usr/bin/env bash

set -euo pipefail

cd /workspace

wait_for_http() {
    local url="$1"
    local attempts="${2:-30}"
    local delay="${3:-1}"
    local i
    for ((i=1; i<=attempts; i++)); do
        if curl -fsS "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$delay"
    done
    return 1
}

wait_for_ssh() {
    local host="$1"
    local attempts="${2:-30}"
    local delay="${3:-1}"
    local i
    for ((i=1; i<=attempts; i++)); do
        if ssh -o ConnectTimeout=3 -o BatchMode=yes root@"$host" "true" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$delay"
    done
    return 1
}

wait_for_http "http://thisnode.info/" 30 1
wait_for_ssh "thisnode.info" 30 1
wait_for_ssh "fake-gateway" 30 1

doctor_rc=0
bash scripts/doctor.sh >/tmp/doctor.out 2>&1 || doctor_rc=$?
if [[ "$doctor_rc" -ne 0 && "$doctor_rc" -ne 2 ]]; then
    cat /tmp/doctor.out
    echo "doctor.sh failed unexpectedly with rc=$doctor_rc" >&2
    exit 1
fi

bash scripts/activate-workspace.sh >/tmp/activate.out 2>&1
bash scripts/discover-from-thisnode.sh --plan >/tmp/discover-plan.json
bash scripts/discover-from-thisnode.sh >/tmp/discover.out
bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --plan >/tmp/mesh-plan.json
bash skills/mesh-readonly/scripts/run-mesh-readonly.sh >/tmp/mesh-live.json
bash scripts/mesh-heartbeat.sh >/tmp/heartbeat.out

python3 - <<'PYEOF'
import json
from pathlib import Path

workspace = Path("/workspace")

discover_plan = json.loads(Path("/tmp/discover-plan.json").read_text())
assert discover_plan["target_host"] == "thisnode.info"
assert "latest_gateway_candidate" in discover_plan["writes_to"]

discover_latest = json.loads((workspace / "exports/discovery/latest.json").read_text())
assert discover_latest["http_ok"] is True
assert discover_latest["ssh_ok"] is True
assert discover_latest["inferred"]["observed_hostname"] == "thisnode-fixture"
assert "10.13.0.10" in discover_latest["inferred"]["ipv4_candidates"]

assert (workspace / "exports/discovery/latest-candidate-node.yaml").exists()
assert (workspace / "exports/discovery/latest-candidate-gateway.yaml").exists()

mesh_plan = json.loads(Path("/tmp/mesh-plan.json").read_text())
assert mesh_plan["mode"] == "plan"
assert mesh_plan["inventory_targets"] == ["fake-thisnode", "fake-gateway"]
assert mesh_plan["topology_target"] == "fake-gateway"

mesh_live = json.loads(Path("/tmp/mesh-live.json").read_text())
assert mesh_live["mode"] == "live"
assert len(mesh_live["nodes"]) == 2
assert all(node["reachable"] for node in mesh_live["nodes"])
assert mesh_live["topology"]["reachable"] is True
assert mesh_live["topology"]["gateway_hostname"] == "gateway-fixture"
hostnames = {node["hostname"] for node in mesh_live["nodes"]}
assert hostnames == {"thisnode-fixture", "gateway-fixture"}

latest = json.loads((workspace / "exports/mesh/latest.json").read_text())
assert latest["mode"] == "live"
assert len(latest["nodes"]) == 2
assert latest["topology"]["reachable"] is True

summary = (workspace / "exports/mesh/latest-summary.txt").read_text()
assert "collected_at:" in summary
assert "overall:" in summary
PYEOF

echo "Phase 1 onboarding compose test passed."
