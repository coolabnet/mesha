#!/usr/bin/env bash
# tests/01-file-inventory.sh — Verify that all expected workspace files exist,
# are non-empty, and (for scripts) are executable.
#
# Usage:
#   ./tests/01-file-inventory.sh
#   bash tests/01-file-inventory.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# check_file <rel_path> [executable]
# Asserts the file exists and is non-empty.  When the optional second argument
# is "exec", also asserts it is executable.
check_file() {
    local rel_path="$1"
    local check_exec="${2:-}"
    local abs_path="${WORKSPACE_ROOT}/${rel_path}"

    assert_file_exists    "$abs_path" "exists:      ${rel_path}"
    assert_file_nonempty  "$abs_path" "non-empty:   ${rel_path}"
    if [[ "$check_exec" == "exec" ]]; then
        assert_file_executable "$abs_path" "executable:  ${rel_path}"
    fi
}

# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

run_file_inventory() {
    cd "$WORKSPACE_ROOT"

    # -----------------------------------------------------------------------
    qa_section "Root / tracking documents"
    # -----------------------------------------------------------------------
    for doc in \
        BOOTSTRAP.md \
        AGENTS.md \
        SOUL.md \
        TOOLS.md \
        MEMORY.md \
        WORKING.md \
        TASKS.md \
        PROGRESS.md
    do
        check_file "$doc"
    done

    # -----------------------------------------------------------------------
    qa_section "Inventories"
    # -----------------------------------------------------------------------
    check_file "inventories/mesh-nodes.yaml"
    check_file "inventories/sites.yaml"
    check_file "inventories/gateways.yaml"
    check_file "inventories/local-services.yaml"
    check_file "inventories/hardware-models.yaml"

    # -----------------------------------------------------------------------
    qa_section "Desired state — mesh"
    # -----------------------------------------------------------------------
    check_file "desired-state/mesh/community-profile/lime-community"
    check_file "desired-state/mesh/community-profile/rollout-policy.yaml"
    check_file "desired-state/mesh/firmware-policy.yaml"

    # -----------------------------------------------------------------------
    qa_section "Desired state — server"
    # -----------------------------------------------------------------------
    check_file "desired-state/server/service-catalog.yaml"
    check_file "desired-state/server/hosts.yaml"
    check_file "desired-state/server/domains.yaml"
    check_file "desired-state/server/reverse-proxy.yaml"
    check_file "desired-state/server/backup-policy.yaml"
    check_file "desired-state/server/monitoring/prometheus.yml"
    check_file "desired-state/server/monitoring/alerting-rules.yaml"

    # -----------------------------------------------------------------------
    qa_section "Core scripts"
    # -----------------------------------------------------------------------
    check_file "scripts/bootstrap.sh"    exec
    check_file "scripts/doctor.sh"       exec
    check_file "scripts/activate-workspace.sh" exec
    check_file "scripts/bootstrap.mjs"
    check_file "scripts/bootstrap.ps1"

    # -----------------------------------------------------------------------
    qa_section "Mesh-rollout scripts"
    # -----------------------------------------------------------------------
    check_file "skills/mesh-rollout/scripts/run-rollout.sh"   exec
    check_file "skills/mesh-rollout/scripts/stage-upgrade.sh" exec
    check_file "skills/mesh-rollout/scripts/validate-node.sh" exec
    check_file "skills/mesh-rollout/scripts/rollback-node.sh" exec
    check_file "skills/mesh-rollout/scripts/check-drift.sh"   exec

    # -----------------------------------------------------------------------
    qa_section "Server-service recipe scripts"
    # -----------------------------------------------------------------------
    check_file "skills/server-services/scripts/create-network.sh"        exec
    check_file "skills/server-services/scripts/nextcloud/install.sh"     exec
    check_file "skills/server-services/scripts/jellyfin/install.sh"      exec
    check_file "skills/server-services/scripts/kolibri/install.sh"       exec
    check_file "skills/server-services/scripts/homer/install.sh"         exec
    check_file "skills/server-services/scripts/prometheus/install.sh"    exec

    # -----------------------------------------------------------------------
    qa_section "Mesh and server adapters"
    # -----------------------------------------------------------------------
    check_file "adapters/mesh/collect-nodes.sh"    exec
    check_file "adapters/mesh/collect-topology.sh" exec
    check_file "adapters/mesh/normalize.py"
    check_file "adapters/server/collect-health.sh"    exec
    check_file "adapters/server/collect-services.sh"  exec

    # -----------------------------------------------------------------------
    qa_section "Telegram channel adapter"
    # -----------------------------------------------------------------------
    check_file "adapters/channels/telegram/adapter.mjs"
    check_file "adapters/channels/telegram/health.mjs"
    check_file "adapters/channels/telegram/docker-compose.yaml"
    check_file "adapters/channels/telegram/.env.example"
    check_file "adapters/channels/telegram/README.md"

    # -----------------------------------------------------------------------
    qa_section "Docker Compose files"
    # -----------------------------------------------------------------------
    check_file "skills/server-services/scripts/nextcloud/docker-compose.yaml"
    check_file "skills/server-services/scripts/jellyfin/docker-compose.yaml"
    check_file "skills/server-services/scripts/kolibri/docker-compose.yaml"
    check_file "skills/server-services/scripts/homer/docker-compose.yaml"
    check_file "skills/server-services/scripts/prometheus/docker-compose.yaml"
    check_file "adapters/channels/telegram/docker-compose.yaml"

    # -----------------------------------------------------------------------
    qa_section "Secrets directory — no plaintext credential files"
    # -----------------------------------------------------------------------
    local secrets_dir="${WORKSPACE_ROOT}/secrets"
    if [[ ! -d "$secrets_dir" ]]; then
        qa_skip "secrets/ directory not present" "directory does not exist"
    else
        local found_sensitive=0
        local f
        for f in \
            "${secrets_dir}"/*.yaml \
            "${secrets_dir}"/*.json \
            "${secrets_dir}"/*.env \
            "${secrets_dir}"/*.key \
            "${secrets_dir}"/*.pem
        do
            # Glob expands to the literal pattern when no match — skip those.
            [[ -e "$f" ]] || continue
            qa_fail "secrets/ must not contain plaintext credential file: $(basename "$f")"
            found_sensitive=1
        done
        if [[ $found_sensitive -eq 0 ]]; then
            qa_pass "secrets/ contains no .yaml / .json / .env / .key / .pem files"
        fi
    fi

    # -----------------------------------------------------------------------
    qa_section "Runtime consistency — no stale OpenClaw references"
    # -----------------------------------------------------------------------
    local stale_pattern='claude''-flow|Claude'' Flow|claude'' flow'
    local branding_targets=(
        "$WORKSPACE_ROOT/README.md"
        "$WORKSPACE_ROOT/BOOTSTRAP.md"
        "$WORKSPACE_ROOT/AGENTS.md"
        "$WORKSPACE_ROOT/SOUL.md"
        "$WORKSPACE_ROOT/TOOLS.md"
        "$WORKSPACE_ROOT/MEMORY.md"
        "$WORKSPACE_ROOT/WORKING.md"
        "$WORKSPACE_ROOT/TASKS.md"
        "$WORKSPACE_ROOT/PROGRESS.md"
        "$WORKSPACE_ROOT/docs"
        "$WORKSPACE_ROOT/scripts"
        "$WORKSPACE_ROOT/tests"
    )
    local stale_hits
    stale_hits="$(
        LC_ALL=C grep -RInE "$stale_pattern" \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            --exclude-dir=secrets \
            "${branding_targets[@]}" 2>/dev/null || true
    )"
    if [[ -n "$stale_hits" ]]; then
        qa_fail "workspace docs and scripts must not contain stale runtime references"
        qa_info "Matches:"
        printf '%s\n' "$stale_hits"
    else
        qa_pass "workspace docs and scripts contain no stale runtime references"
    fi

    local stale_command_pattern='openclaw'' start|openclaw'' init|openclaw'' workspace activate|openclaw'' workspace list'
    local stale_command_hits
    stale_command_hits="$(
        LC_ALL=C grep -RInE "$stale_command_pattern" \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            --exclude-dir=secrets \
            "${branding_targets[@]}" 2>/dev/null || true
    )"
    if [[ -n "$stale_command_hits" ]]; then
        qa_fail "workspace docs and scripts must not contain obsolete OpenClaw commands"
        qa_info "Matches:"
        printf '%s\n' "$stale_command_hits"
    else
        qa_pass "workspace docs and scripts contain no obsolete OpenClaw commands"
    fi

}

# ---------------------------------------------------------------------------
# Entry point — only run when executed directly, not when sourced.
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_file_inventory
    qa_summary
fi
