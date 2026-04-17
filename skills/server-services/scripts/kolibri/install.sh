#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
set -euo pipefail

# ---------------------------------------------------------------------------
# Kolibri install recipe
# Community Infrastructure Operator — server-services skill
#
# Idempotent: safe to run multiple times. Will skip steps already done.
# Local domain: aprendizado.bairro.local (port 8080 behind reverse proxy)
#
# NOTE: Kolibri runs database migrations on first boot and may take
# 60–120 seconds to become ready. This is expected behavior.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="kolibri"
LOCAL_DOMAIN="aprendizado.bairro.local"
HEALTH_URL="http://localhost:8080/api/public/v1/info/"  # polled via docker exec inside the container
HEALTH_TIMEOUT=120

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [kolibri] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [kolibri] ERROR: $*" >&2; exit 1; }

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
    log ".env created. Review KOLIBRI_FACILITY_NAME and KOLIBRI_DATA_PATH before continuing."
  else
    fail ".env file is missing and no .env.example found. Cannot continue."
  fi
fi

log ".env file found."

# Load .env
set -o allexport
# shellcheck disable=SC1091
source <(grep -v '^\s*#' .env | grep -v '^\s*$')
set +o allexport

# ---------------------------------------------------------------------------
# Step 3 — Create data directory
# ---------------------------------------------------------------------------
log "Step 3: Creating data directory..."

KOLIBRI_DATA_PATH="${KOLIBRI_DATA_PATH:-./data/kolibri}"
mkdir -p "${KOLIBRI_DATA_PATH}"

log "Data directory ready: ${KOLIBRI_DATA_PATH}"

# ---------------------------------------------------------------------------
# Step 4 — Pull image and start service
# ---------------------------------------------------------------------------
log "Step 4: Pulling Docker image..."

docker compose pull

log "Starting Kolibri with docker compose up -d..."

docker compose up -d

log "Container started."

# ---------------------------------------------------------------------------
# Step 5 — Wait for Kolibri to initialize
# ---------------------------------------------------------------------------
log "Step 5: Waiting for Kolibri to initialize (up to ${HEALTH_TIMEOUT}s)..."
log "  Kolibri runs database migrations on first boot — this takes 60–120 seconds."

ELAPSED=0
INTERVAL=10
HEALTHY=false

while [[ $ELAPSED -lt $HEALTH_TIMEOUT ]]; do
  HTTP_STATUS=$(docker exec kolibri curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" 2>/dev/null || true)
  if [[ "$HTTP_STATUS" == "200" ]]; then
    HEALTHY=true
    break
  fi
  log "  ...not ready yet (HTTP ${HTTP_STATUS:-no response}), waiting ${INTERVAL}s... (${ELAPSED}/${HEALTH_TIMEOUT}s elapsed)"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ "$HEALTHY" != "true" ]]; then
  fail "Kolibri did not respond at ${HEALTH_URL} within ${HEALTH_TIMEOUT}s. Check logs: docker compose logs kolibri"
fi

log "Kolibri is ready."

# ---------------------------------------------------------------------------
# Step 6 — Print access information
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Kolibri installed successfully"
echo "============================================================"
echo ""
echo "  Local domain : http://${LOCAL_DOMAIN}"
echo "  Health check : ${HEALTH_URL} (internal — via docker exec)"
echo ""
echo "  Facility name: ${KOLIBRI_FACILITY_NAME:-Comunidade}"
echo "  Data path    : ${KOLIBRI_DATA_PATH}"
echo ""
echo "  Reverse proxy entry (desired-state/server/reverse-proxy.yaml):"
echo "    domain  : ${LOCAL_DOMAIN}"
echo "    backend : kolibri:8080"
echo "    health  : /api/public/v1/info/"
echo ""

# ---------------------------------------------------------------------------
# Step 7 — User onboarding note
# ---------------------------------------------------------------------------
echo "  FIRST-RUN SETUP"
echo "  ---------------"
echo "  1. Open http://${LOCAL_DOMAIN} in a browser on the local mesh network."
echo "  2. A setup wizard will appear on first visit."
echo "     - Set the device name and language."
echo "     - Create the superuser (admin) account."
echo "     - Set up the facility (school or community group)."
echo "  3. Save admin credentials in secrets/kolibri.env — never in chat."
echo ""
echo "  CHANNEL DOWNLOAD (requires internet on first run)"
echo "  --------------------------------------------------"
echo "  Kolibri comes with no content installed."
echo "  To download educational channels (Khan Academy, etc.):"
echo "  1. Log in as admin and go to Device > Channels."
echo "  2. Connect the server to the internet temporarily."
echo "  3. Import the desired channels — this can take several hours."
echo "  4. Once downloaded, the content is available offline permanently."
echo "  5. Disconnect from internet when done if operating in offline mode."
echo ""
echo "  BACKUP"
echo "  ------"
echo "  - Backup job defined in desired-state/server/backup-policy.yaml:"
echo "    * kolibri-data : weekly Sunday at 03:00"
echo "  - Student progress data is in ${KOLIBRI_DATA_PATH}."
echo "  - Content channels are large — only user/facility data is critical."
echo ""
echo "  ROLLBACK"
echo "  --------"
echo "  - To stop: docker compose stop"
echo "  - To remove: docker compose down  (data directory preserved)"
echo "  - To wipe all data: docker compose down && rm -rf ${KOLIBRI_DATA_PATH}"
echo "============================================================"
