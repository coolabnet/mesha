#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# adapters/mesh/collect-topology.sh
#
# Usage:
#   ./collect-topology.sh <gateway-ip>
#
# Description:
#   Connects to a LibreMesh gateway node via SSH and collects the BMX7 (or
#   Babel) neighbor/routing table to produce a normalized JSON topology
#   snapshot. This snapshot represents the mesh as seen from the gateway's
#   perspective at the time of collection.
#
#   The gateway is the entry point because it typically has the most complete
#   view of the mesh (it sees all routes to all reachable nodes). For a more
#   complete topology, run this against multiple gateways and merge results.
#
# Output schema:
#   {
#     "collected_at": "<ISO8601 timestamp>",
#     "gateway_ip": "<ip>",
#     "reachable": true|false,
#     "error": "<message or null>",
#     "node_count": <int>,
#     "nodes": [
#       {
#         "ip": "<string>",
#         "hostname": "<string or null>",
#         "metric": "<float or null>",
#         "hops": <int or null>,
#         "peers": [
#           { "peer_ip": "<string>", "interface": "<string>", "rx_rate": <int>, "tx_rate": <int>, "signal_dbm": <int or null> }
#         ]
#       }
#     ],
#     "links": [
#       { "from_ip": "<string>", "to_ip": "<string>", "interface": "<string>", "metric": "<float or null>", "signal_dbm": <int or null> }
#     ]
#   }
#
# Risk class: A (read-only — no writes performed on the node)
# Credentials: SSH key auth via ssh-agent or secrets/ convention
#
# Dependencies: ssh, python3 (stdlib only, for JSON construction)

set -e # reason: originally POSIX sh; now bash, kept for error-on-fail behavior

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [ $# -ne 1 ]; then
  echo "Usage: $0 <gateway-ip>" >&2
  exit 1
fi

GATEWAY_IP="$1"
COLLECTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SSH_TIMEOUT=15
SSH_OPTS="-o ConnectTimeout=${SSH_TIMEOUT} -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR"

# ---------------------------------------------------------------------------
# Helper: emit error JSON and exit 0
# Always output valid JSON so the caller can parse the response regardless
# of whether the gateway was reachable.
# ---------------------------------------------------------------------------
emit_error() {
  local msg="$1"
  python3 -c "
import json, sys
print(json.dumps({
    'collected_at': '${COLLECTED_AT}',
    'gateway_ip': '${GATEWAY_IP}',
    'gateway_hostname': None,
    'reachable': False,
    'error': sys.argv[1],
    'node_count': 0,
    'nodes': [],
    'links': []
}, indent=2))
" "$msg"
  exit 0
}

# ---------------------------------------------------------------------------
# Connectivity check
# ---------------------------------------------------------------------------
if ! ssh $SSH_OPTS root@"$GATEWAY_IP" "true" 2>/dev/null; then
  emit_error "SSH connection to gateway ${GATEWAY_IP} failed (timeout=${SSH_TIMEOUT}s)"
fi

# ---------------------------------------------------------------------------
# Collect topology data from the gateway in a single SSH session
# ---------------------------------------------------------------------------
RAW_TOPO="$(
  ssh $SSH_OPTS root@"$GATEWAY_IP" sh -s <<'REMOTE_SCRIPT'

# --- BMX7 originators table ---
# `bmx7 -c --originators` lists all known mesh nodes (originators) with
# their IP, metric (route cost), hop count, and best-path information.
# This is the primary source for enumerating all reachable mesh nodes.
BMX7_ORIG="$(bmx7 -c --originators 2>/dev/null || echo '')"

# --- BMX7 links table ---
# `bmx7 -c --links` lists direct RF/link-layer peers of this node.
# Each entry includes the neighbor IP, the interface (radio), and
# link quality metrics (transmit/receive rates).
BMX7_LINKS="$(bmx7 -c --links 2>/dev/null || echo '')"

# --- BMX7 interfaces ---
# `bmx7 -c --interfaces` shows which local interfaces BMX7 is using.
BMX7_IFACES="$(bmx7 -c --interfaces 2>/dev/null || echo '')"

# --- Babeld neighbor dump (fallback if BMX7 not running) ---
# babeld exposes a local TCP control port on 33123 by default.
# `dump neighbours` returns active Babel neighbors with reachability info.
BABEL_DUMP="$(echo 'dump neighbours' | nc -q2 localhost 33123 2>/dev/null || echo '')"
BABEL_TABLE="$(echo 'dump routes' | nc -q2 localhost 33123 2>/dev/null || echo '')"

# --- ARP/neighbor table ---
# The ARP table gives us IP-to-MAC mappings for all nodes visible at L2/L3.
# Useful for correlating BMX7 IPs with MACs in the inventory.
ARP_TABLE="$(ip neigh show 2>/dev/null || arp -n 2>/dev/null || echo '')"

# --- Local hostname for reference ---
LOCAL_HOSTNAME="$(uci get system.@system[0].hostname 2>/dev/null || hostname)"

cat <<EOF
__LOCAL_HOSTNAME__${LOCAL_HOSTNAME}
__BMX7_ORIG_START__
${BMX7_ORIG}
__BMX7_ORIG_END__
__BMX7_LINKS_START__
${BMX7_LINKS}
__BMX7_LINKS_END__
__BABEL_DUMP_START__
${BABEL_DUMP}
__BABEL_DUMP_END__
__BABEL_TABLE_START__
${BABEL_TABLE}
__BABEL_TABLE_END__
__ARP_START__
${ARP_TABLE}
__ARP_END__
EOF
REMOTE_SCRIPT
)"

