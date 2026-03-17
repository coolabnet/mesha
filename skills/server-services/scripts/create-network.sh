#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# create-network.sh
# Community Infrastructure Operator — server-services skill
#
# Creates the shared Docker network used by all community service containers.
# This script must be run once before installing any service recipe.
# It is idempotent — safe to run multiple times.
#
# Network name : community-net
# Driver       : bridge
# ---------------------------------------------------------------------------

NETWORK_NAME="community-net"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [network] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [network] ERROR: $*" >&2; exit 1; }

if ! command -v docker &>/dev/null; then
  fail "docker is not installed or not in PATH."
fi

if ! docker info &>/dev/null; then
  fail "Docker daemon is not running or current user cannot connect to it."
fi

if docker network inspect "${NETWORK_NAME}" &>/dev/null; then
  log "Network '${NETWORK_NAME}' already exists. Nothing to do."
else
  log "Creating Docker network '${NETWORK_NAME}' (bridge driver)..."
  docker network create --driver bridge "${NETWORK_NAME}"
  log "Network '${NETWORK_NAME}' created successfully."
fi

log "Done. Services can now be connected to '${NETWORK_NAME}'."
