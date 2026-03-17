#!/usr/bin/env bash
# adapters/server/collect-services.sh
#
# Usage:
#   ./collect-services.sh [--inventory PATH]
#
# Description:
#   Checks the health of each service listed in inventories/local-services.yaml
#   and outputs a normalized JSON array to stdout. Each service is checked
#   independently — one failure does not stop others.
#
#   For each service, the check strategy is:
#     1. If a local_domain and port are set: attempt an HTTP GET to the
#        service's health endpoint (or root path) and measure response time.
#     2. If a container name is set: check Docker container status.
#     3. If neither is available: mark status as "unknown".
#
#   The inventory file path defaults to "inventories/local-services.yaml"
#   relative to the workspace root. Override with --inventory <path>.
#
# Output schema (array of service check results):
#   [
#     {
#       "name": "<string>",
#       "host": "<string>",
#       "container": "<string or null>",
#       "local_domain": "<string or null>",
#       "port": <int or null>,
#       "status": "up" | "down" | "degraded" | "unknown",
#       "last_checked": "<ISO8601>",
#       "response_time_ms": <int or null>,
#       "check_method": "http" | "docker" | "none",
#       "detail": "<string — human-readable status detail>"
#     }
#   ]
#
# Risk class: A (read-only — only GETs and docker inspect, no writes)
# Dependencies: python3, pyyaml (python3-yaml), curl (for HTTP checks),
#               docker (optional)

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
INVENTORY_FILE="inventories/local-services.yaml"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --inventory)
            INVENTORY_FILE="$2"
            shift 2
            ;;
        -h|--help)
            head -30 "$0" | grep '^#' | cut -c3-
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve inventory path: support relative (from workspace root) or absolute
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "$INVENTORY_FILE" != /* ]]; then
    INVENTORY_FILE="${WORKSPACE_ROOT}/${INVENTORY_FILE}"
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
    python3 -c "
import json
print(json.dumps([{'name': 'error', 'status': 'unknown', 'detail': 'Inventory file not found: $INVENTORY_FILE', 'last_checked': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'}], indent=2))
"
    exit 0
fi

# ---------------------------------------------------------------------------
# Check if PyYAML is available
# ---------------------------------------------------------------------------
if ! python3 -c "import yaml" 2>/dev/null; then
    echo "Error: python3-yaml is required. Install with: pip install pyyaml" >&2
    echo "  or: apt install python3-yaml" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# HTTP health check helper
# Uses curl with a timeout to attempt a GET request.
# Returns: HTTP status code and response time in milliseconds.
# We try /health first (common health endpoint), then fall back to root /.
# ---------------------------------------------------------------------------
http_check() {
    local url="$1"
    local timeout_sec=5

    # curl writes response code and timing to stdout, errors to /dev/null
    curl -s -o /dev/null \
        --max-time "$timeout_sec" \
        --write-out "%{http_code} %{time_total}" \
        "$url" 2>/dev/null || echo "000 0"
}

# ---------------------------------------------------------------------------
# Docker container status helper
# Returns "running", "exited", "paused", or "not_found"
# ---------------------------------------------------------------------------
docker_status() {
    local container_name="$1"
    if ! command -v docker &>/dev/null; then
        echo "docker_unavailable"
        return
    fi
    if ! docker info &>/dev/null; then
        echo "docker_unavailable"
        return
    fi
    local status
    status="$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "not_found")"
    echo "$status"
}

# ---------------------------------------------------------------------------
# Main: load inventory and check each service with Python 3 orchestration
# ---------------------------------------------------------------------------
python3 - <<PYEOF
import json
import subprocess
import time
import os
import sys
from datetime import datetime, timezone

try:
    import yaml
except ImportError:
    print(json.dumps([{"name": "error", "status": "unknown",
                       "detail": "PyYAML not available", "last_checked": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}], indent=2))
    sys.exit(0)

INVENTORY_FILE = "${INVENTORY_FILE}"
HTTP_TIMEOUT = 5
HTTP_HEALTH_PATHS = ["/health", "/api/health", "/status", "/"]

def utcnow():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def http_check(url):
    """Attempt HTTP GET; return (http_code, response_ms) or (0, None) on failure."""
    try:
        result = subprocess.run(
            ["curl", "-s", "-o", "/dev/null",
             "--max-time", str(HTTP_TIMEOUT),
             "--write-out", "%{http_code} %{time_total}",
             url],
            capture_output=True, text=True, timeout=HTTP_TIMEOUT + 2
        )
        parts = result.stdout.strip().split()
        http_code = int(parts[0]) if parts else 0
        time_total = float(parts[1]) if len(parts) > 1 else 0.0
        return http_code, int(time_total * 1000)
    except (subprocess.TimeoutExpired, subprocess.SubprocessError, ValueError, IndexError):
        return 0, None

def docker_check(container_name):
    """Check Docker container state. Returns (state_str, available_bool)."""
    try:
        # Check if docker command exists and daemon is responsive
        result = subprocess.run(["docker", "info"], capture_output=True, timeout=5)
        if result.returncode != 0:
            return "docker_unavailable", False
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return "docker_unavailable", False

    try:
        result = subprocess.run(
            ["docker", "inspect", "--format={{.State.Status}}", container_name],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip(), True
        return "not_found", True
    except (subprocess.TimeoutExpired, subprocess.SubprocessError):
        return "error", True

def check_service(svc):
    name = svc.get("name", "unknown")
    host = svc.get("host", "")
    container = svc.get("container")
    local_domain = svc.get("local_domain")
    port = svc.get("port")

    checked_at = utcnow()
    status = "unknown"
    response_ms = None
    check_method = "none"
    detail = "No check method available"

    # --- Strategy 1: HTTP check via local_domain ---
    if local_domain and port:
        check_method = "http"
        base_url = f"http://{local_domain}:{port}"

        for path in HTTP_HEALTH_PATHS:
            url = base_url + path
            code, ms = http_check(url)
            if code > 0:
                response_ms = ms
                if 200 <= code < 400:
                    status = "up"
                    detail = f"HTTP {code} on {url} ({ms}ms)"
                elif code >= 500:
                    status = "degraded"
                    detail = f"HTTP {code} server error on {url}"
                else:
                    status = "degraded"
                    detail = f"HTTP {code} unexpected response on {url}"
                break
        else:
            # All paths failed
            status = "down"
            detail = f"No HTTP response from {base_url} (timeout={HTTP_TIMEOUT}s)"

    # --- Strategy 2: Docker check (fallback or supplement) ---
    elif container:
        check_method = "docker"
        state, docker_available = docker_check(container)

        if not docker_available:
            status = "unknown"
            detail = "Docker not available on this host"
        elif state == "running":
            status = "up"
            detail = f"Container '{container}' is running"
        elif state == "exited":
            status = "down"
            detail = f"Container '{container}' has exited"
        elif state == "paused":
            status = "degraded"
            detail = f"Container '{container}' is paused"
        elif state == "not_found":
            status = "down"
            detail = f"Container '{container}' not found"
        elif state == "docker_unavailable":
            status = "unknown"
            detail = "Docker daemon not accessible"
        else:
            status = "unknown"
            detail = f"Container '{container}' state: {state}"

    return {
        "name": name,
        "host": host,
        "container": container,
        "local_domain": local_domain,
        "port": port,
        "status": status,
        "last_checked": checked_at,
        "response_time_ms": response_ms,
        "check_method": check_method,
        "detail": detail,
    }

# Load inventory
try:
    with open(INVENTORY_FILE, "r") as fh:
        data = yaml.safe_load(fh)
except Exception as exc:
    print(json.dumps([{
        "name": "error", "status": "unknown",
        "detail": f"Failed to load inventory: {exc}",
        "last_checked": utcnow()
    }], indent=2))
    sys.exit(0)

services = data.get("services", [])
if not services:
    print(json.dumps([], indent=2))
    sys.exit(0)

# Check each service independently — errors in one do not stop others
results = []
for svc in services:
    try:
        result = check_service(svc)
    except Exception as exc:
        result = {
            "name": svc.get("name", "unknown"),
            "host": svc.get("host", ""),
            "container": svc.get("container"),
            "local_domain": svc.get("local_domain"),
            "port": svc.get("port"),
            "status": "unknown",
            "last_checked": utcnow(),
            "response_time_ms": None,
            "check_method": "none",
            "detail": f"Check failed with exception: {exc}",
        }
    results.append(result)

print(json.dumps(results, indent=2))
PYEOF
