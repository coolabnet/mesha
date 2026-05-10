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
# Raw data is written to a temp file to avoid unsafe string interpolation
# into Python code (the data may contain arbitrary content from nodes).
# ---------------------------------------------------------------------------
RAW_FILE=$(mktemp "${TMPDIR:-/tmp}/mesh-topo-XXXXXX")
printf '%s' "${RAW_TOPO}" > "${RAW_FILE}"
trap 'rm -f "${RAW_FILE}"' EXIT

python3 - <<PYEOF
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
    return [l for l in block if l.strip()]

gateway_hostname = extract_value("__LOCAL_HOSTNAME__", lines) or "unknown"

# --- Parse ARP/neighbor table for IPv6->IPv4 resolution ---
# ARP entries look like:
#   10.99.0.12 dev br-lan lladdr 52:54:00:00:00:02 REACHABLE
#   fe80::5054:ff:fe00:2 dev br-lan lladdr 52:54:00:00:00:02 REACHABLE
# We build MAC->IPv4 map, then derive MAC from BMX7 IPv6 via EUI-64 if needed.
arp_lines = extract_block("__ARP_START__", "__ARP_END__", lines)
mac_to_ipv4 = {}
for line in arp_lines:
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
    """Derive MAC address from EUI-64 IPv6 link-local address.
    fe80::5054:ff:fe00:2 -> 52:54:00:00:00:02
    """
    try:
        import ipaddress
        addr = ipaddress.IPv6Address(ipv6)
    except (ValueError, Exception):
        return None
    if not ipv6.lower().startswith('fe80'):
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

def resolve_ip(ip):
    """Resolve an IP to IPv4 if possible (handles IPv6 link-local via MAC lookup)."""
    if '.' in ip:
        return ip  # Already IPv4
    # Try deriving MAC from EUI-64 and looking up IPv4
    mac = eui64_to_mac(ip)
    if mac and mac in mac_to_ipv4:
        return mac_to_ipv4[mac]
    return ip

def is_mesh_ip(ip):
    """Check if IP looks like an IPv4 or IPv6 link-local address."""
    return bool(re.match(r'\d+\.\d+\.\d+\.\d+', ip) or re.match(r'fe80::', ip, re.IGNORECASE) or re.match(r'fe80:[0-9a-fA-F:]+', ip, re.IGNORECASE))

# --- Parse BMX7 links FIRST (to build shortId→IPv4 map for originators) ---
# BMX7 links output is a table with header. Typical columns:
# shortId name linkKey linkKeys nbLocalIp dev rts rq tq txRate ...
link_lines = extract_block("__BMX7_LINKS_START__", "__BMX7_LINKS_END__", lines)

# Detect column indices from header
link_col_nbLocalIp = None
link_col_dev = None
link_col_txRate = None
link_col_shortId = None
link_header_found = False
for line in link_lines:
    line = line.strip()
    if not line:
        continue
    tokens_lower = line.lower().split()
    if 'nblocalip' in tokens_lower:
        link_col_nbLocalIp = tokens_lower.index('nblocalip')
        link_col_dev = tokens_lower.index('dev') if 'dev' in tokens_lower else None
        link_col_txRate = tokens_lower.index('txrate') if 'txrate' in tokens_lower else None
        link_col_shortId = tokens_lower.index('shortid') if 'shortid' in tokens_lower else None
        link_header_found = True
        break

links = []
shortid_to_ipv4 = {}  # Map shortId to resolved IPv4 for originators

if link_header_found and link_col_nbLocalIp is not None:
    # Store the actual header line so we skip it reliably regardless of
    # which column appears first (nbLocalIp, shortId, link, etc.)
    link_header_line_lower = None
    for hl in link_lines:
        hl = hl.strip()
        if not hl:
            continue
        tokens_lower_hl = hl.lower().split()
        if 'nblocalip' in tokens_lower_hl:
            link_header_line_lower = hl.lower()
            break
    for line in link_lines:
        line = line.strip()
        if not line:
            continue
        if link_header_line_lower is not None and line.lower() == link_header_line_lower:
            continue
        tokens = line.split()
        if len(tokens) <= link_col_nbLocalIp:
            continue
        nb_local_ip = tokens[link_col_nbLocalIp]
        interface = tokens[link_col_dev] if link_col_dev is not None and len(tokens) > link_col_dev else None
        peer_short_id = tokens[link_col_shortId] if link_col_shortId is not None and len(tokens) > link_col_shortId else None

        # Resolve the neighbor IP via EUI-64 → MAC → ARP IPv4
        peer_ip = resolve_ip(nb_local_ip)

        # Build shortId → IPv4 map for originators resolution
        if peer_short_id and '.' in peer_ip:
            shortid_to_ipv4[peer_short_id] = peer_ip

        tx_rate = None
        if link_col_txRate is not None and len(tokens) > link_col_txRate:
            try:
                tx_val = tokens[link_col_txRate]
                if tx_val.upper().endswith('M'):
                    tx_rate = int(float(tx_val[:-1]))
                elif tx_val.upper().endswith('K'):
                    tx_rate = int(float(tx_val[:-1]) * 1000)
                elif tx_val != '-1':
                    tx_rate = int(float(tx_val))
            except ValueError:
                pass

        link_entry = {
            "from_ip": "${GATEWAY_IP}",
            "to_ip": peer_ip,
            "interface": interface,
            "metric": None,
            "signal_dbm": None,
            "rx_rate": None,
            "tx_rate": tx_rate,
        }
        links.append(link_entry)
