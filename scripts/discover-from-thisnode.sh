#!/usr/bin/env bash
# scripts/discover-from-thisnode.sh
#
# Bootstrap discovery for LibreMesh/OpenWrt networks where the currently
# connected node is reachable as thisnode.info.
#
# This script is read-only. It collects a few safe discovery artifacts from
# root@thisnode.info and writes them under exports/discovery/ so a maintainer
# can seed the durable inventory with real values.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_ROOT="$REPO_ROOT/exports/discovery"
RAW_DIR="$EXPORT_ROOT/raw"
TARGET_HOST="thisnode.info"
PLAN_ONLY=false

usage() {
    cat <<EOF >&2
Usage: $0 [--plan]

Options:
  --plan             Show what would run without touching the network
  -h, --help         Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan)
            PLAN_ONLY=true
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

if [[ "$PLAN_ONLY" == true ]]; then
    python3 - "$TARGET_HOST" "$EXPORT_ROOT" "$RAW_DIR" <<'PYEOF'
import json
import sys

target_host, export_root, raw_dir = sys.argv[1:4]

print(json.dumps({
    "mode": "plan",
    "target_host": target_host,
    "writes_to": {
        "latest_json": f"{export_root}/latest.json",
        "latest_summary": f"{export_root}/latest-summary.txt",
        "latest_candidate": f"{export_root}/latest-candidate-node.yaml",
        "latest_gateway_candidate": f"{export_root}/latest-candidate-gateway.yaml",
        "raw_dir": raw_dir,
    },
    "http_probe": f"http://{target_host}/",
    "ssh_commands": [
        f"ssh root@{target_host} uci show network",
        f"ssh root@{target_host} ubus call network.interface dump",
        f"ssh root@{target_host} ubus call network.wireless status",
    ],
    "purpose": [
        "bootstrap first-contact discovery from the currently connected LibreMesh node",
        "produce draft machine-observed data under exports/discovery/",
        "avoid writing curated inventory files automatically",
    ],
}, indent=2))
PYEOF
    exit 0
fi

mkdir -p "$RAW_DIR"

STAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
LATEST_JSON="$EXPORT_ROOT/latest.json"
LATEST_SUMMARY="$EXPORT_ROOT/latest-summary.txt"
LATEST_CANDIDATE="$EXPORT_ROOT/latest-candidate-node.yaml"
LATEST_GATEWAY_CANDIDATE="$EXPORT_ROOT/latest-candidate-gateway.yaml"
RAW_HTTP="$RAW_DIR/$STAMP.http.html"
RAW_NETWORK="$RAW_DIR/$STAMP.uci-network.txt"
RAW_INTERFACES="$RAW_DIR/$STAMP.interface-dump.json"
RAW_WIRELESS="$RAW_DIR/$STAMP.wireless-status.json"
RAW_HOSTNAME="$RAW_DIR/$STAMP.hostname.txt"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

SSH_TIMEOUT=10
SSH_OPTS=(
    -o "ConnectTimeout=${SSH_TIMEOUT}"
    -o StrictHostKeyChecking=no
    -o BatchMode=yes
    -o LogLevel=ERROR
)

HTTP_OK=false
SSH_OK=false
HTTP_ERROR=""
SSH_ERROR=""

if curl -fsSL "http://${TARGET_HOST}/" > "$RAW_HTTP" 2>/dev/null; then
    HTTP_OK=true
else
    HTTP_ERROR="HTTP request to http://${TARGET_HOST}/ failed"
    : > "$RAW_HTTP"
fi

if ssh "${SSH_OPTS[@]}" root@"$TARGET_HOST" "true" 2>/dev/null; then
    SSH_OK=true
    if ! ssh "${SSH_OPTS[@]}" root@"$TARGET_HOST" "uci show network" > "$RAW_NETWORK" 2>/dev/null; then
        SSH_ERROR="SSH connected but 'uci show network' failed"
        : > "$RAW_NETWORK"
    fi
    if ! ssh "${SSH_OPTS[@]}" root@"$TARGET_HOST" "ubus call network.interface dump" > "$RAW_INTERFACES" 2>/dev/null; then
        SSH_ERROR="SSH connected but 'ubus call network.interface dump' failed"
        : > "$RAW_INTERFACES"
    fi
    if ! ssh "${SSH_OPTS[@]}" root@"$TARGET_HOST" "ubus call network.wireless status" > "$RAW_WIRELESS" 2>/dev/null; then
        SSH_ERROR="SSH connected but 'ubus call network.wireless status' failed"
        : > "$RAW_WIRELESS"
    fi
    if ! ssh "${SSH_OPTS[@]}" root@"$TARGET_HOST" "uci get system.@system[0].hostname 2>/dev/null || cat /proc/sys/kernel/hostname" > "$RAW_HOSTNAME" 2>/dev/null; then
        : > "$RAW_HOSTNAME"
    fi
else
    SSH_ERROR="SSH connection to root@${TARGET_HOST} failed (timeout=${SSH_TIMEOUT}s)"
    : > "$RAW_NETWORK"
    : > "$RAW_INTERFACES"
    : > "$RAW_WIRELESS"
    : > "$RAW_HOSTNAME"
fi

python3 - "$STAMP" "$TARGET_HOST" "$HTTP_OK" "$SSH_OK" "$HTTP_ERROR" "$SSH_ERROR" "$RAW_HTTP" "$RAW_NETWORK" "$RAW_INTERFACES" "$RAW_WIRELESS" "$RAW_HOSTNAME" "$LATEST_SUMMARY" "$LATEST_CANDIDATE" "$LATEST_GATEWAY_CANDIDATE" <<'PYEOF' > "$TMP_JSON"
import json
import pathlib
import sys

