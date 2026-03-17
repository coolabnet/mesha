#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Homer install recipe
# Community Infrastructure Operator — server-services skill
#
# Idempotent: safe to run multiple times. Will skip steps already done.
# Local domain: inicio.bairro.local (port 8081 behind reverse proxy)
#
# Homer is a static dashboard — no database, no secrets required.
# Config lives in ./config/config.yaml (mounted into container).
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="homer"
LOCAL_DOMAIN="inicio.bairro.local"
CONTAINER_PORT=8080
STARTUP_WAIT=5

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [homer] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [homer] ERROR: $*" >&2; exit 1; }

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
# Step 2 — Ensure community-net network exists
# ---------------------------------------------------------------------------
log "Step 2: Checking community-net Docker network..."

if ! docker network inspect community-net &>/dev/null; then
  fail "Docker network 'community-net' does not exist. Run 'bash skills/server-services/scripts/create-network.sh' first."
fi

log "community-net network found."

# ---------------------------------------------------------------------------
# Step 3 — Create config directory
# ---------------------------------------------------------------------------
log "Step 3: Ensuring config directory exists..."

cd "${SCRIPT_DIR}"

mkdir -p "./config"

log "Config directory ready: ${SCRIPT_DIR}/config"

# ---------------------------------------------------------------------------
# Step 4 — Copy config if not already present (never overwrite)
# ---------------------------------------------------------------------------
log "Step 4: Checking dashboard config..."

if [[ -f "./config/config.yaml" ]]; then
  log "config/config.yaml already exists — skipping copy to preserve local customizations."
else
  if [[ -f "${SCRIPT_DIR}/config/config.yaml" ]]; then
    # Config source is already in place (mounted from repo)
    log "config/config.yaml found in script directory — no copy needed."
  else
    fail "config/config.yaml not found. Expected at: ${SCRIPT_DIR}/config/config.yaml"
  fi
fi

log "Dashboard config OK."

# ---------------------------------------------------------------------------
# Step 5 — Pull image
# ---------------------------------------------------------------------------
log "Step 5: Pulling Homer Docker image..."

docker compose pull

log "Image pulled."

# ---------------------------------------------------------------------------
# Step 6 — Start service
# ---------------------------------------------------------------------------
log "Step 6: Starting Homer with docker compose up -d..."

docker compose up -d

log "Container started."

# ---------------------------------------------------------------------------
# Step 7 — Wait and verify
# ---------------------------------------------------------------------------
log "Step 7: Waiting ${STARTUP_WAIT}s for Homer to initialize..."

sleep "${STARTUP_WAIT}"

# Verify container is running
if docker ps --format '{{.Names}}' | grep -q "^homer$"; then
  log "Homer container is running."
else
  fail "Homer container is not running after start. Check: docker compose logs homer"
fi

# ---------------------------------------------------------------------------
# Step 8 — Print access information
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Homer dashboard installed successfully"
echo "============================================================"
echo ""
echo "  Local domain : http://${LOCAL_DOMAIN}"
echo "  Internal port: ${CONTAINER_PORT} (behind reverse proxy on community-net)"
echo "  Config file  : ${SCRIPT_DIR}/config/config.yaml"
echo ""
echo "  Reverse proxy entry (desired-state/server/reverse-proxy.yaml):"
echo "    domain  : ${LOCAL_DOMAIN}"
echo "    backend : homer:${CONTAINER_PORT}"
echo "    health  : /"
echo "    auth    : none"
echo ""
echo "  CONFIGURATION"
echo "  -------------"
echo "  To customize the dashboard, edit:"
echo "    ${SCRIPT_DIR}/config/config.yaml"
echo "  Then reload Homer: docker compose restart homer"
echo ""
echo "  Homer does NOT require a restart after config edits if the"
echo "  file is edited and the browser is refreshed (static asset)."
echo ""
echo "  SOURCE OF TRUTH"
echo "  ---------------"
echo "  The config.yaml file is tracked in the repo."
echo "  Add new services to service-catalog.yaml first, then update"
echo "  config/config.yaml to add the service to the dashboard."
echo ""
echo "  ROLLBACK"
echo "  --------"
echo "  - To stop: docker compose down  (config directory preserved)"
echo "  - Config can be restored from git: git checkout -- config/config.yaml"
echo "============================================================"
