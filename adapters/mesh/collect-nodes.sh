#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# adapters/mesh/collect-nodes.sh
#
# Usage:
#   ./collect-nodes.sh <node-ip-or-hostname>
#
# Description:
#   Connects to a LibreMesh/OpenWrt node via SSH (root, key auth assumed)
#   and collects read-only diagnostic information. Outputs a normalized
#   JSON object to stdout. Designed to be run by the mesh-collector agent.
#
# Output schema:
#   {
#     "collected_at": "<ISO8601 timestamp>",
#     "node_ip": "<ip used to connect>",
#     "reachable": true|false,
#     "error": "<error message if unreachable, else null>",
#     "hostname": "<string>",
#     "firmware_version": "<string>",
#     "uptime_seconds": <int>,
#     "uptime_human": "<string>",
#     "interfaces": [ { "name": "...", "mac": "...", "ipv4": "...", "ipv6": "..." } ],
#     "radios": [ { "name": "...", "ssid": "...", "channel": ..., "signal": "..." } ],
#     "mesh_neighbors": [ { "hostname": "...", "ip": "...", "metric": "..." } ]
#   }
#
# Risk class: A (read-only — no writes performed on the node)
# Credentials: SSH key auth; key must be available in the agent's ssh-agent
#              or in secrets/ per secrets/README.md convention.
#
# Dependencies: ssh, jq (for JSON assembly)
#
# Exit codes:
#   0 — success (JSON output to stdout, even if node was unreachable)
#   1 — usage error (wrong number of arguments)

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <node-ip-or-hostname>" >&2
  exit 1
fi

NODE_IP="$1"
COLLECTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SSH_TIMEOUT=10 # seconds before SSH gives up
SSH_OPTS=(-o "ConnectTimeout=${SSH_TIMEOUT}" -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR)

# ---------------------------------------------------------------------------
# Helper: emit an error JSON object and exit 0
# We exit 0 even on connection failure so the calling agent receives
# structured output rather than a bare non-zero exit code.
# ---------------------------------------------------------------------------
emit_error() {
  local error_msg="$1"
  jq -n \
    --arg collected_at "$COLLECTED_AT" \
    --arg node_ip "$NODE_IP" \
    --arg error "$error_msg" \
    '{
            collected_at: $collected_at,
            node_ip: $node_ip,
            reachable: false,
            error: $error,
            hostname: null,
            firmware_version: null,
            uptime_seconds: null,
            uptime_human: null,
            interfaces: [],
            radios: [],
            mesh_neighbors: []
        }'
  exit 0
}

# ---------------------------------------------------------------------------
# Connectivity check: attempt SSH before running full data collection
# ---------------------------------------------------------------------------
if ! ssh "${SSH_OPTS[@]}" root@"$NODE_IP" "true" 2>/dev/null; then
  emit_error "SSH connection failed to ${NODE_IP} (timeout=${SSH_TIMEOUT}s)"
fi

# ---------------------------------------------------------------------------
# Data collection via SSH
# All commands are read-only. Each command block is explained with comments.
# We run everything in a single SSH session to minimize round-trip overhead.
# ---------------------------------------------------------------------------
RAW_DATA="$(
  ssh "${SSH_OPTS[@]}" root@"$NODE_IP" sh -s <<'REMOTE_SCRIPT'

# --- Hostname ---
# uci show: reads the OpenWrt UCI configuration key directly.
# system.@system[0].hostname is the standard OpenWrt hostname setting.
HOSTNAME=$(uci get system.@system[0].hostname 2>/dev/null || cat /proc/sys/kernel/hostname)

# --- Firmware version ---
# /etc/openwrt_release is the standard file on OpenWrt/LibreMesh that
# identifies the build, version, and release name.
FIRMWARE_VERSION=$(grep -o 'DISTRIB_DESCRIPTION=.*' /etc/openwrt_release 2>/dev/null | cut -d'"' -f2 || echo 'unknown')

# --- Uptime ---
# /proc/uptime contains two fields: total uptime and idle time in seconds.
# We read the first field (total uptime, may include decimal) and truncate.
UPTIME_SECS=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || echo 0)

# Convert seconds to human-readable D+H:M:S format for the summary field
UPTIME_HUMAN=$(awk -v uptime="$UPTIME_SECS" 'BEGIN{
    s=uptime;
    d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); sec=s%60;
    printf "%dd %dh %dm %ds", d, h, m, sec
}')

# --- Network interfaces ---
# `ip -j addr show` outputs JSON with all interfaces, addresses, and MACs.
# We parse it further downstream in Python/jq, but collect raw JSON here.
IFACE_JSON=$(ip -j addr show 2>/dev/null || echo '[]')

# --- WiFi / radio status ---
# `iwinfo` is available on OpenWrt/LibreMesh and provides per-radio status.
# We use the `-d` flag to get detail in a parseable format.
# `iw dev` gives a more machine-readable alternative; we collect both.
IWINFO_OUT=$(iwinfo 2>/dev/null | head -80 || echo '')

# wifidevice list from UCI gives the configured radios
RADIOS_RAW=$(uci show wireless 2>/dev/null | grep '\.ssid\|\.channel\|\.band\|\.type' || echo '')

