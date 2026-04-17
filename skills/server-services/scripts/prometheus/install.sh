#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
set -euo pipefail

# ---------------------------------------------------------------------------
# Prometheus + Grafana + node-exporter install recipe
# Community Infrastructure Operator — server-services skill
#
# Idempotent: safe to run multiple times. Will skip steps already done.
# Services installed by this script:
#   - Prometheus (metricas.bairro.local — maintainer only)
#   - Grafana    (grafana.bairro.local  — maintainer + read-only guest)
#   - Node Exporter (scraped internally, not publicly exposed)
#   - Blackbox Exporter (probes community service health endpoints)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
GRAFANA_URL="http://grafana.bairro.local"
PROMETHEUS_URL="http://metricas.bairro.local"
GRAFANA_HEALTH_URL="http://localhost:3000/api/health"
GRAFANA_TIMEOUT=120
GRAFANA_INTERVAL=5

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [monitoring] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [monitoring] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Step 1 — Prerequisites check
# ---------------------------------------------------------------------------
log "Step 1: Checking prerequisites..."

if ! command -v docker &>/dev/null; then
  fail "docker is not installed or not in PATH."
fi

if ! docker compose version &>/dev/null; then
  fail "docker compose plugin is not available. Install Docker Compose v2."
fi

if ! docker info &>/dev/null; then
  fail "Docker daemon is not running or current user cannot connect to it."
fi

if ! command -v curl &>/dev/null; then
  fail "curl is not installed. Install curl: apt-get install -y curl"
fi

log "Prerequisites OK."

# ---------------------------------------------------------------------------
# Step 2 — Ensure community-net exists
# ---------------------------------------------------------------------------
log "Step 2: Checking community-net Docker network..."

if ! docker network inspect community-net &>/dev/null; then
  fail "Docker network 'community-net' does not exist. Run 'bash ${REPO_ROOT}/skills/server-services/scripts/create-network.sh' first."
fi

log "community-net found."

# ---------------------------------------------------------------------------
# Step 3 — Validate .env file
# ---------------------------------------------------------------------------
log "Step 3: Checking .env file..."

cd "${SCRIPT_DIR}"

if [[ ! -f ".env" ]]; then
  if [[ -f ".env.example" ]]; then
    log ".env not found — copying from .env.example."
    cp .env.example .env
    log "IMPORTANT: Edit .env and replace placeholder passwords before continuing."
    log "  nano ${SCRIPT_DIR}/.env"
    fail "Stopping — .env was just created from example. Edit it and re-run."
  else
    fail ".env file missing and no .env.example found."
  fi
fi

# Check for unchanged placeholder passwords
if grep -q "change-me-" .env; then
  fail "Placeholder passwords detected in .env (change-me-*). Replace them before running."
fi

log ".env validated."

# Load environment
set -o allexport
# shellcheck disable=SC1091
source <(grep -v '^\s*#' .env | grep -v '^\s*$')
set +o allexport

# ---------------------------------------------------------------------------
# Step 4 — Create provisioning directories and config files
# ---------------------------------------------------------------------------
log "Step 4: Creating provisioning directories..."

mkdir -p "${SCRIPT_DIR}/provisioning/datasources"
mkdir -p "${SCRIPT_DIR}/provisioning/dashboards"
mkdir -p "${SCRIPT_DIR}/data/prometheus"
mkdir -p "${SCRIPT_DIR}/data/grafana"

# Write Grafana datasource provisioning
cat > "${SCRIPT_DIR}/provisioning/datasources/prometheus.yaml" <<'DATASOURCE'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      httpMethod: POST
      timeInterval: "15s"
DATASOURCE

log "Grafana datasource provisioning file written."

# Write Grafana dashboard provisioning
cat > "${SCRIPT_DIR}/provisioning/dashboards/community.yaml" <<'DASHPROV'
apiVersion: 1

providers:
  - name: "Community Dashboards"
    orgId: 1
    folder: "Community"
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
DASHPROV

log "Grafana dashboard provisioning file written."

# Write Blackbox Exporter config
cat > "${SCRIPT_DIR}/blackbox.yml" <<'BLACKBOX'
modules:
  http_2xx:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []  # defaults to 2xx
      method: GET
      follow_redirects: true
      preferred_ip_protocol: "ip4"
BLACKBOX

log "Blackbox exporter config written."

log "Provisioning directories and config files ready."

