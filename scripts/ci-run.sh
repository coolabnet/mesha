#!/usr/bin/env bash
# =============================================================================
# scripts/ci-run.sh — Mesha CI-agnostic quality gate runner
#
# Runs all quality checks in sequence. Exits on first failure with a clear
# error message. Tools that are not installed are skipped with a warning.
#
# Required tools (any missing tool is skipped with a warning, not a failure):
#   - betterleaks    — secret/credential scanning
#   - shellcheck     — shell script static analysis
#   - shfmt          — shell script formatting
#   - yamllint       — YAML linting
#   - ruff           — Python linting and formatting
#   - python3        — JSON syntax validation (stdlib json.tool)
#   - docker         — Docker compose validation (optional)
#
# Usage:
#   ./scripts/ci-run.sh
#
# Exit codes:
#   0  all checks passed
#   1  one or more checks failed
#
# Designed to work offline — no network calls are made.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

STEP_NUM=0
TOTAL_STEPS=8

step_header() {
  STEP_NUM=$((STEP_NUM + 1))
  printf "\n${BOLD}[%d/%d] %s${RESET}\n" "$STEP_NUM" "$TOTAL_STEPS" "$1"
  printf '%*s\n' 60 '' | tr ' ' '-'
}

ok() {
  printf "  ${GREEN}PASS${RESET} — %s\n" "$1"
}

warn() {
  printf "  ${YELLOW}SKIP${RESET} — %s\n" "$1"
}

fail() {
  printf "  ${RED}FAIL${RESET} — %s\n" "$1" >&2
  printf "\n${RED}${BOLD}CI aborted at step %d: %s${RESET}\n" "$STEP_NUM" "$1" >&2
  exit 1
}

# Resolve workspace root (one directory up from scripts/)
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE_ROOT"

printf "\n${BOLD}══════════════════════════════════════════════${RESET}\n"
printf "${BOLD}  Mesha CI Quality Gate${RESET}\n"
printf "${BOLD}  Workspace: %s${RESET}\n" "$WORKSPACE_ROOT"
printf "${BOLD}══════════════════════════════════════════════${RESET}\n"

# ---------------------------------------------------------------------------
# 1. Secret scan — betterleaks
# ---------------------------------------------------------------------------
step_header "Secret scan (betterleaks)"

if command -v betterleaks &>/dev/null; then
  # Scan only git-tracked files to avoid false positives from
  # secrets/ and .env files that exist locally but are gitignored.
  bl_rc=0
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    bl_out="$(git ls-files -z 2>/dev/null | xargs -0 -r betterleaks dir 2>&1)" && bl_rc=$? || bl_rc=$?
  else
    # Fallback: not in a git repo, scan everything
    warn "Not in a git repo — scanning all files (may include secrets/)"
    bl_out="$(betterleaks dir . 2>&1)" && bl_rc=$? || bl_rc=$?
  fi
  if [[ $bl_rc -eq 0 ]]; then
    ok "No secrets detected"
  else
    printf "%s\n" "$bl_out" >&2
    fail "betterleaks found potential secrets — review and remove before merging"
  fi
else
  warn "betterleaks not installed — skipping secret scan"
fi

# ---------------------------------------------------------------------------
# 2. Shell lint — shellcheck
# ---------------------------------------------------------------------------
step_header "Shell lint (shellcheck)"

if command -v shellcheck &>/dev/null; then
  shellcheck_targets="$({
    find . -name '*.sh' -not -path './.git/*' -print0 2>/dev/null
    find . -not -name '*.sh' -not -path './.git/*' -type f -print0 2>/dev/null |
      while IFS= read -r -d '' f; do
        head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
        head -1 "$f" | grep -qiE '\b(ba)?sh\b' || continue
        printf '%s\0' "$f"
      done
  } | xargs -0 shellcheck --severity=warning 2>&1)" && sc_rc=$? || sc_rc=$?
  if [[ $sc_rc -eq 0 ]]; then
    ok "All shell scripts pass shellcheck"
  else
    printf "%s\n" "$shellcheck_targets" >&2
    fail "shellcheck found warnings or errors — fix before merging"
  fi
else
  warn "shellcheck not installed — skipping shell lint"
fi

# ---------------------------------------------------------------------------
# 3. Shell format — shfmt
# ---------------------------------------------------------------------------
step_header "Shell format check (shfmt)"

if command -v shfmt &>/dev/null; then
  shfmt_out="$(shfmt -d . 2>&1)" && shfmt_rc=$? || shfmt_rc=$?
  if [[ $shfmt_rc -eq 0 ]]; then
    ok "All shell scripts are formatted correctly"
  else
    printf "%s\n" "$shfmt_out" >&2
    fail "shfmt found formatting issues — run 'shfmt -w .' to fix"
  fi
else
  warn "shfmt not installed — skipping shell format check"
fi

# ---------------------------------------------------------------------------
# 4. YAML lint — yamllint
# ---------------------------------------------------------------------------
step_header "YAML lint (yamllint)"

if command -v yamllint &>/dev/null; then
  if yamllint .; then
    ok "All YAML files pass yamllint"
  else
    fail "yamllint found issues — fix before merging"
  fi
else
  warn "yamllint not installed — skipping YAML lint"
fi

