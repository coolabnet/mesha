#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
set -euo pipefail

# ---------------------------------------------------------------------------
# Jellyfin install recipe
# Community Infrastructure Operator — server-services skill
#
# Idempotent: safe to run multiple times. Will skip steps already done.
# Local domain: midia.bairro.local (port 8096 behind reverse proxy)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
SERVICE_NAME="jellyfin"
LOCAL_DOMAIN="midia.bairro.local"
HEALTH_URL="http://localhost:8096/health" # polled via docker exec inside the container
STARTUP_WAIT=15

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [jellyfin] $*"; }
fail() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [jellyfin] ERROR: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Step 1 — Prerequisites check
# ---------------------------------------------------------------------------
log "Step 1: Checking prerequisites..."

if ! command -v docker &>/dev/null; then
  fail "docker is not installed or not in PATH. Install Docker before running this recipe."
fi

if ! docker compose version &>/dev/null; then
  fail "docker compose plugin is not available. Install the Docker Compose plugin (v2) before continuing."
fi

if ! docker info &>/dev/null; then
  fail "Docker daemon is not running or current user cannot connect to it. Check 'sudo systemctl status docker'."
fi

log "Prerequisites OK."

# ---------------------------------------------------------------------------
# Step 2 — Ensure .env file exists
# ---------------------------------------------------------------------------
log "Step 2: Checking .env file..."

cd "${SCRIPT_DIR}"

if [[ ! -f ".env" ]]; then
  if [[ -f ".env.example" ]]; then
    log ".env not found — copying from .env.example."
    cp .env.example .env
    log ".env created. Review paths in .env and re-run if the defaults are not suitable."
  else
    fail ".env file is missing and no .env.example found. Cannot continue."
  fi
fi

log ".env file found."

# Load .env
set -o allexport
# shellcheck source=/dev/null
source <(grep -v '^\s*#' .env | grep -v '^\s*$')
set +o allexport

# ---------------------------------------------------------------------------
# Step 3 — Create required data directories
# ---------------------------------------------------------------------------
log "Step 3: Creating data directories..."

JELLYFIN_DATA_PATH="${JELLYFIN_DATA_PATH:-./data/jellyfin/config}"
JELLYFIN_CACHE_PATH="${JELLYFIN_CACHE_PATH:-./data/jellyfin/cache}"
JELLYFIN_MEDIA_PATH="${JELLYFIN_MEDIA_PATH:-./data/media}"

mkdir -p "${JELLYFIN_DATA_PATH}"
mkdir -p "${JELLYFIN_CACHE_PATH}"
mkdir -p "${JELLYFIN_MEDIA_PATH}"

log "Data directories ready:"
log "  config : ${JELLYFIN_DATA_PATH}"
log "  cache  : ${JELLYFIN_CACHE_PATH}"
log "  media  : ${JELLYFIN_MEDIA_PATH}"

# ---------------------------------------------------------------------------
# Step 4 — Pull image and start service
# ---------------------------------------------------------------------------
log "Step 4: Pulling Docker image..."

docker compose pull

log "Step 5: Starting Jellyfin with docker compose up -d..."

docker compose up -d

log "Container started."

# ---------------------------------------------------------------------------
# Step 5 — Wait for startup
# ---------------------------------------------------------------------------
log "Step 5: Waiting ${STARTUP_WAIT}s for Jellyfin to initialize..."

sleep "${STARTUP_WAIT}"

# Poll health endpoint for up to 60s additional
HEALTH_TIMEOUT=60
ELAPSED=0
INTERVAL=5
HEALTHY=false

while [[ $ELAPSED -lt $HEALTH_TIMEOUT ]]; do
  HTTP_STATUS=$(docker exec jellyfin curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" 2>/dev/null || true)
  if [[ $HTTP_STATUS == "200" ]]; then
    HEALTHY=true
    break
  fi
  log "  ...not ready yet (HTTP ${HTTP_STATUS:-no response}), waiting ${INTERVAL}s..."
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $HEALTHY != "true" ]]; then
  fail "Jellyfin did not respond at ${HEALTH_URL} within the timeout. Check logs: docker compose logs jellyfin"
fi

log "Jellyfin is responding."

# ---------------------------------------------------------------------------
# Step 6 — Print access information
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Jellyfin installed successfully"
echo "============================================================"
echo ""
echo "  Local domain : http://${LOCAL_DOMAIN}"
echo "  Health check : ${HEALTH_URL} (internal — via docker exec)"
echo ""
echo "  Reverse proxy entry (desired-state/server/reverse-proxy.yaml):"
echo "    domain  : ${LOCAL_DOMAIN}"
echo "    backend : jellyfin:8096"
echo "    health  : /health"
echo "    note    : websocket passthrough required for playback"
echo ""

# ---------------------------------------------------------------------------
# Step 7 — User onboarding note
# ---------------------------------------------------------------------------
echo "  FIRST-RUN SETUP"
echo "  ---------------"
echo "  Jellyfin does NOT create an admin account automatically."
echo "  You must complete first-run setup in the web UI:"
echo ""
echo "  1. Open http://${LOCAL_DOMAIN} from a browser on the local mesh network."
echo "  2. The setup wizard will appear — create the admin username and password."
echo "  3. Add your media library: point Jellyfin to /media (the container path)."
echo "     The host path is: ${JELLYFIN_MEDIA_PATH}"
echo "  4. Wait for the library scan to complete before sharing with users."
echo ""
echo "  CONTENT NOTE"
echo "  ------------"
echo "  - This service is open to all mesh users (no login required by default)."
echo "  - Only add educational or community-approved content."
echo "  - If personal content is added in the future, enable authentication"
echo "    in the Jellyfin admin panel and update service-catalog.yaml."
echo ""
echo "  ROLLBACK"
echo "  --------"
echo "  - To remove: docker compose down  (data directories preserved)"
echo "  - To wipe all data: docker compose down && rm -rf ./data/jellyfin"
echo "============================================================"
