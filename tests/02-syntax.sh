#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
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
  cd "$WORKSPACE_ROOT" || exit 1

  # -----------------------------------------------------------------------
  qa_section "Bash syntax (bash -n)"
  # -----------------------------------------------------------------------

  local -a SH_FILES=()
  # Collect *.sh files
  while IFS= read -r -d '' f; do
    SH_FILES+=("$f")
  done < <(find "$WORKSPACE_ROOT" -name '*.sh' -not -path '*/.git/*' -print0 | sort -z)
  # Also collect shell scripts without .sh suffix (by shebang)
  while IFS= read -r -d '' f; do
    SH_FILES+=("$f")
  done < <(find "$WORKSPACE_ROOT" -not -name '*.sh' -not -path '*/.git/*' -type f -print0 2>/dev/null |
    while IFS= read -r -d '' f; do
      head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
      head -1 "$f" | grep -qiE '\b(ba)?sh\b' || continue
      printf '%s\0' "$f"
    done | sort -z)

  local f
  for f in "${SH_FILES[@]}"; do
    local rel="${f#"$WORKSPACE_ROOT/"}"
    local err
    err="$(bash -n "$f" 2>&1)"
    if [[ $? -eq 0 ]]; then
      qa_pass "bash syntax OK: ${rel}"
    else
      qa_fail "bash syntax error: ${rel}"
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
    local -a PY_FILES=()
    while IFS= read -r -d '' f; do
      PY_FILES+=("$f")
    done < <(find "$WORKSPACE_ROOT" -name '*.py' -not -path '*/.git/*' -not -path '*/.venv/*' -not -path '*/node_modules/*' -print0 | sort -z)

    for f in "${PY_FILES[@]}"; do
      local rel="${f#"$WORKSPACE_ROOT/"}"
      local err
      err="$(python3 -m py_compile "$f" 2>&1)"
      if [[ $? -eq 0 ]]; then
        qa_pass "python syntax OK: ${rel}"
      else
        qa_fail "python syntax error: ${rel}"
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
      scripts/bootstrap.mjs
    )
    for f in "${MJS_FILES[@]}"; do
      local abs="${WORKSPACE_ROOT}/${f}"
      if [[ ! -f $abs ]]; then
        qa_fail "node syntax: ${f}  (file not found)"
        continue
      fi

      # Run the module with a 3-second timeout.  A SyntaxError or
      # ReferenceError emitted before any async I/O indicates a parse
      # problem.  All other non-zero exits (missing env vars, network,
      # etc.) are treated as "syntax OK — runtime failure expected".
      local output
      output="$(timeout 3 node --input-type=module <"$abs" 2>&1 || true)"
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
      [[ -f $p ]] && YAML_FILES+=("$p")
    }

    # desired-state — all .yaml / .yml files, recursively
    while IFS= read -r -d '' p; do
      YAML_FILES+=("$p")
    done < <(find "${WORKSPACE_ROOT}/desired-state" \
      -type f \( -name '*.yaml' -o -name '*.yml' \) \
      -print0 2>/dev/null | sort -z)

    # inventories
    while IFS= read -r -d '' p; do
      YAML_FILES+=("$p")
    done < <(find "${WORKSPACE_ROOT}/inventories" \
      -type f \( -name '*.yaml' -o -name '*.yml' \) \
      -print0 2>/dev/null | sort -z)

    # docker-compose files inside server-service scripts
    while IFS= read -r -d '' p; do
      YAML_FILES+=("$p")
    done < <(find "${WORKSPACE_ROOT}/skills/server-services/scripts" \
      -type f -name 'docker-compose.yaml' \
      -print0 2>/dev/null | sort -z)

    # Telegram adapter compose file
    _add_yaml "adapters/channels/telegram/docker-compose.yaml"
    _add_yaml "docker-compose.onboarding-test.yml"

    if [[ ${#YAML_FILES[@]} -eq 0 ]]; then
      qa_skip "YAML syntax checks" "no YAML files found"
    else
      local errors
      errors="$(
        python3 - "${YAML_FILES[@]}" <<'PYEOF'
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
          [[ -z $line ]] && continue
          # Strip WORKSPACE_ROOT prefix for readability.
          local short="${line#"${WORKSPACE_ROOT}/"}"
          qa_fail "YAML syntax error: ${short}"
        done <<<"$errors"
      fi
    fi
  fi

  # -----------------------------------------------------------------------
  qa_section "Shebang/executable consistency"
  # -----------------------------------------------------------------------

  # Find .sh files with a shebang that are NOT marked executable
  # Exclude docker/**/bin/* (fake binaries intentionally not executable outside Docker)
  while IFS= read -r -d '' f; do
    head -c 2 "$f" | grep -q '^#!' || continue
    rel="${f#"$WORKSPACE_ROOT/"}"
    if [[ $rel == docker/*/bin/* ]]; then
      qa_pass "shebang+not-exec (docker fake bin, OK): ${rel}"
      continue
    fi
    if [[ ! -x $f ]]; then
      qa_fail "shebang but not executable: ${rel}"
    else
      qa_pass "shebang+executable OK: ${rel}"
    fi
  done < <(
    (
      find "$WORKSPACE_ROOT" -name '*.sh' -not -path '*/.git/*' -print0
      find "$WORKSPACE_ROOT" -not -name '*.sh' -not -path '*/.git/*' -type f -print0 2>/dev/null |
        while IFS= read -r -d '' f; do
          head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
          head -1 "$f" | grep -qiE '\b(ba)?sh\b' || continue
          printf '%s\0' "$f"
        done
    ) | sort -z
  )

  # -----------------------------------------------------------------------
  qa_section "Shell safety (set -e)"
  # -----------------------------------------------------------------------

  while IFS= read -r -d '' f; do
    rel="${f#"$WORKSPACE_ROOT/"}"
    # Skip test files — they use set -uo pipefail intentionally
    [[ $rel == tests/* ]] && continue
    # Skip .claude/ helpers — auto-generated, not project code
    [[ $rel == .claude/* ]] && continue

    shebang=$(head -1 "$f")
    # Only check files with a shebang
    [[ $shebang != '#!'* ]] && continue

    # Determine if bash or POSIX sh
    is_bash=false
    if [[ $shebang == *'bash'* ]]; then
      is_bash=true
    fi

    # Check for appropriate set options
    if $is_bash; then
      if grep -qE '^set -[a-z]*e[a-z]*u[a-z]*o[[:space:]]*pipefail' "$f"; then
        qa_pass "bash safety OK: ${rel}"
      elif grep -qE '^set -[a-z]*e[a-z]*' "$f"; then
        # Has set -e but not full set -euo pipefail — check for inline justification
        # Accept any comment on the same line as set -e, or a # reason: marker elsewhere
        set_line="$(grep -nE '^set -[a-z]*e[a-z]*' "$f" | head -1)"
        if echo "$set_line" | grep -qE '#'; then
          qa_pass "bash safety OK (justified): ${rel}"
        elif grep -qE '# reason:' "$f"; then
          qa_pass "bash safety OK (justified): ${rel}"
        else
          qa_fail "bash script missing 'set -euo pipefail': ${rel}"
        fi
      else
        qa_fail "bash script missing 'set -euo pipefail': ${rel}"
      fi
    else
      # POSIX sh
      if grep -qE '^set -e' "$f"; then
        qa_pass "sh safety OK: ${rel}"
      else
        qa_fail "POSIX sh script missing 'set -e': ${rel}"
      fi
    fi
  done < <(
    (
      find "$WORKSPACE_ROOT" -name '*.sh' -not -path '*/.git/*' -print0
      find "$WORKSPACE_ROOT" -not -name '*.sh' -not -path '*/.git/*' -type f -print0 2>/dev/null |
        while IFS= read -r -d '' f; do
          head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
          head -1 "$f" | grep -qiE '\b(ba)?sh\b' || continue
          printf '%s\0' "$f"
        done
    ) | sort -z
  )

  # -----------------------------------------------------------------------
  qa_section "PowerShell syntax"
  # -----------------------------------------------------------------------

  if ! check_command pwsh; then
    qa_skip "PowerShell syntax checks" "pwsh not available"
  else
    local -a PS_FILES=()
    while IFS= read -r -d '' f; do
      PS_FILES+=("$f")
    done < <(find "$WORKSPACE_ROOT" -name '*.ps1' -not -path '*/.git/*' -print0 | sort -z)

    if [[ ${#PS_FILES[@]} -eq 0 ]]; then
      qa_skip "PowerShell syntax checks" "no .ps1 files found"
    else
      for f in "${PS_FILES[@]}"; do
        rel="${f#"$WORKSPACE_ROOT/"}"
        local err
        # Pass file path via env var to avoid injection through string interpolation
        err=$(PWSH_PATH="$f" pwsh -Command '[System.Management.Automation.Language.Parser]::ParseFile($env:PWSH_PATH, [ref]$null, [ref]$null)' 2>&1) || true
        if echo "$err" | grep -qiE 'error|exception'; then
          qa_fail "PowerShell syntax error: ${rel}"
          printf "       %s\n" "$err"
        else
          qa_pass "PowerShell syntax OK: ${rel}"
        fi
      done
    fi
  fi

}

# ---------------------------------------------------------------------------
# Entry point — only run when executed directly, not when sourced.
# ---------------------------------------------------------------------------
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  run_syntax_checks
  qa_summary
fi