# ---------------------------------------------------------------------------
# Step 5 — Verify desired-state monitoring config files exist
# ---------------------------------------------------------------------------
log "Step 5: Verifying monitoring config files..."

if [[ ! -f "${REPO_ROOT}/desired-state/server/monitoring/prometheus.yml" ]]; then
  fail "Missing: desired-state/server/monitoring/prometheus.yml — run Codex-C3 to generate it."
fi

if [[ ! -f "${REPO_ROOT}/desired-state/server/monitoring/alerting-rules.yaml" ]]; then
  fail "Missing: desired-state/server/monitoring/alerting-rules.yaml — run Codex-C3 to generate it."
fi

if [[ ! -f "${REPO_ROOT}/desired-state/server/monitoring/grafana-dashboards/community-overview.json" ]]; then
  log "WARNING: community-overview.json not found. Grafana will start without the overview dashboard."
fi

log "Config files verified."

# ---------------------------------------------------------------------------
# Step 6 — Pull images
# ---------------------------------------------------------------------------
log "Step 6: Pulling Docker images..."

docker compose pull

log "Images pulled."

# ---------------------------------------------------------------------------
# Step 7 — Start the monitoring stack
# ---------------------------------------------------------------------------
log "Step 7: Starting monitoring stack with docker compose up -d..."

docker compose up -d

log "Stack started."

# ---------------------------------------------------------------------------
# Step 8 — Wait for Grafana to be ready
# ---------------------------------------------------------------------------
log "Step 8: Waiting for Grafana to be ready (timeout: ${GRAFANA_TIMEOUT}s)..."

ELAPSED=0
GRAFANA_READY=false

while [[ $ELAPSED -lt $GRAFANA_TIMEOUT ]]; do
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${GRAFANA_HEALTH_URL}" 2>/dev/null || true)
  if [[ "$HTTP_STATUS" == "200" ]]; then
    GRAFANA_READY=true
    break
  fi
  log "  ...Grafana not ready yet (HTTP ${HTTP_STATUS:-no response}), waiting ${GRAFANA_INTERVAL}s..."
  sleep $GRAFANA_INTERVAL
  ELAPSED=$((ELAPSED + GRAFANA_INTERVAL))
done

if [[ "$GRAFANA_READY" != "true" ]]; then
  fail "Grafana did not respond at ${GRAFANA_HEALTH_URL} within ${GRAFANA_TIMEOUT}s. Check: docker compose logs grafana"
fi

log "Grafana is ready."

# ---------------------------------------------------------------------------
# Step 9 — Print access information
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Monitoring stack installed successfully"
echo "============================================================"
echo ""
echo "  Grafana    : ${GRAFANA_URL}"
echo "  Prometheus : ${PROMETHEUS_URL}"
echo ""
echo "  GRAFANA ACCESS"
echo "  --------------"
echo "  Guest (read-only) : ${GRAFANA_URL}  — no login required"
echo "  Admin login       : use credentials from .env (GF_ADMIN_USER / GF_ADMIN_PASSWORD)"
echo ""
echo "  PROMETHEUS ACCESS"
echo "  -----------------"
echo "  Protected by basic auth at the reverse proxy level."
echo "  See desired-state/server/reverse-proxy.yaml for auth config."
echo ""
echo "  REVERSE PROXY ENTRIES (desired-state/server/reverse-proxy.yaml):"
echo "    grafana   : grafana:3000    health: /api/health"
echo "    prometheus: prometheus:9090 health: /-/healthy  auth: basic"
echo ""
echo "  DASHBOARDS"
echo "  ----------"
echo "  The 'Mesha Community Overview' dashboard is pre-provisioned."
echo "  Source: desired-state/server/monitoring/grafana-dashboards/community-overview.json"
echo "  To add dashboards: add JSON files to the grafana-dashboards/ directory."
echo ""
echo "  ALERTING RULES"
echo "  --------------"
echo "  Source: desired-state/server/monitoring/alerting-rules.yaml"
echo "  To reload without restart: curl -X POST http://prometheus:9090/-/reload"
echo "  (requires --web.enable-lifecycle flag — already set)"
echo ""
echo "  ROLLBACK"
echo "  --------"
echo "  - Stop stack : docker compose down"
echo "  - Wipe data  : docker compose down && docker volume rm prometheus-data grafana-data"
echo "============================================================"
