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

# --- Neighbor/ARP table for IPv6->IPv4 resolution ---
# BMX7 on br-lan uses IPv6 link-local addresses; we need the ARP table
# to resolve those to IPv4 (via MAC address correlation).
NEIGHBOR_TABLE=$(ip neigh show 2>/dev/null || echo '')

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
__NEIGHBOR_START__
${NEIGHBOR_TABLE}
__NEIGHBOR_END__
__BABEL_START__
${BABEL_NEIGHBORS}
__BABEL_END__
EOF
REMOTE_SCRIPT
)"

# ---------------------------------------------------------------------------
# Parse collected data and assemble normalized JSON
# We use Python 3 for robust JSON construction from the raw text blocks.
# Raw data is written to a temp file to avoid unsafe string interpolation
# into Python code (the data may contain arbitrary content from nodes).
# ---------------------------------------------------------------------------
RAW_FILE=$(mktemp "${TMPDIR:-/tmp}/mesh-nodes-XXXXXX")
printf '%s' "${RAW_DATA}" > "${RAW_FILE}"
trap 'rm -f "${RAW_FILE}"' EXIT

python3 - <<PYEOF
import sys
import json
import re

with open("${RAW_FILE}", "r") as f:
    raw = f.read()
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

# Build IPv6->IPv4 lookup from neighbor/ARP table
# Neighbor entries look like:
#   10.99.0.12 dev br-lan lladdr 52:54:00:00:00:02 REACHABLE
#   fe80::5054:ff:fe00:2 dev br-lan lladdr 52:54:00:00:00:02 REACHABLE
# We use MAC as the join key: IPv6->MAC->IPv4
neighbor_raw = extract_block("__NEIGHBOR_START__", "__NEIGHBOR_END__", lines)
mac_to_ipv4 = {}
for line in neighbor_raw.splitlines():
    parts = line.strip().split()
    if len(parts) >= 4:
        ip_addr = parts[0]
        mac = None
        for i, p in enumerate(parts):
            if p == "lladdr" and i + 1 < len(parts):
                mac = parts[i + 1].lower()
                break
        if mac and '.' in ip_addr:
            mac_to_ipv4[mac] = ip_addr

def eui64_to_mac(ipv6):
    """Derive MAC address from EUI-64 IPv6 link-local address."""
    try:
        import ipaddress
        addr = ipaddress.IPv6Address(ipv6)
    except (ValueError, Exception):
        return None
    if not ipv6.startswith('fe80'):
        return None
    iid = int(addr) & 0xFFFFFFFFFFFFFFFF
    iid_bytes = iid.to_bytes(8, 'big')
    if iid_bytes[3] != 0xff or iid_bytes[4] != 0xfe:
        return None
    mac_bytes = [
        iid_bytes[0] ^ 0x02,
        iid_bytes[1],
        iid_bytes[2],
        iid_bytes[5],
        iid_bytes[6],
        iid_bytes[7],
    ]
    return ':'.join(f'{b:02x}' for b in mac_bytes)

def resolve_neighbor_ip(ip):
    """Resolve IPv6 link-local to IPv4 via EUI-64 MAC derivation and ARP lookup."""
    if '.' in ip:
        return ip
    mac = eui64_to_mac(ip)
    if mac and mac in mac_to_ipv4:
        return mac_to_ipv4[mac]
    return ip

# Parse BMX7 neighbor links
# BMX7 links output has a header row with column names. Detect columns from header.
bmx7_raw = extract_block("__BMX7_START__", "__BMX7_END__", lines)
neighbors = []
bmx7_lines = bmx7_raw.splitlines()

# Detect column indices from header
link_col_nbLocalIp = None
link_col_dev = None
link_col_shortId = None
link_header_found = False
for line in bmx7_lines:
    line = line.strip()
    if not line:
        continue
    tokens_lower = line.lower().split()
    if 'nblocalip' in tokens_lower:
        link_col_nbLocalIp = tokens_lower.index('nblocalip')
        link_col_dev = tokens_lower.index('dev') if 'dev' in tokens_lower else None
        link_col_shortId = tokens_lower.index('shortid') if 'shortid' in tokens_lower else None
        link_header_found = True
        break

if link_header_found and link_col_nbLocalIp is not None:
    for line in bmx7_lines:
        line = line.strip()
        if not line or line.lower().startswith('link') or line.lower().startswith('shortid'):
            continue
        tokens = line.split()
        if len(tokens) <= link_col_nbLocalIp:
            continue
        raw_ip = tokens[link_col_nbLocalIp]
        iface_name = tokens[link_col_dev] if link_col_dev is not None and len(tokens) > link_col_dev else None
        resolved_ip = resolve_neighbor_ip(raw_ip)
        neighbors.append({
            "protocol": "bmx7",
            "ip": resolved_ip,
            "interface": iface_name,
            "metric": None,
        })
else:
    # Old-style fallback: first token is IP
    for line in bmx7_lines:
        tokens = line.strip().split()
        if len(tokens) >= 3 and ("." in tokens[0] or ":" in tokens[0]):
            raw_ip = tokens[0]
            iface_name = tokens[1] if len(tokens) > 1 else None
            resolved_ip = resolve_neighbor_ip(raw_ip)
            neighbors.append({
                "protocol": "bmx7",
                "ip": resolved_ip,
                "interface": iface_name,
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
