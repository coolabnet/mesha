#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# tests/04-dryrun.sh — Safe dry-run / smoke tests for Mesha scripts and adapters.
#
# No network access required. No real routers touched.
# Scripts are invoked in their safest available mode; tests SKIP when a safe
# mode is unavailable rather than running with side effects.
#
# Usage:
#   ./tests/04-dryrun.sh
#   bash tests/04-dryrun.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# run_dryrun_checks
# ---------------------------------------------------------------------------

run_dryrun_checks() {

  # -----------------------------------------------------------------------
  qa_section "A. doctor.sh — read-only health diagnostics"
  # -----------------------------------------------------------------------
  # doctor.sh exit codes:
  #   0 — all checks pass
  #   1 — one or more critical failures  (e.g. openclaw not installed)
  #   2 — warnings only (e.g. missing optional tools or runtime dirs)
  # All three are valid outcomes on a baseline system; only a crash (rc>=3)
  # or a bash syntax/parse error (rc=127) would indicate a real problem.

  timeout 30 bash "$WORKSPACE_ROOT/scripts/doctor.sh" >/tmp/qa_doctor.out 2>&1
  local rc=$?
  if [[ $rc -eq 0 || $rc -eq 1 || $rc -eq 2 ]]; then
    qa_pass "doctor.sh runs cleanly without crashing (rc=$rc)"
  elif [[ $rc -eq 124 ]]; then
    qa_fail "doctor.sh timed out after 30 seconds"
  else
    qa_fail "doctor.sh crashed with unexpected rc=$rc"
    qa_info "Output tail: $(tail -5 /tmp/qa_doctor.out 2>/dev/null || true)"
  fi

  # -----------------------------------------------------------------------
  qa_section "B. bootstrap.sh --check-only — read-only prerequisite check"
  # -----------------------------------------------------------------------
  # bootstrap.sh supports --check-only (confirmed in source).
  # In that mode it checks tools and prints suggestions but makes NO changes.
  # Exit 0 = all required tools present; exit 1 = missing required tools.
  # Both are acceptable outcomes here.

  timeout 30 bash "$WORKSPACE_ROOT/scripts/bootstrap.sh" --check-only \
    >/tmp/qa_bootstrap.out 2>&1
  local brc=$?
  if [[ $brc -eq 0 || $brc -eq 1 ]]; then
    qa_pass "bootstrap.sh --check-only runs cleanly (rc=$brc)"
  elif [[ $brc -eq 124 ]]; then
    qa_fail "bootstrap.sh --check-only timed out"
  else
    qa_fail "bootstrap.sh --check-only crashed with unexpected rc=$brc"
    qa_info "Output tail: $(tail -5 /tmp/qa_bootstrap.out 2>/dev/null || true)"
  fi

  # -----------------------------------------------------------------------
  qa_section "C. activate-workspace.sh — side-effect analysis"
  # -----------------------------------------------------------------------
  # activate-workspace.sh has no --dry-run or --check-only flag.
  # It creates runtime directories (logs/incidents, logs/maintenance,
  # logs/decisions, exports) and prints an activation prompt.
  # Running it here would create those directories as side effects on any
  # host; skip in a clean QA environment to preserve test isolation.

  qa_skip "activate-workspace.sh" \
    "no dry-run flag available — creates runtime directories as side effects (logs/, exports/)"

  # -----------------------------------------------------------------------
  qa_section "D. run-rollout.sh --dry-run — rollout plan without changes"
  # -----------------------------------------------------------------------
  # run-rollout.sh requires:
  #   --firmware-url  (mandatory; triggers usage() and exit 1 if absent)
  #   --dry-run       prints plan and exits 0 — no SSH, no node changes
  # It also checks:
  #   - desired-state/mesh/community-profile/rollout-policy.yaml  (must exist)
  #   - inventories/mesh-nodes.yaml                               (must exist)
  #   - skills/mesh-rollout/scripts/stage-upgrade.sh              (must be executable)
  #   - skills/mesh-rollout/scripts/validate-node.sh              (must be executable)
  # All of those files should be present in the repo per 01-file-inventory.sh.

  local policy_file="$WORKSPACE_ROOT/desired-state/mesh/community-profile/rollout-policy.yaml"
  local inventory_file="$WORKSPACE_ROOT/inventories/mesh-nodes.yaml"
  local stage_upgrade="$WORKSPACE_ROOT/skills/mesh-rollout/scripts/stage-upgrade.sh"
  local validate_node="$WORKSPACE_ROOT/skills/mesh-rollout/scripts/validate-node.sh"

  if [[ ! -f $policy_file ]]; then
    qa_skip "run-rollout.sh --dry-run" "rollout-policy.yaml not found — run 01-file-inventory first"
  elif [[ ! -f $inventory_file ]]; then
    qa_skip "run-rollout.sh --dry-run" "mesh-nodes.yaml not found — run 01-file-inventory first"
  elif [[ ! -x $stage_upgrade ]]; then
    qa_skip "run-rollout.sh --dry-run" "stage-upgrade.sh missing or not executable"
  elif [[ ! -x $validate_node ]]; then
    qa_skip "run-rollout.sh --dry-run" "validate-node.sh missing or not executable"
  else
    assert_exit_zero "run-rollout.sh --dry-run exits cleanly with a dummy firmware URL" \
      timeout 15 bash \
      "$WORKSPACE_ROOT/skills/mesh-rollout/scripts/run-rollout.sh" \
      --firmware-url "/tmp/qa-dummy-firmware.bin" \
      --dry-run
  fi

  # -----------------------------------------------------------------------
  qa_section "E. mesh-readonly runner --plan — inventory selection only"
  # -----------------------------------------------------------------------

  local mesh_runner="$WORKSPACE_ROOT/skills/mesh-readonly/scripts/run-mesh-readonly.sh"
  if [[ ! -x $mesh_runner ]]; then
    qa_skip "mesh-readonly runner --plan" "runner script missing or not executable"
  else
    assert_exit_zero "mesh-readonly runner --plan exits cleanly without touching routers" \
      timeout 15 bash "$mesh_runner" --plan
  fi

  # -----------------------------------------------------------------------
  qa_section "F. mesh-heartbeat.sh --plan — scheduled collection without live reads"
  # -----------------------------------------------------------------------

  local mesh_heartbeat="$WORKSPACE_ROOT/scripts/mesh-heartbeat.sh"
  if [[ ! -x $mesh_heartbeat ]]; then
    qa_skip "mesh-heartbeat.sh --plan" "heartbeat script missing or not executable"
  else
    assert_exit_zero "mesh-heartbeat.sh --plan exits cleanly without touching routers" \
      timeout 15 bash "$mesh_heartbeat" --plan

    local heartbeat_latest="$WORKSPACE_ROOT/exports/mesh/latest.json"
    local heartbeat_before
    local heartbeat_backup
    heartbeat_before="$(mktemp)"
    heartbeat_backup="$(mktemp)"
    printf '{"sentinel":"preserve-existing-cache"}\n' >"$heartbeat_before"
    mkdir -p "$(dirname "$heartbeat_latest")"
    local heartbeat_had_latest=false
    if [[ -f $heartbeat_latest ]]; then
      cp "$heartbeat_latest" "$heartbeat_backup"
      heartbeat_had_latest=true
    fi
    cp "$heartbeat_before" "$heartbeat_latest"

    timeout 15 bash "$mesh_heartbeat" --plan >/dev/null 2>&1
    local heartbeat_plan_rc=$?
    if [[ $heartbeat_plan_rc -ne 0 ]]; then
      qa_fail "mesh-heartbeat.sh --plan preserves cache state"
    elif cmp -s "$heartbeat_before" "$heartbeat_latest"; then
      qa_pass "mesh-heartbeat.sh --plan does not overwrite exports/mesh/latest.json"
    else
      qa_fail "mesh-heartbeat.sh --plan does not overwrite exports/mesh/latest.json"
    fi

    if [[ $heartbeat_had_latest == true ]]; then
      cp "$heartbeat_backup" "$heartbeat_latest"
    else
      rm -f "$heartbeat_latest"
    fi

    rm -f "$heartbeat_before"
    rm -f "$heartbeat_backup"
  fi

  # -----------------------------------------------------------------------
  qa_section "G. discover-from-thisnode.sh --plan — bootstrap discovery without live reads"
  # -----------------------------------------------------------------------

  local discover_thisnode="$WORKSPACE_ROOT/scripts/discover-from-thisnode.sh"
  if [[ ! -x $discover_thisnode ]]; then
    qa_skip "discover-from-thisnode.sh --plan" "discovery script missing or not executable"
  else
    assert_exit_zero "discover-from-thisnode.sh --plan exits cleanly without touching routers" \
      timeout 15 bash "$discover_thisnode" --plan

    local discover_plan_out
    discover_plan_out="$(mktemp)"
    timeout 15 bash "$discover_thisnode" --plan >"$discover_plan_out"
    assert_contains "$discover_plan_out" '"latest_gateway_candidate"' \
      "discover-from-thisnode.sh --plan reports the gateway candidate output path"
    assert_contains "$discover_plan_out" '"target_host": "thisnode.info"' \
      "discover-from-thisnode.sh --plan stays scoped to thisnode.info"
    rm -f "$discover_plan_out"
  fi

  # -----------------------------------------------------------------------
  qa_section "H. qa-onboarding-readiness.sh — read-only onboarding handoff"
  # -----------------------------------------------------------------------

  local onboarding_qa="$WORKSPACE_ROOT/scripts/qa-onboarding-readiness.sh"
  if [[ ! -x $onboarding_qa ]]; then
    qa_skip "qa-onboarding-readiness.sh" "onboarding QA script missing or not executable"
  else
    local onboarding_qa_rc=0
    timeout 20 bash "$onboarding_qa" --agent-brief >/tmp/qa_onboarding_readiness.out 2>&1 || onboarding_qa_rc=$?
    if [[ $onboarding_qa_rc -eq 0 || $onboarding_qa_rc -eq 2 ]]; then
      qa_pass "qa-onboarding-readiness.sh runs cleanly in read-only mode"
    else
      qa_fail "qa-onboarding-readiness.sh crashed with unexpected rc=$onboarding_qa_rc"
      qa_info "Output tail: $(tail -10 /tmp/qa_onboarding_readiness.out 2>/dev/null || true)"
    fi
  fi

  # -----------------------------------------------------------------------
  qa_section "I. test-compose-phase1.sh --help — isolated onboarding harness entrypoint"
  # -----------------------------------------------------------------------

  local compose_phase1="$WORKSPACE_ROOT/scripts/test-compose-phase1.sh"
  local run_compose_phase1="$WORKSPACE_ROOT/scripts/run-compose-phase1-test.sh"
  if [[ ! -x $compose_phase1 || ! -x $run_compose_phase1 ]]; then
    qa_skip "test-compose-phase1.sh --help" "compose phase 1 test script missing or not executable"
  else
    assert_exit_zero "test-compose-phase1.sh --help exits cleanly" \
      timeout 10 bash "$compose_phase1" --help
    assert_exit_zero "run-compose-phase1-test.sh --help exits cleanly" \
      timeout 10 bash "$run_compose_phase1" --help
  fi

  # -----------------------------------------------------------------------
  qa_section "J. normalize.py — stdin JSON normalization"
  # -----------------------------------------------------------------------
  # normalize.py reads JSON from stdin.
  # An empty array [] is valid: the script outputs [] and exits 0.
  # A single node object is also valid; we test both forms.

  if ! check_command python3; then
    qa_skip "normalize.py empty-array input" "python3 not available"
    qa_skip "normalize.py single-node object input" "python3 not available"
  else
    # Test 1: empty array — should produce "[]" on stdout, exit 0
    # shellcheck disable=SC2034
    local norm_out
    # shellcheck disable=SC2034
    norm_out="$(echo '[]' | timeout 5 python3 \
      "$WORKSPACE_ROOT/adapters/mesh/normalize.py" 2>/dev/null)"
    local norm_rc=$?
    if [[ $norm_rc -eq 0 ]]; then
      qa_pass "normalize.py accepts empty JSON array (rc=0)"
    else
      qa_fail "normalize.py returned rc=$norm_rc for empty array input"
    fi

    # Test 2: minimal node object — should normalize and exit 0
    local node_json='{"hostname":"test-node","firmware":"23.05","status":"online","role":"gateway","site":"escola"}'
    # shellcheck disable=SC2034
    local norm2_out
    # shellcheck disable=SC2034
    norm2_out="$(echo "$node_json" | timeout 5 python3 \
      "$WORKSPACE_ROOT/adapters/mesh/normalize.py" 2>/dev/null)"
    local norm2_rc=$?
    if [[ $norm2_rc -eq 0 ]]; then
      qa_pass "normalize.py normalizes a single node object (rc=0)"
    else
      qa_fail "normalize.py returned rc=$norm2_rc for single-node object"
    fi

    # Test 3: invalid JSON — should exit 1 (not crash)
    # shellcheck disable=SC2034
    local bad_out
    # shellcheck disable=SC2034
    bad_out="$(echo 'not-json' | timeout 5 python3 \
      "$WORKSPACE_ROOT/adapters/mesh/normalize.py" 2>/dev/null)"
    local bad_rc=$?
    if [[ $bad_rc -eq 1 ]]; then
      qa_pass "normalize.py exits 1 on invalid JSON input (not a crash)"
    else
      qa_fail "normalize.py returned rc=$bad_rc for invalid JSON — expected 1"
    fi
  fi

  # -----------------------------------------------------------------------
  qa_section "K. Telegram health.mjs — environment-aware health check"
  # -----------------------------------------------------------------------
  # health.mjs does NOT start an HTTP server; it runs checks and exits.
  # Without TELEGRAM_BOT_TOKEN it reports check failures and exits 1.
  # Exit 1 (checks failed) is expected and safe; exit 0 would mean a real
  # token was present in the environment.
  # The script is safe to invoke in any environment.

  if ! check_command node; then
    qa_skip "Telegram health.mjs" "node not available"
  else
    # Run without env vars — expect check failures (rc=1) or all-pass (rc=0)
    TELEGRAM_BOT_TOKEN="" OPERATOR_ENDPOINT="" \
      timeout 15 node "$WORKSPACE_ROOT/adapters/channels/telegram/health.mjs" \
      >/tmp/qa_telegram_health.out 2>&1
    local trc=$?
    if [[ $trc -eq 0 ]]; then
      # All checks passed — a real token must be set in the environment
      qa_pass "Telegram health.mjs completed all checks (rc=0)"
    elif [[ $trc -eq 1 ]]; then
      # Expected: TELEGRAM_BOT_TOKEN not set → check failures → rc=1
      qa_pass "Telegram health.mjs runs and exits cleanly without credentials (rc=1 expected)"
    elif [[ $trc -eq 124 ]]; then
      qa_fail "Telegram health.mjs timed out after 15 seconds"
    else
      qa_fail "Telegram health.mjs crashed with unexpected rc=$trc"
      qa_info "Output: $(cat /tmp/qa_telegram_health.out 2>/dev/null | head -10 || true)"
    fi
  fi

}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  run_dryrun_checks
  qa_summary
fi
