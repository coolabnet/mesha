#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# tests/05-healthchecks.sh — Healthchecks for running Docker services.
#
# Each check SKIPs (never fails) when a service is not running or not reachable.
# Failures are only emitted when a service responds but returns an unexpected
# HTTP status code.
#
# Ports sourced from desired-state/server/service-catalog.yaml and
# desired-state/server/domains.yaml:
#   nextcloud      port 80   (container-internal; reverse-proxied)
#   jellyfin       port 8096
#   kolibri        port 8080
#   homer          port 8080
#   prometheus     port 9090
#   grafana        port 3000
#   telegram       WEBHOOK_PORT 8080 (from adapters/channels/telegram/.env.example)
#
# All checks use localhost because the QA runner is on the same host as Docker.
#
# Usage:
#   ./tests/05-healthchecks.sh
#   bash tests/05-healthchecks.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# Helper: check_http <description> <url> [expected_status]
#
# Attempts an HTTP request and:
#   - SKIP  if service is not reachable (connection refused / timeout)
#   - PASS  if the HTTP status matches expected_status (default 200)
#   - FAIL  if the service responds but with a different status
# ---------------------------------------------------------------------------
check_http() {
    local description="$1"
    local url="$2"
    local expected_status="${3:-200}"

    if ! check_command curl; then
        qa_skip "$description" "curl not available"
        return
    fi

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 10 "$url" 2>/dev/null; true)

    if [[ "$status" == "000" ]]; then
        qa_skip "$description" "service not reachable at $url"
    elif [[ "$status" == "$expected_status" ]]; then
        qa_pass "$description (HTTP $status)"
    else
        qa_fail "$description — expected HTTP $expected_status, got HTTP $status at $url"
    fi
}

# ---------------------------------------------------------------------------
# Helper: check_docker_service <description> <compose_file>
#
# Checks whether any container defined in the compose file is running.
#   - SKIP  if docker is unavailable or no containers are running
#   - PASS  if at least one container shows "running" or "Up" state
# ---------------------------------------------------------------------------
check_docker_service() {
    local description="$1"
    local compose_file="$2"

    if ! check_command docker; then
        qa_skip "$description docker containers" "docker not available"
        return
    fi

    if [[ ! -f "$compose_file" ]]; then
        qa_skip "$description docker containers" "compose file not found: $compose_file"
        return
    fi

    if docker compose -f "$compose_file" ps 2>/dev/null | grep -qiE "running|up"; then
        qa_pass "$description — at least one container is running"
    else
        qa_skip "$description" "no running containers found via $(basename "$compose_file")"
    fi
}

# ---------------------------------------------------------------------------
# run_healthchecks
# ---------------------------------------------------------------------------

run_healthchecks() {

    # -----------------------------------------------------------------------
    qa_section "HTTP healthchecks — service endpoints"
    # -----------------------------------------------------------------------
    # Ports from desired-state/server/service-catalog.yaml:
    #   homer-dashboard  port: 8080  (same port as kolibri; both behind reverse proxy)
    #   kolibri          port: 8080
    #   nextcloud        port: 80    (container-internal; nginx reverse-proxied)
    #   jellyfin         port: 8096
    #   prometheus       port: 9090
    #   grafana          port: 3000
    #
    # Jellyfin health endpoint: /health (documented in Jellyfin API)
    # Kolibri public info:      /api/public/info/
    # Prometheus healthy:       /-/healthy
    # Grafana health:           /api/health
    # Homer:                    / (serves the dashboard directly)
    # Nextcloud status:         /status.php (returns JSON, HTTP 200 when up)

    check_http "Homer dashboard"         "http://localhost:8080/"              200
    check_http "Kolibri public info API" "http://localhost:8080/api/public/info/" 200
    check_http "Nextcloud status.php"    "http://localhost:80/status.php"      200
    check_http "Jellyfin health"         "http://localhost:8096/health"        200
    check_http "Prometheus healthy"      "http://localhost:9090/-/healthy"     200
    check_http "Grafana API health"      "http://localhost:3000/api/health"    200

    # Telegram adapter webhook server.
    # WEBHOOK_PORT defaults to 8080 per adapters/channels/telegram/.env.example.
    # The adapter only starts this server when TELEGRAM_WEBHOOK_URL is set and
    # it is running in webhook mode; in polling mode no local server is started.
    # We accept either 200 or 404 as "service is up" — anything else or a
    # connection refusal means the webhook server is not running.
    local webhook_port="${WEBHOOK_PORT:-8080}"
    local telegram_health_url="http://localhost:${webhook_port}/health"
    if ! check_command curl; then
        qa_skip "Telegram adapter webhook /health" "curl not available"
    else
        local tg_status
        tg_status=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 3 --max-time 10 "$telegram_health_url" 2>/dev/null; true)
        if [[ "$tg_status" == "000" ]]; then
            qa_skip "Telegram adapter webhook /health" \
                "webhook server not reachable at $telegram_health_url (normal in polling mode)"
        elif [[ "$tg_status" == "200" || "$tg_status" == "404" ]]; then
            qa_pass "Telegram adapter webhook server is listening (HTTP $tg_status)"
        else
            qa_fail "Telegram adapter webhook — unexpected HTTP $tg_status at $telegram_health_url"
        fi
    fi

    # -----------------------------------------------------------------------
    qa_section "Docker container status checks"
    # -----------------------------------------------------------------------
    # Compose file paths from skills/server-services/scripts/* and
    # adapters/channels/telegram as discovered in the repository.

    check_docker_service "Nextcloud" \
        "$WORKSPACE_ROOT/skills/server-services/scripts/nextcloud/docker-compose.yaml"

    check_docker_service "Jellyfin" \
        "$WORKSPACE_ROOT/skills/server-services/scripts/jellyfin/docker-compose.yaml"

    check_docker_service "Kolibri" \
        "$WORKSPACE_ROOT/skills/server-services/scripts/kolibri/docker-compose.yaml"

    check_docker_service "Homer dashboard" \
        "$WORKSPACE_ROOT/skills/server-services/scripts/homer/docker-compose.yaml"

    check_docker_service "Prometheus stack" \
        "$WORKSPACE_ROOT/skills/server-services/scripts/prometheus/docker-compose.yaml"

    check_docker_service "Telegram adapter" \
        "$WORKSPACE_ROOT/adapters/channels/telegram/docker-compose.yaml"

}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_healthchecks
    qa_summary
fi