# ---------------------------------------------------------------------------
# Parse and normalize topology data with Python 3
# ---------------------------------------------------------------------------
python3 - <<PYEOF
import json
import re

raw = """${RAW_TOPO}"""
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
    return [l for l in block if l.strip()]

gateway_hostname = extract_value("__LOCAL_HOSTNAME__", lines) or "unknown"

# --- Parse BMX7 originators ---
# BMX7 originator lines look like (version-dependent):
#   <ip>  <metric>  <hops>  <best-link-interface>  ...
orig_lines = extract_block("__BMX7_ORIG_START__", "__BMX7_ORIG_END__", lines)
nodes = {}
for line in orig_lines:
    line = line.strip()
    if not line or line.startswith('#') or line.lower().startswith('id') or line.lower().startswith('orig'):
        continue
    tokens = line.split()
    if len(tokens) >= 2:
        ip = tokens[0]
        metric = tokens[1] if len(tokens) > 1 else None
        hops = tokens[2] if len(tokens) > 2 else None
        try:
            hops = int(hops) if hops else None
        except ValueError:
            hops = None
        try:
            metric = float(metric) if metric else None
        except ValueError:
            metric = None
        if re.match(r'\d+\.\d+\.\d+\.\d+', ip):
            nodes[ip] = {
                "ip": ip,
                "hostname": None,
                "metric": metric,
                "hops": hops,
                "peers": []
            }

# --- Parse BMX7 links ---
# BMX7 link lines look like:
#   <neighbor-ip>  <interface>  <rx-rate>  <tx-rate>  ...
link_lines = extract_block("__BMX7_LINKS_START__", "__BMX7_LINKS_END__", lines)
links = []
for line in link_lines:
    line = line.strip()
    if not line or line.startswith('#') or line.lower().startswith('id') or line.lower().startswith('link'):
        continue
    tokens = line.split()
    if len(tokens) >= 2 and re.match(r'\d+\.\d+\.\d+\.\d+', tokens[0]):
        peer_ip = tokens[0]
        interface = tokens[1] if len(tokens) > 1 else None
        rx_rate = None
        tx_rate = None
        if len(tokens) >= 4:
            try:
                rx_rate = int(tokens[2])
                tx_rate = int(tokens[3])
            except ValueError:
                pass
        link_entry = {
            "from_ip": "${GATEWAY_IP}",
            "to_ip": peer_ip,
            "interface": interface,
            "metric": None,
            "signal_dbm": None,
        }
        links.append(link_entry)
        # Also add peer info to the node if known
        if peer_ip in nodes:
            nodes[peer_ip]["peers"].append({
                "peer_ip": "${GATEWAY_IP}",
                "interface": interface,
                "rx_rate": rx_rate,
                "tx_rate": tx_rate,
                "signal_dbm": None,
            })

# --- Babel fallback: parse neighbour dump ---
if not nodes:
    babel_lines = extract_block("__BABEL_DUMP_START__", "__BABEL_DUMP_END__", lines)
    for line in babel_lines:
        line = line.strip()
        tokens = line.split()
        ip = None
        for t in tokens:
            if re.match(r'\d+\.\d+\.\d+\.\d+', t) or re.match(r'[0-9a-f:]+::', t):
                ip = t
                break
        if ip:
            nodes[ip] = {
                "ip": ip,
                "hostname": None,
                "metric": None,
                "hops": None,
                "peers": []
            }
            links.append({
                "from_ip": "${GATEWAY_IP}",
                "to_ip": ip,
                "interface": None,
                "metric": None,
                "signal_dbm": None,
            })

# Add the gateway itself as a node
nodes["${GATEWAY_IP}"] = {
    "ip": "${GATEWAY_IP}",
    "hostname": gateway_hostname,
    "metric": 0,
    "hops": 0,
    "peers": []
}

node_list = list(nodes.values())

result = {
    "collected_at": "${COLLECTED_AT}",
    "gateway_ip": "${GATEWAY_IP}",
    "gateway_hostname": gateway_hostname,
    "reachable": True,
    "error": None,
    "node_count": len(node_list),
    "nodes": node_list,
    "links": links,
}

print(json.dumps(result, indent=2))
PYEOF