# ---------------------------------------------------------------------------
# 5. Python lint + format — ruff
# ---------------------------------------------------------------------------
step_header "Python lint and format (ruff)"

if command -v ruff &>/dev/null; then
  ruff_check_out="$(ruff check . 2>&1)" && ruff_check_rc=$? || ruff_check_rc=$?
  if [[ $ruff_check_rc -ne 0 ]]; then
    printf "%s\n" "$ruff_check_out" >&2
    fail "ruff check found issues — fix before merging"
  fi

  ruff_fmt_out="$(ruff format --check . 2>&1)" && ruff_fmt_rc=$? || ruff_fmt_rc=$?
  if [[ $ruff_fmt_rc -ne 0 ]]; then
    printf "%s\n" "$ruff_fmt_out" >&2
    fail "ruff format found issues — run 'ruff format .' to fix"
  fi

  ok "Python files pass ruff check and format"
else
  warn "ruff not installed — skipping Python lint and format"
fi

# ---------------------------------------------------------------------------
# 6. JSON syntax validation
# ---------------------------------------------------------------------------
step_header "JSON syntax validation"

if command -v python3 &>/dev/null; then
  json_found=0
  json_failed=0
  while IFS= read -r -d '' json_file; do
    json_found=1
    if ! python3 -m json.tool --no-ensure-ascii "$json_file" >/dev/null 2>&1; then
      printf "  ${RED}FAIL${RESET} — %s\n" "$json_file" >&2
      json_failed=1
    fi
  done < <(find . -name '*.json' -not -path './.git/*' -not -path './node_modules/*' -print0 2>/dev/null)

  if [[ $json_failed -eq 1 ]]; then
    fail "JSON syntax error detected — check JSON files for correctness"
  elif [[ $json_found -eq 0 ]]; then
    ok "No JSON files found — nothing to validate"
  else
    ok "All JSON files are syntactically valid"
  fi
else
  warn "python3 not installed — skipping JSON syntax validation"
fi

# ---------------------------------------------------------------------------
# 7. Full test suite
# ---------------------------------------------------------------------------
step_header "Full test suite (tests/run-all.sh)"

if [[ -x "tests/run-all.sh" ]]; then
  if bash tests/run-all.sh; then
    ok "All tests passed"
  else
    fail "Test suite failed — review output above and fix failing tests"
  fi
else
  fail "tests/run-all.sh not found or not executable — cannot run test suite"
fi

# ---------------------------------------------------------------------------
# 8. Docker compose validation + image pinning check
# ---------------------------------------------------------------------------
step_header "Docker compose validation and image pinning"

docker_available=0
if command -v docker &>/dev/null; then
  # Check if Docker daemon is actually responsive
  if docker info &>/dev/null; then
    docker_available=1
  else
    warn "Docker daemon not running — skipping compose validation"
  fi
else
  warn "docker not installed — skipping compose validation"
fi

if [[ $docker_available -eq 1 ]]; then
  # Provide placeholder values for ${VAR:?...} guards in compose files so
  # that `docker compose config` can validate without real fixtures on disk.
  # These are only used for static validation — real runs must set them.
  export MESHA_TEST_WORKSPACE_DIR="${MESHA_TEST_WORKSPACE_DIR:-/tmp/mesha-ci-placeholder-workspace}"
  export MESHA_TEST_KEYS_DIR="${MESHA_TEST_KEYS_DIR:-/tmp/mesha-ci-placeholder-keys}"

  # Find all docker-compose files
  compose_files_found=0
  compose_failed=0
  while IFS= read -r -d '' compose_file; do
    compose_files_found=$((compose_files_found + 1))
    printf "  Validating: %s\n" "$compose_file"
    if ! docker compose -f "$compose_file" config --quiet 2>&1; then
      printf "  ${RED}FAIL${RESET} — %s is invalid\n" "$compose_file" >&2
      compose_failed=1
    fi
  done < <(find . -name 'docker-compose*.y*ml' -not -path './.git/*' -print0 2>/dev/null)

  if [[ $compose_failed -eq 1 ]]; then
    fail "One or more docker-compose files are invalid"
  elif [[ $compose_files_found -eq 0 ]]; then
    ok "No docker-compose files found — nothing to validate"
  else
    ok "All docker-compose files are valid"
  fi
fi

# Image pinning check (does not require Docker daemon, only grep)
pinning_out="$(grep -rn 'image:.*:latest\|image:[^:]*$' \
  --include='*.yaml' --include='*.yml' . 2>/dev/null |
  grep -v '.git/' || true)"
if [[ -n $pinning_out ]]; then
  printf "  ${YELLOW}WARNING${RESET} — Unpinned Docker image tags found:\n"
  printf "%s\n" "$pinning_out" | sed 's/^/    /'
  printf "  ${YELLOW}Images should use explicit tags, not ':latest' or bare names.${RESET}\n"
  # This is a warning, not a hard failure — the check still passes
  ok "Image pinning check complete (warnings above — consider pinning)"
else
  ok "All Docker images use pinned tags"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n${BOLD}══════════════════════════════════════════════${RESET}\n"
printf "${GREEN}${BOLD}  All quality checks passed.${RESET}\n"
printf "${BOLD}══════════════════════════════════════════════${RESET}\n\n"