else:
    # Old-style fallback: first token is IP
    for line in link_lines:
        line = line.strip()
        if not line or line.startswith('#') or line.lower().startswith('id') or line.lower().startswith('link'):
            continue
        tokens = line.split()
        if len(tokens) >= 2 and is_mesh_ip(tokens[0]):
            peer_ip = resolve_ip(tokens[0])
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
                "rx_rate": rx_rate,
                "tx_rate": tx_rate,
            }
            links.append(link_entry)

# --- Parse BMX7 originators (using shortId→IPv4 from links) ---
# BMX7 originators output is a table with header. Column positions vary by version.
# Typical columns: shortId name as S s T t descSqn lastDesc descSize cv revision primaryIp dev nbShortId nbName metric hops ogmSqn lastRef
orig_lines = extract_block("__BMX7_ORIG_START__", "__BMX7_ORIG_END__", lines)

# Detect column indices from header
orig_col_primaryIp = None
orig_col_dev = None
orig_col_metric = None
orig_col_hops = None
orig_col_shortId = None
orig_col_name = None
orig_header_found = False
for line in orig_lines:
    line = line.strip()
    if not line:
        continue
    tokens_lower = line.lower().split()
    if 'primaryip' in tokens_lower:
        orig_col_primaryIp = tokens_lower.index('primaryip')
        orig_col_dev = tokens_lower.index('dev') if 'dev' in tokens_lower else None
        orig_col_metric = tokens_lower.index('metric') if 'metric' in tokens_lower else None
        orig_col_hops = tokens_lower.index('hops') if 'hops' in tokens_lower else None
        orig_col_shortId = tokens_lower.index('shortid') if 'shortid' in tokens_lower else None
        orig_col_name = tokens_lower.index('name') if 'name' in tokens_lower else None
        orig_header_found = True
        break

nodes = {}

if orig_header_found and orig_col_primaryIp is not None:
    # Store the actual header line so we skip it reliably regardless of
    # which column appears first (shortId, originator, primaryIp, etc.)
    orig_header_line_lower = None
    for hl in orig_lines:
        hl = hl.strip()
        if not hl:
            continue
        tokens_lower_hl = hl.lower().split()
        if 'primaryip' in tokens_lower_hl:
            orig_header_line_lower = hl.lower()
            break
    for line in orig_lines:
        line = line.strip()
        if not line:
            continue
        if orig_header_line_lower is not None and line.lower() == orig_header_line_lower:
            continue
        tokens = line.split()
        if len(tokens) <= orig_col_primaryIp:
            continue
        primary_ip = tokens[orig_col_primaryIp]
        dev = tokens[orig_col_dev] if orig_col_dev is not None and len(tokens) > orig_col_dev else None
        metric_str = tokens[orig_col_metric] if orig_col_metric is not None and len(tokens) > orig_col_metric else None
        hops_str = tokens[orig_col_hops] if orig_col_hops is not None and len(tokens) > orig_col_hops else None
        short_id = tokens[orig_col_shortId] if orig_col_shortId is not None and len(tokens) > orig_col_shortId else None
        name = tokens[orig_col_name] if orig_col_name is not None and len(tokens) > orig_col_name else None

        metric = None
        if metric_str:
            try:
                if metric_str.upper().endswith('K'):
                    metric = float(metric_str[:-1]) * 1000
                elif metric_str.upper().endswith('M'):
                    metric = float(metric_str[:-1]) * 1000000
                elif metric_str.upper().endswith('G'):
                    metric = float(metric_str[:-1]) * 1000000000
                else:
                    metric = float(metric_str)
            except ValueError:
                pass
        hops = None
        if hops_str:
            try:
                hops = int(hops_str)
            except ValueError:
                pass

        # Resolve IP: try shortId→IPv4 from links first, then EUI-64
        node_ip = None
        if short_id and short_id in shortid_to_ipv4:
            node_ip = shortid_to_ipv4[short_id]
        else:
            resolved = resolve_ip(primary_ip)
            node_ip = resolved if '.' in resolved else primary_ip

        nodes[node_ip] = {
            "ip": node_ip,
            "hostname": name if name and name != "OpenWrt" else None,
            "metric": metric,
            "hops": hops,
            "peers": []
        }
else:
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
            if is_mesh_ip(ip):
                resolved = resolve_ip(ip)
                nodes[resolved] = {
                    "ip": resolved,
                    "hostname": None,
                    "metric": metric,
                    "hops": hops,
                    "peers": []
                }

# Now add peer info from links to nodes
for link in links:
    peer_ip = link["to_ip"]
    if peer_ip in nodes:
        nodes[peer_ip]["peers"].append({
            "peer_ip": "${GATEWAY_IP}",
            "interface": link["interface"],
            "rx_rate": link.get("rx_rate"),
            "tx_rate": link.get("tx_rate"),
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