(
    stamp,
    target_host,
    http_ok_raw,
    ssh_ok_raw,
    http_error,
    ssh_error,
    raw_http,
    raw_network,
    raw_interfaces,
    raw_wireless,
    raw_hostname,
    latest_summary,
    latest_candidate,
    latest_gateway_candidate,
) = sys.argv[1:15]

http_path = pathlib.Path(raw_http)
network_path = pathlib.Path(raw_network)
interfaces_path = pathlib.Path(raw_interfaces)
wireless_path = pathlib.Path(raw_wireless)
hostname_path = pathlib.Path(raw_hostname)

http_ok = http_ok_raw.lower() == "true"
ssh_ok = ssh_ok_raw.lower() == "true"

http_text = http_path.read_text(encoding="utf-8", errors="ignore") if http_path.exists() else ""
network_text = network_path.read_text(encoding="utf-8", errors="ignore") if network_path.exists() else ""
hostname_text = hostname_path.read_text(encoding="utf-8", errors="ignore").strip() if hostname_path.exists() else ""

try:
    interface_dump = json.loads(interfaces_path.read_text(encoding="utf-8")) if interfaces_path.exists() and interfaces_path.stat().st_size else None
except json.JSONDecodeError:
    interface_dump = None

try:
    wireless_status = json.loads(wireless_path.read_text(encoding="utf-8")) if wireless_path.exists() and wireless_path.stat().st_size else None
except json.JSONDecodeError:
    wireless_status = None

hostname = hostname_text or None

ipv4_candidates = []
interface_names = []
if isinstance(interface_dump, dict):
    for item in interface_dump.get("interface", []):
        name = item.get("interface")
        if name:
            interface_names.append(name)
        for route in item.get("route", []):
            target = route.get("target")
            if target and target not in ipv4_candidates and "." in target:
                ipv4_candidates.append(target)
        for addr in item.get("ipv4-address", []):
            address = addr.get("address")
            if address and address not in ipv4_candidates:
                ipv4_candidates.append(address)

wifi_radios = []
if isinstance(wireless_status, dict):
    for radio_name, radio_data in wireless_status.items():
        wifi_radios.append({
            "radio": radio_name,
            "up": radio_data.get("up"),
        })

result = {
    "collected_at": stamp,
    "target_host": target_host,
    "http_ok": http_ok,
    "ssh_ok": ssh_ok,
    "http_error": http_error or None,
    "ssh_error": ssh_error or None,
    "inferred": {
        "observed_hostname": hostname,
        "ipv4_candidates": ipv4_candidates,
        "interface_names": interface_names,
        "wifi_radios": wifi_radios,
    },
    "artifacts": {
        "http_html": raw_http,
        "uci_network": raw_network,
        "interface_dump_json": raw_interfaces,
        "wireless_status_json": raw_wireless,
    },
}

summary_lines = [
    f"collected_at: {stamp}",
    f"target_host: {target_host}",
    f"http_ok: {http_ok}",
    f"ssh_ok: {ssh_ok}",
]

if http_error:
    summary_lines.append(f"http_error: {http_error}")
if ssh_error:
    summary_lines.append(f"ssh_error: {ssh_error}")

summary_lines.extend([
    "",
    f"observed_hostname: {hostname or 'unknown'}",
    "ipv4_candidates:",
])

if ipv4_candidates:
    for ip in ipv4_candidates:
        summary_lines.append(f"- {ip}")
else:
    summary_lines.append("- none discovered")

summary_lines.append("")
summary_lines.append("next_steps:")
summary_lines.append("- review exports/discovery/latest.json")
summary_lines.append("- use observed hostname/IPs to seed inventories/mesh-nodes.yaml")
summary_lines.append("- keep site names, contacts, and physical notes manual")

pathlib.Path(latest_summary).write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

candidate_lines = [
    "nodes:",
    '  - name: "RENAME-ME"',
    f'    hostname: "{hostname or target_host}"',
    '    site: "REQUIRED"',
    '    model: "REQUIRED"',
    '    firmware_version: "unknown"',
    '    role: "REQUIRED"',
    '    status: unconfirmed',
    '    notes: "Bootstrap candidate generated from thisnode.info discovery"',
    "",
    "# Replace REQUIRED fields before merging into inventories/mesh-nodes.yaml",
]
pathlib.Path(latest_candidate).write_text("\n".join(candidate_lines) + "\n", encoding="utf-8")

gateway_candidate_lines = [
    "gateways:",
    '  - node: "REVIEW_IF_GATEWAY"',
    f'    hostname: "{hostname or target_host}"',
    '    uplink_type: "REQUIRED_IF_GATEWAY"',
    '    uplink_isp: "REQUIRED_IF_GATEWAY"',
    '    uplink_ip: "REVIEW_ME"',
    '    priority: 10',
    '    status: unconfirmed',
    '    notes: "Bootstrap gateway candidate generated from thisnode.info discovery. Remove if this node is not a gateway."',
    "",
    "# Merge into inventories/gateways.yaml only if this node really has an uplink role.",
]
pathlib.Path(latest_gateway_candidate).write_text("\n".join(gateway_candidate_lines) + "\n", encoding="utf-8")
print(json.dumps(result, indent=2))
PYEOF

cp "$TMP_JSON" "$LATEST_JSON"

echo "bootstrap discovery wrote:"
echo "  $LATEST_JSON"
echo "  $LATEST_SUMMARY"
echo "  $LATEST_CANDIDATE"
echo "  $LATEST_GATEWAY_CANDIDATE"
echo "  $RAW_HTTP"
echo "  $RAW_NETWORK"
echo "  $RAW_INTERFACES"
echo "  $RAW_WIRELESS"
echo "  $RAW_HOSTNAME"
