#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
set -euo pipefail

# ---------------------------------------------------------------------------
# Nextcloud install recipe
# Community Infrastructure Operator — server-services skill
#
# Idempotent: safe to run multiple times. Will skip steps already done.
# Local domain: nuvem.bairro.local (port 80 behind reverse proxy)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="nextcloud"
LOCAL_DOMAIN="nuvem.bairro.local"
HEALTH_URL="http://localhost/status.php"
HEALTH_TIMEOUT=60

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [nextcloud] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [nextcloud] ERROR: $*" >&2; exit 1; }

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
    log ".env not found — copying from .env.example. Edit the file before re-running."
    cp .env.example .env
    fail ".env was created from .env.example. Fill in all required values and run this script again."
  else
    fail ".env file is missing and no .env.example found. Cannot continue."
  fi
fi

log ".env file found."

# ---------------------------------------------------------------------------
# Step 3 — Validate required environment variables
# ---------------------------------------------------------------------------
log "Step 3: Validating required environment variables..."

# Load .env (skip comments and blank lines)
set -o allexport
# shellcheck disable=SC1091
source <(grep -v '^\s*#' .env | grep -v '^\s*$')
set +o allexport

REQUIRED_VARS=(
  NEXTCLOUD_ADMIN_USER
  NEXTCLOUD_ADMIN_PASSWORD
  MYSQL_ROOT_PASSWORD
  MYSQL_DATABASE
  MYSQL_USER
  MYSQL_PASSWORD
  NEXTCLOUD_TRUSTED_DOMAINS
)

MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    MISSING+=("$var")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  fail "The following required variables are not set in .env: ${MISSING[*]}"
fi

# Check for placeholder values that were never changed
for var in NEXTCLOUD_ADMIN_PASSWORD MYSQL_ROOT_PASSWORD MYSQL_PASSWORD; do
  if [[ "${!var}" == *"change-me"* ]]; then
    fail "${var} still contains the placeholder value 'change-me'. Set a real password before installing."
  fi
done

log "Environment variables OK."

# ---------------------------------------------------------------------------
# Step 4 — Create required data directories
# ---------------------------------------------------------------------------
log "Step 4: Creating data directories..."

mkdir -p ./data/nextcloud
mkdir -p ./data/nextcloud-db

log "Data directories ready: ./data/nextcloud  ./data/nextcloud-db"

# ---------------------------------------------------------------------------
# Step 5 — Pull images
# ---------------------------------------------------------------------------
log "Step 5: Pulling Docker images..."

docker compose pull

log "Images pulled."

# ---------------------------------------------------------------------------
# Step 6 — Start services
# ---------------------------------------------------------------------------
log "Step 6: Starting services with docker compose up -d..."

docker compose up -d

log "Services started."

# ---------------------------------------------------------------------------
# Step 7 — Wait for health check
# ---------------------------------------------------------------------------
log "Step 7: Waiting for Nextcloud to become healthy (up to ${HEALTH_TIMEOUT}s)..."

ELAPSED=0
INTERVAL=5
HEALTHY=false

while [[ $ELAPSED -lt $HEALTH_TIMEOUT ]]; do
  HTTP_STATUS=$(docker exec nextcloud_app curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" 2>/dev/null || true)
  if [[ "$HTTP_STATUS" == "200" ]]; then
    HEALTHY=true
    break
  fi
  log "  ...not ready yet (HTTP ${HTTP_STATUS:-no response}), waiting ${INTERVAL}s..."
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ "$HEALTHY" != "true" ]]; then
  fail "Nextcloud did not become healthy within ${HEALTH_TIMEOUT}s. Check logs: docker compose logs nextcloud_app"
fi

log "Nextcloud is healthy."

# ---------------------------------------------------------------------------
# Step 8 — Print access information
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Nextcloud installed successfully"
echo "============================================================"
echo ""
echo "  Local domain : http://${LOCAL_DOMAIN}"
echo "  Health check : ${HEALTH_URL}"
echo ""
echo "  Reverse proxy entry (desired-state/server/reverse-proxy.yaml):"
echo "    domain  : ${LOCAL_DOMAIN}"
echo "    backend : nextcloud_app:80"
echo "    health  : /status.php"
echo ""

# ---------------------------------------------------------------------------
# Step 9 — User onboarding note
# ---------------------------------------------------------------------------
echo "  ONBOARDING NOTE"
echo "  ---------------"
echo "  - Open http://${LOCAL_DOMAIN} in your browser (from the local mesh network)."
echo "  - Log in with the admin credentials you set in .env."
echo "  - Create user accounts for school and clinic staff from the admin panel."
echo "  - Shared folders and calendars can be set up after first login."
echo "  - Credentials are stored in secrets/nextcloud.env — never share in chat."
echo ""
echo "  BACKUP"
echo "  ------"
echo "  - Backup jobs are defined in desired-state/server/backup-policy.yaml:"
echo "    * nextcloud-data  : daily at 02:00"
echo "    * nextcloud-db    : daily at 02:30"
echo "  - Run backup hooks as described in the backup policy before going live."
echo ""
echo "  ROLLBACK"
echo "  --------"
echo "  - To remove: docker compose down -v  (WARNING: destroys volumes)"
echo "  - To stop only: docker compose stop"
echo "============================================================"