# --- BMX7 mesh neighbors ---
# BMX7 exposes its neighbor/link table via a Unix socket using `bmx7 -c`
# The `--links` option lists active mesh links with quality metrics.
BMX7_LINKS=$(bmx7 -c --links 2>/dev/null | head -60 || echo '')

# Also try babeld if bmx7 is not available or returns empty
BABEL_NEIGHBORS=$(echo 'dump neighbours' | nc -q1 localhost 33123 2>/dev/null | head -40 || echo '')

# --- Output everything as a simple key=value blob for parsing ---
cat <<EOF
__HOSTNAME__${HOSTNAME}
__FIRMWARE__${FIRMWARE_VERSION}
__UPTIME_SECS__${UPTIME_SECS}
__UPTIME_HUMAN__${UPTIME_HUMAN}
__IFACE_JSON_START__
${IFACE_JSON}
__IFACE_JSON_END__
__RADIOS_START__
${RADIOS_RAW}
__RADIOS_END__
__BMX7_START__
${BMX7_LINKS}
__BMX7_END__
__BABEL_START__
${BABEL_NEIGHBORS}
__BABEL_END__
EOF
REMOTE_SCRIPT
)"

# ---------------------------------------------------------------------------
# Parse collected data and assemble normalized JSON
# We use Python 3 for robust JSON construction from the raw text blocks.
# ---------------------------------------------------------------------------
python3 - <<PYEOF
import sys
import json
import re

raw = """${RAW_DATA}"""
lines = raw.splitlines()

def extract_value(marker, lines):
    for line in lines:
        if line.startswith(marker):
            return line[len(marker):].strip()
    return None

def extract_block(start_marker, end_marker, lines):
    collecting = False
    block = []
    for line in lines:
        if line.strip() == start_marker:
            collecting = True
            continue
        if line.strip() == end_marker:
            break
        if collecting:
            block.append(line)
    return "\n".join(block).strip()

hostname = extract_value("__HOSTNAME__", lines) or "unknown"
firmware = extract_value("__FIRMWARE__", lines) or "unknown"
uptime_secs_str = extract_value("__UPTIME_SECS__", lines) or "0"
uptime_human = extract_value("__UPTIME_HUMAN__", lines) or "unknown"

try:
    uptime_secs = int(uptime_secs_str)
except ValueError:
    uptime_secs = 0

# Parse interface JSON from 'ip -j addr show'
iface_raw = extract_block("__IFACE_JSON_START__", "__IFACE_JSON_END__", lines)
interfaces = []
try:
    iface_data = json.loads(iface_raw)
    for iface in iface_data:
        name = iface.get("ifname", "")
        mac = iface.get("address", "")
        ipv4 = next((a["local"] for a in iface.get("addr_info", []) if a.get("family") == "inet"), None)
        ipv6 = next((a["local"] for a in iface.get("addr_info", []) if a.get("family") == "inet6" and not a["local"].startswith("fe80")), None)
        if name and not name.startswith("lo"):
            interfaces.append({"name": name, "mac": mac, "ipv4": ipv4, "ipv6": ipv6})
except (json.JSONDecodeError, KeyError):
    interfaces = []

# Parse radio info from UCI wireless output
radios_raw = extract_block("__RADIOS_START__", "__RADIOS_END__", lines)
radios = []
radio_dict = {}
for line in radios_raw.splitlines():
    m = re.match(r"wireless\.(radio\d+|@wifi-iface\[\d+\])\.(\w+)='?(.*?)'?$", line.strip())
    if m:
        section, key, value = m.group(1), m.group(2), m.group(3)
        if section not in radio_dict:
            radio_dict[section] = {}
        radio_dict[section][key] = value
for section, props in radio_dict.items():
    if "channel" in props or "ssid" in props:
        radios.append({
            "name": section,
            "ssid": props.get("ssid"),
            "channel": props.get("channel"),
            "band": props.get("band") or props.get("hwmode"),
        })

# Parse BMX7 neighbor links
bmx7_raw = extract_block("__BMX7_START__", "__BMX7_END__", lines)
neighbors = []
for line in bmx7_raw.splitlines():
    # BMX7 link line format varies by version; look for IP-like tokens
    tokens = line.strip().split()
    if len(tokens) >= 3 and "." in tokens[0]:
        neighbors.append({
            "protocol": "bmx7",
            "ip": tokens[0],
            "interface": tokens[1] if len(tokens) > 1 else None,
            "metric": tokens[2] if len(tokens) > 2 else None,
        })

# Parse Babel neighbors as fallback
if not neighbors:
    babel_raw = extract_block("__BABEL_START__", "__BABEL_END__", lines)
    for line in babel_raw.splitlines():
        tokens = line.strip().split()
        if len(tokens) >= 2 and ("neighbour" in line.lower() or ":" in tokens[0]):
            neighbors.append({
                "protocol": "babeld",
                "ip": tokens[0],
                "interface": tokens[1] if len(tokens) > 1 else None,
                "metric": None,
            })

result = {
    "collected_at": "${COLLECTED_AT}",
    "node_ip": "${NODE_IP}",
    "reachable": True,
    "error": None,
    "hostname": hostname,
    "firmware_version": firmware,
    "uptime_seconds": uptime_secs,
    "uptime_human": uptime_human,
    "interfaces": interfaces,
    "radios": radios,
    "mesh_neighbors": neighbors,
}

print(json.dumps(result, indent=2))
PYEOF
