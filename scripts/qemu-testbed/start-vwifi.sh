#!/usr/bin/env bash
# Compiles and launches vwifi-server from https://github.com/Raizo62/vwifi
# TCP mode with -u flag (use-port-in-hash for multi-VM)
# Server binds INADDR_ANY by default — no bind-address flag needed
# PID tracked in testbed/run/vwifi-server.pid

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VWIFI_DIR="${REPO_ROOT}/testbed/bin"
VWIFI_SRC="${REPO_ROOT}/testbed/src/vwifi"
PID_FILE="${REPO_ROOT}/testbed/run/vwifi-server.pid"
VWIFI_PORT="${VWIFI_PORT:-8212}"  # TCP primary port

mkdir -p "${VWIFI_DIR}" "${REPO_ROOT}/testbed/run"

# Check if already running
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "vwifi-server already running (PID $(cat "$PID_FILE"))"
    exit 0
fi

# Compile if needed
if [ ! -x "${VWIFI_DIR}/vwifi-server" ]; then
    echo "Compiling vwifi-server..."
    if [ ! -d "${VWIFI_SRC}" ]; then
        git clone https://github.com/Raizo62/vwifi.git "${VWIFI_SRC}"
    fi
    cd "${VWIFI_SRC}"
    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j"$(nproc)"
    cp vwifi-server "${VWIFI_DIR}/vwifi-server"
    cp vwifi-ctrl "${VWIFI_DIR}/vwifi-ctrl" 2>/dev/null || true
fi

# Launch
echo "Starting vwifi-server (TCP mode, port ${VWIFI_PORT})..."
"${VWIFI_DIR}/vwifi-server" -u -t "${VWIFI_PORT}" &
VWIFI_PID=$!
echo "$VWIFI_PID" > "$PID_FILE"

# Wait for readiness
sleep 1
if kill -0 "$VWIFI_PID" 2>/dev/null; then
    echo "vwifi-server started (PID $VWIFI_PID)"
else
    echo "ERROR: vwifi-server failed to start"
    rm -f "$PID_FILE"
    exit 1
fi
