#!/usr/bin/env bash
# tests/02-syntax.sh — Validate the syntax of every shell script, Python
# module, Node.js ESM file, and YAML document in the workspace.
#
# Usage:
#   ./tests/02-syntax.sh
#   bash tests/02-syntax.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

run_syntax_checks() {
    cd "$WORKSPACE_ROOT"

    # -----------------------------------------------------------------------
    qa_section "Bash syntax (bash -n)"
    # -----------------------------------------------------------------------

    local -a SH_FILES=(
        scripts/bootstrap.sh
        scripts/doctor.sh
        scripts/activate-workspace.sh
        scripts/discover-from-thisnode.sh
        scripts/mesh-heartbeat.sh
        scripts/qa-onboarding-readiness.sh
        skills/mesh-readonly/scripts/run-mesh-readonly.sh
        skills/mesh-rollout/scripts/run-rollout.sh
        skills/mesh-rollout/scripts/stage-upgrade.sh
        skills/mesh-rollout/scripts/validate-node.sh
        skills/mesh-rollout/scripts/rollback-node.sh
        skills/mesh-rollout/scripts/check-drift.sh
        skills/server-services/scripts/create-network.sh
        skills/server-services/scripts/nextcloud/install.sh
        skills/server-services/scripts/jellyfin/install.sh
        skills/server-services/scripts/kolibri/install.sh
        skills/server-services/scripts/homer/install.sh
        skills/server-services/scripts/prometheus/install.sh
        adapters/mesh/collect-nodes.sh
        adapters/mesh/collect-topology.sh
        adapters/server/collect-health.sh
        adapters/server/collect-services.sh
        tests/lib.sh
    )

    local f
    for f in "${SH_FILES[@]}"; do
        local abs="${WORKSPACE_ROOT}/${f}"
        if [[ ! -f "$abs" ]]; then
            qa_fail "bash syntax: ${f}  (file not found)"
            continue
        fi
        local err
        err="$(bash -n "$abs" 2>&1)"
        if [[ $? -eq 0 ]]; then
            qa_pass "bash syntax OK: ${f}"
        else
            qa_fail "bash syntax error: ${f}"
            printf "       %s\n" "$err"
        fi
    done

    # -----------------------------------------------------------------------
    qa_section "Python syntax (py_compile)"
    # -----------------------------------------------------------------------

    require_command python3 "python3 not installed — skipping Python syntax checks" || {
        # require_command already called qa_skip; skip remaining Python tests.
        true
    }

    if check_command python3; then
        local -a PY_FILES=(
            adapters/mesh/normalize.py
        )
        for f in "${PY_FILES[@]}"; do
            local abs="${WORKSPACE_ROOT}/${f}"
            if [[ ! -f "$abs" ]]; then
                qa_fail "python syntax: ${f}  (file not found)"
                continue
            fi
            local err
            err="$(python3 -m py_compile "$abs" 2>&1)"
            if [[ $? -eq 0 ]]; then
                qa_pass "python syntax OK: ${f}"
            else
                qa_fail "python syntax error: ${f}"
                printf "       %s\n" "$err"
            fi
        done
    fi

    # -----------------------------------------------------------------------
    qa_section "Node.js ESM syntax"
    # -----------------------------------------------------------------------
    # `node --check` only works for CommonJS modules; it does not support ESM
    # (type:module / .mjs files).  The safest cross-platform approach is to
    # attempt a timed import and treat any SyntaxError as a failure while
    # ignoring expected runtime errors (e.g. missing TELEGRAM_BOT_TOKEN).

    require_command node "node not installed — skipping Node.js syntax checks" || true

    if check_command node; then
        local -a MJS_FILES=(
            adapters/channels/telegram/adapter.mjs
            adapters/channels/telegram/health.mjs
        )
        for f in "${MJS_FILES[@]}"; do
            local abs="${WORKSPACE_ROOT}/${f}"
            if [[ ! -f "$abs" ]]; then
                qa_fail "node syntax: ${f}  (file not found)"
                continue
            fi

            # Run the module with a 3-second timeout.  A SyntaxError or
            # ReferenceError emitted before any async I/O indicates a parse
            # problem.  All other non-zero exits (missing env vars, network,
            # etc.) are treated as "syntax OK — runtime failure expected".
            local output
            output="$(timeout 3 node --input-type=module < "$abs" 2>&1 || true)"
            if printf '%s\n' "$output" | grep -qE '^(file:///|[[:space:]]*).*SyntaxError'; then
                qa_fail "node syntax error: ${f}"
                printf '%s\n' "$output" | grep -E 'SyntaxError' | head -5 | while IFS= read -r line; do
                    printf "       %s\n" "$line"
                done
            else
                qa_pass "node syntax OK (no SyntaxError detected): ${f}"
            fi
        done
    fi

    # -----------------------------------------------------------------------
    qa_section "YAML syntax (python3 yaml.safe_load)"
    # -----------------------------------------------------------------------

    if ! check_command python3; then
        qa_skip "YAML syntax checks" "python3 not available"
    else
        # Build the file list with find so that glob expansion is not needed
        # and the test works even when individual directories are absent.
        local -a YAML_FILES=()

        # Helper: add a file to the list only if it exists.
        _add_yaml() {
            local p="${WORKSPACE_ROOT}/${1}"
            [[ -f "$p" ]] && YAML_FILES+=( "$p" )
        }

        # desired-state — all .yaml / .yml files, recursively
        while IFS= read -r -d '' p; do
            YAML_FILES+=( "$p" )
        done < <(find "${WORKSPACE_ROOT}/desired-state" \
                      -type f \( -name '*.yaml' -o -name '*.yml' \) \
                      -print0 2>/dev/null | sort -z)

        # inventories
        while IFS= read -r -d '' p; do
            YAML_FILES+=( "$p" )
        done < <(find "${WORKSPACE_ROOT}/inventories" \
                      -type f \( -name '*.yaml' -o -name '*.yml' \) \
                      -print0 2>/dev/null | sort -z)

        # docker-compose files inside server-service scripts
        while IFS= read -r -d '' p; do
            YAML_FILES+=( "$p" )
        done < <(find "${WORKSPACE_ROOT}/skills/server-services/scripts" \
                      -type f -name 'docker-compose.yaml' \
                      -print0 2>/dev/null | sort -z)

        # Telegram adapter compose file
        _add_yaml "adapters/channels/telegram/docker-compose.yaml"

        if [[ ${#YAML_FILES[@]} -eq 0 ]]; then
            qa_skip "YAML syntax checks" "no YAML files found"
        else
            local errors
            errors="$(python3 - "${YAML_FILES[@]}" <<'PYEOF'
import sys, yaml

errors = []
for path in sys.argv[1:]:
    try:
        with open(path) as fh:
            yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        errors.append(f"{path}: {exc}")
    except OSError as exc:
        errors.append(f"{path}: {exc}")

if errors:
    for e in errors:
        print(e)
    sys.exit(1)
PYEOF
            )"
            if [[ $? -eq 0 ]]; then
                qa_pass "YAML syntax OK: ${#YAML_FILES[@]} file(s) validated"
            else
                # Emit one failure per erroring file for clear attribution.
                local line
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    # Strip WORKSPACE_ROOT prefix for readability.
                    local short="${line#"${WORKSPACE_ROOT}/"}"
                    qa_fail "YAML syntax error: ${short}"
                done <<< "$errors"
            fi
        fi
    fi

}

# ---------------------------------------------------------------------------
# Entry point — only run when executed directly, not when sourced.
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_syntax_checks
    qa_summary
fi
