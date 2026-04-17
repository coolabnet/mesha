#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# scripts/qa-onboarding-readiness.sh
#
# Read-only onboarding readiness checks plus a detailed handoff brief for
# another agent or maintainer to execute.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STRICT=false
AGENT_BRIEF=false
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

usage() {
  cat <<EOF
Usage: $0 [--strict] [--agent-brief]

Options:
  --strict       Treat warnings as failures in the exit code
  --agent-brief  Print a numbered execution brief after the checks
  -h, --help     Show this help
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
  --strict)
    STRICT=true
    ;;
  --agent-brief)
    AGENT_BRIEF=true
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

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  GREEN='\033[0;32m'
  # shellcheck disable=SC2034
  CYAN='\033[0;36m'
  # shellcheck disable=SC2034
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  YELLOW=''
  GREEN=''
  # shellcheck disable=SC2034
  CYAN=''
  BOLD=''
  RESET=''
fi

header() { printf "\n%s%s%s\n" "$BOLD" "$1" "$RESET"; }
pass() {
  printf "%sPASS%s  %s\n" "$GREEN" "$RESET" "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
warn() {
  printf "%sWARN%s  %s\n" "$YELLOW" "$RESET" "$1"
  WARN_COUNT=$((WARN_COUNT + 1))
}
fail() {
  printf "%sFAIL%s  %s\n" "$RED" "$RESET" "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_file() {
  local rel="$1"
  if [[ -f "$REPO_ROOT/$rel" ]]; then
    pass "file present: $rel"
  else
    fail "missing file: $rel"
  fi
}

check_exec() {
  local rel="$1"
  if [[ -x "$REPO_ROOT/$rel" ]]; then
    pass "executable: $rel"
  else
    fail "missing executable bit or file: $rel"
  fi
}

check_yaml_key() {
  local rel="$1"
  local pattern="$2"
  local desc="$3"
  if grep -Eq "^[[:space:]]*${pattern}:" "$REPO_ROOT/$rel"; then
    pass "$desc"
  else
    warn "$desc"
  fi
}

dotenv_has_value() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '
        $1 == key {
            value = substr($0, index($0, "=") + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if (value != "") found = 1
        }
        END { exit found ? 0 : 1 }
    ' "$file"
}

header "Documentation"
check_file "docs/configuration.md"
check_file "docs/deployment.md"
check_file "docs/testing/isolated-compose-plan.md"
check_file "secrets/README.md"
check_file "adapters/channels/telegram/.env.example"

header "Core onboarding scripts"
check_exec "scripts/doctor.sh"
check_exec "scripts/activate-workspace.sh"
check_exec "scripts/discover-from-thisnode.sh"
check_exec "scripts/mesh-heartbeat.sh"
check_exec "scripts/qa-onboarding-readiness.sh"
check_exec "skills/mesh-readonly/scripts/run-mesh-readonly.sh"

header "Required configuration surfaces"
check_file "inventories/mesh-nodes.yaml"
check_file "inventories/gateways.yaml"
check_file "inventories/sites.yaml"
check_file "desired-state/server/hosts.yaml"
check_yaml_key "inventories/mesh-nodes.yaml" "hostname" "mesh inventory contains at least one hostname field"
check_yaml_key "inventories/gateways.yaml" "hostname" "gateway inventory contains at least one hostname field"
check_yaml_key "inventories/sites.yaml" "name" "sites inventory contains at least one site name"
check_yaml_key "desired-state/server/hosts.yaml" "maintainers" "maintainer identity source is present in desired-state/server/hosts.yaml"

if [[ -f "$REPO_ROOT/secrets/maintainers.yaml" ]]; then
  pass "local-only maintainer identity file exists: secrets/maintainers.yaml"
else
  warn "local-only secrets/maintainers.yaml not found (okay if desired-state/server/hosts.yaml is authoritative)"
fi

header "Host secret indicators"
if command -v ssh >/dev/null 2>&1; then
  pass "ssh client available"
else
  fail "ssh client not available"
fi

if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    pass "docker compose plugin available"
  else
    warn "docker is installed but 'docker compose' is not available; isolated onboarding stack will not run"
  fi
else
  warn "docker not available; isolated onboarding stack will not run"
fi

if [[ -n ${MESHA_ROUTER_SSH_KEY:-} || -f "$HOME/.ssh/mesha-router-key" || -f "$HOME/.config/mesha/router-ssh-key" ]]; then
  pass "router SSH credential indicator present"
else
  warn "router SSH key path not detected via env or common local paths; live reads may still work via ssh-agent or ~/.ssh/config"
fi

if [[ -n ${MESHA_SERVER_SSH_KEY:-} || -f "$HOME/.ssh/mesha-server-key" || -f "$HOME/.config/mesha/server-ssh-key" ]]; then
  pass "server SSH credential indicator present"
else
  warn "server SSH key path not detected via env or common local paths"
fi

header "Telegram adapter readiness"
TELEGRAM_ENV="$REPO_ROOT/adapters/channels/telegram/.env"
if [[ -f $TELEGRAM_ENV ]]; then
  pass "telegram local env file present"
  for key in TELEGRAM_BOT_TOKEN TELEGRAM_MAINTAINER_IDS TELEGRAM_LEAD_MAINTAINER_IDS OPERATOR_ENDPOINT; do
    if dotenv_has_value "$TELEGRAM_ENV" "$key"; then
      pass "telegram env key populated: $key"
    else
      warn "telegram env key missing or empty: $key"
    fi
  done
else
  warn "Telegram adapter .env not found (okay if Telegram is not part of this deployment)"
fi

header "Dry-run onboarding path"
if bash "$REPO_ROOT/scripts/discover-from-thisnode.sh" --plan >/dev/null; then
  pass "discover-from-thisnode.sh --plan"
else
  fail "discover-from-thisnode.sh --plan"
fi

if bash "$REPO_ROOT/skills/mesh-readonly/scripts/run-mesh-readonly.sh" --plan >/dev/null; then
  pass "run-mesh-readonly.sh --plan"
else
  fail "run-mesh-readonly.sh --plan"
fi

if bash "$REPO_ROOT/scripts/mesh-heartbeat.sh" --plan >/dev/null; then
  pass "mesh-heartbeat.sh --plan"
else
  fail "mesh-heartbeat.sh --plan"
fi

if [[ $AGENT_BRIEF == true ]]; then
  header "Agent brief"
  cat <<EOF
1. Run \`bash scripts/doctor.sh\`.
2. Run \`bash scripts/qa-onboarding-readiness.sh --agent-brief\` and record every WARN and FAIL.
3. Read \`docs/configuration.md\` and confirm whether the deployment will use:
   - seeded inventories only
   - LibreMesh bootstrap via \`thisnode.info\`
   - Telegram
4. If Docker is available, run the isolated onboarding proof first:
   - \`bash scripts/test-compose-phase1.sh\`
5. If on a LibreMesh-connected host, run:
   - \`bash scripts/discover-from-thisnode.sh --plan\`
   - \`bash scripts/discover-from-thisnode.sh\`
6. Review:
   - \`exports/discovery/latest.json\`
   - \`exports/discovery/latest-candidate-node.yaml\`
   - \`exports/discovery/latest-candidate-gateway.yaml\`
7. Confirm the durable facts are merged into \`inventories/mesh-nodes.yaml\`, \`inventories/gateways.yaml\`, and \`inventories/sites.yaml\`.
8. Run:
   - \`bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --plan\`
   - \`bash skills/mesh-readonly/scripts/run-mesh-readonly.sh\`
   - \`bash scripts/mesh-heartbeat.sh\`
9. If Telegram is in scope, copy \`adapters/channels/telegram/.env.example\` to \`.env\`, fill the required values, then run:
   - \`node adapters/channels/telegram/health.mjs\`
10. Report:
   - what is configured
   - what is still stubbed
   - whether live mesh status works
   - whether cached heartbeat output was written
EOF
fi

header "Summary"
printf "PASS/WARN/FAIL counts: %s%d%s / %s%d%s / %s%d%s\n" \
  "$GREEN" "$PASS_COUNT" "$RESET" "$YELLOW" "$WARN_COUNT" "$RESET" "$RED" "$FAIL_COUNT" "$RESET"

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi

if [[ $STRICT == true && $WARN_COUNT -gt 0 ]]; then
  exit 1
fi

if [[ $WARN_COUNT -gt 0 ]]; then
  exit 2
fi

exit 0
