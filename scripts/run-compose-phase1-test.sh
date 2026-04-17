#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# scripts/run-compose-phase1-test.sh
#
# Phase 1 isolated onboarding smoke test using docker-compose.onboarding-test.yml.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.onboarding-test.yml"
FIXTURE_INVENTORY_DIR="$REPO_ROOT/docker/onboarding-test/fixtures/inventories"
KEEP_WORKSPACE=false
WORK_DIR=""
PROJECT_NAME="mesha-phase1-${RANDOM}"

usage() {
  cat <<EOF
Usage: $0 [--keep-workspace]

Options:
  --keep-workspace  Preserve the temporary workspace copy after the test
  -h, --help        Show this help
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
  --keep-workspace)
    KEEP_WORKSPACE=true
    ;;
  -h | --help)
    usage
    ;;
  *)
    echo "Unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd git
require_cmd ssh-keygen
require_cmd python3
require_cmd tar

if ! docker compose version >/dev/null 2>&1; then
  echo "Missing required Docker Compose plugin: 'docker compose'" >&2
  exit 1
fi

cleanup() {
  if [[ -n ${WORK_DIR:-} ]]; then
    MESHA_TEST_WORKSPACE_DIR="$WORK_DIR/workspace" \
      MESHA_TEST_KEYS_DIR="$WORK_DIR/keys" \
      docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans >/dev/null 2>&1 || true
    if [[ $KEEP_WORKSPACE == false ]]; then
      rm -rf "$WORK_DIR"
    fi
  fi
}
trap cleanup EXIT

WORK_DIR="$(mktemp -d)"
mkdir -p "$WORK_DIR/workspace" "$WORK_DIR/keys"
echo "Phase 1 test workspace: $WORK_DIR/workspace"

git -C "$REPO_ROOT" ls-files -z \
  --cached \
  --modified \
  -- ':!:.openclaw/**' \
  ':!:exports/**' \
  ':!:logs/**' \
  ':!:secrets/**' \
  ':!:IDENTITY.md' \
  ':!:USER.md' >"$WORK_DIR/workspace-files.zlist"

(cd "$REPO_ROOT" && tar --null -T "$WORK_DIR/workspace-files.zlist" -cf -) \
  | (cd "$WORK_DIR/workspace" && tar -xf -)

git -C "$WORK_DIR/workspace" init -q

cp "$FIXTURE_INVENTORY_DIR/mesh-nodes.yaml" "$WORK_DIR/workspace/inventories/mesh-nodes.yaml"
cp "$FIXTURE_INVENTORY_DIR/gateways.yaml" "$WORK_DIR/workspace/inventories/gateways.yaml"
cp "$FIXTURE_INVENTORY_DIR/sites.yaml" "$WORK_DIR/workspace/inventories/sites.yaml"

ssh-keygen -q -t ed25519 -N "" -f "$WORK_DIR/keys/id_ed25519" >/dev/null

export MESHA_TEST_WORKSPACE_DIR="$WORK_DIR/workspace"
export MESHA_TEST_KEYS_DIR="$WORK_DIR/keys"

docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans >/dev/null 2>&1 || true
compose_rc=0
if ! docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up --build --abort-on-container-exit --exit-code-from phase1-test phase1-test; then
  compose_rc=$?
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs --no-color phase1-test fake-thisnode fake-gateway >&2 || true
  exit "$compose_rc"
fi

python3 - "$WORK_DIR/workspace" <<'PYEOF'
import json
import pathlib
import sys

workspace = pathlib.Path(sys.argv[1])

discovery = json.loads((workspace / "exports" / "discovery" / "latest.json").read_text(encoding="utf-8"))
mesh = json.loads((workspace / "exports" / "mesh" / "latest.json").read_text(encoding="utf-8"))

if discovery.get("inferred", {}).get("observed_hostname") != "thisnode-fixture":
    raise SystemExit("Discovery observed hostname mismatch")
if "10.13.0.10" not in discovery.get("inferred", {}).get("ipv4_candidates", []):
    raise SystemExit("Discovery IPv4 candidate mismatch")
if mesh.get("mode") != "live":
    raise SystemExit("Heartbeat latest.json is not live")
if mesh.get("topology", {}).get("gateway_hostname") != "gateway-fixture":
    raise SystemExit("Topology gateway hostname mismatch")
PYEOF

echo "Phase 1 isolated onboarding test passed."
echo "Workspace copy: $WORK_DIR/workspace"
