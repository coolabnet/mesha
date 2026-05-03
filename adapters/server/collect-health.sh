#!/usr/bin/env sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# adapters/server/collect-health.sh
#
# Usage:
#   ./collect-health.sh
#
# Description:
#   Collects local host health metrics and outputs normalized JSON to stdout.
#   Runs locally on the server — no SSH required. Safe to run without root
#   (uses standard unprivileged commands only).
#
#   Collects:
#     - hostname and system identity
#     - uptime and load averages
#     - memory usage (total, used, free, cached)
#     - disk usage per mount point
#     - running Docker containers (if Docker is available)
#
# Output schema:
#   {
#     "collected_at": "<ISO8601>",
#     "hostname": "<string>",
#     "uptime_seconds": <int>,
#     "uptime_human": "<string>",
#     "load_average": { "1m": <float>, "5m": <float>, "15m": <float> },
#     "memory": {
#       "total_kb": <int>, "used_kb": <int>, "free_kb": <int>,
#       "available_kb": <int>, "cached_kb": <int>, "buffers_kb": <int>
#     },
#     "disk": [
#       { "mount": "<string>", "device": "<string>", "total_kb": <int>,
#         "used_kb": <int>, "free_kb": <int>, "use_pct": <int> }
#     ],
#     "docker": {
#       "available": true|false,
#       "containers": [
#         { "id": "<string>", "name": "<string>", "image": "<string>",
#           "status": "<string>", "running": true|false }
#       ]
#     }
#   }
#
# Risk class: A (read-only)
# Dependencies: python3 (stdlib), df, free, uptime (all standard on Linux)
#               docker (optional — handled gracefully if missing)

set -e

COLLECTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ---------------------------------------------------------------------------
# Collect: hostname
# ---------------------------------------------------------------------------
HOSTNAME_VAL="$(hostname -s 2>/dev/null || cat /proc/sys/kernel/hostname)"

# ---------------------------------------------------------------------------
# Collect: uptime and load averages
# /proc/uptime: "<uptime_seconds> <idle_seconds>"
# /proc/loadavg: "<1m> <5m> <15m> <running/total> <last_pid>"
# ---------------------------------------------------------------------------
UPTIME_SECS="$(awk '{printf "%d", $1}' /proc/uptime)"
LOAD_1M="$(awk '{print $1}' /proc/loadavg)"
LOAD_5M="$(awk '{print $2}' /proc/loadavg)"
LOAD_15M="$(awk '{print $3}' /proc/loadavg)"

# Human-readable uptime
UPTIME_HUMAN="$(awk -v s="$UPTIME_SECS" 'BEGIN{
    d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); sec=s%60;
    printf "%dd %dh %dm %ds", d, h, m, sec
}')"

# ---------------------------------------------------------------------------
# Collect: memory usage
# `free -k` outputs in kilobytes. We parse the "Mem:" line.
# Format: Mem: total used free shared buff/cache available
# ---------------------------------------------------------------------------
MEM_LINE="$(free -k | awk '/^Mem:/{print}')"
MEM_TOTAL="$(echo "$MEM_LINE" | awk '{print $2}')"
MEM_USED="$(echo "$MEM_LINE" | awk '{print $3}')"
MEM_FREE="$(echo "$MEM_LINE" | awk '{print $4}')"
MEM_AVAILABLE="$(echo "$MEM_LINE" | awk '{print $7}')"
# Modern `free -k` combines buffers+cache in column 6 (buff/cache).
# Read separately from /proc/meminfo for accuracy.
MEM_BUFFERS="$(awk '/^Buffers:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_CACHED="$(awk '/^Cached:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"

# ---------------------------------------------------------------------------
# Collect: disk usage
# `df -Pk` outputs POSIX format in kilobytes. We skip tmpfs, devtmpfs,
# squashfs, and overlayfs since we only care about persistent storage mounts.
# ---------------------------------------------------------------------------
DISK_JSON="$(df -Pk 2>/dev/null |
  awk 'NR>1 && $1 !~ /^(tmpfs|devtmpfs|squashfs|overlay|udev|none|cgroup)/ {
        gsub(/%/,"",$5);
        printf "{\"device\":\"%s\",\"total_kb\":%s,\"used_kb\":%s,\"free_kb\":%s,\"use_pct\":%s,\"mount\":\"%s\"}\n",
               $1, $2, $3, $4, $5, $6
    }' |
  python3 -c "
import sys, json
rows = []
for line in sys.stdin:
    line = line.strip()
    if line:
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            pass
print(json.dumps(rows))
")"

# ---------------------------------------------------------------------------
# Collect: Docker containers
# We attempt `docker ps -a` with JSON format. If Docker is not installed
# or the user cannot access the socket, we record docker.available=false.
# ---------------------------------------------------------------------------
DOCKER_AVAILABLE="false"
DOCKER_JSON="[]"

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    DOCKER_AVAILABLE="true"
    DOCKER_JSON="$(docker ps -a --format '{{json .}}' 2>/dev/null |
      python3 -c "
import sys, json
containers = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        c = json.loads(line)
        running = 'up' in c.get('Status', '').lower() or c.get('State', '').lower() == 'running'
        containers.append({
            'id': c.get('ID', c.get('Id', ''))[:12],
            'name': c.get('Names', '').lstrip('/'),
            'image': c.get('Image', ''),
            'status': c.get('Status', c.get('State', '')),
            'running': running,
        })
    except json.JSONDecodeError:
        pass
print(json.dumps(containers))
" 2>/dev/null || echo "[]")"
  fi
fi

# ---------------------------------------------------------------------------
# Assemble final JSON output with Python 3
# ---------------------------------------------------------------------------
python3 - <<PYEOF
import json

# Convert shell boolean strings to Python booleans
docker_available = "${DOCKER_AVAILABLE}" == "true"

# Parse JSON strings that were created in the shell
disk_data = json.loads("""${DISK_JSON}""")
docker_containers = json.loads("""${DOCKER_JSON}""")

result = {
    "collected_at": "${COLLECTED_AT}",
    "hostname": "${HOSTNAME_VAL}",
    "uptime_seconds": int("${UPTIME_SECS}") if "${UPTIME_SECS}".isdigit() else 0,
    "uptime_human": "${UPTIME_HUMAN}",
    "load_average": {
        "1m": float("${LOAD_1M}"),
        "5m": float("${LOAD_5M}"),
        "15m": float("${LOAD_15M}"),
    },
    "memory": {
        "total_kb": int("${MEM_TOTAL}") if "${MEM_TOTAL}".isdigit() else 0,
        "used_kb": int("${MEM_USED}") if "${MEM_USED}".isdigit() else 0,
        "free_kb": int("${MEM_FREE}") if "${MEM_FREE}".isdigit() else 0,
        "available_kb": int("${MEM_AVAILABLE}") if "${MEM_AVAILABLE}".isdigit() else 0,
        "cached_kb": int("${MEM_CACHED}") if "${MEM_CACHED}".isdigit() else 0,
        "buffers_kb": int("${MEM_BUFFERS}") if "${MEM_BUFFERS}".isdigit() else 0,
    },
    "disk": disk_data,
    "docker": {
        "available": docker_available,
        "containers": docker_containers,
    },
}

print(json.dumps(result, indent=2))
PYEOF
