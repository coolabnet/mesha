#!/usr/bin/env bash
# tests/07-inline-python.sh — Validate inline Python in shell heredocs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run_inline_python_checks() {
  cd "$WORKSPACE_ROOT" || exit 1
  require_command python3 "python3 required for inline Python checks" || return 0

  qa_section "Inline Python in shell heredocs"

  # Files known to contain inline Python via heredoc
  local -a FILES_WITH_HEREDOC_PY=(
    adapters/mesh/collect-nodes.sh
    skills/mesh-rollout/scripts/run-rollout.sh
  )

  for f in "${FILES_WITH_HEREDOC_PY[@]}"; do
    local abs="${WORKSPACE_ROOT}/${f}"
    if [[ ! -f $abs ]]; then
      qa_skip "${f}" "file not found"
      continue
    fi

    # Extract Python code from heredocs using Python itself
    local extracted
    extracted=$(python3 - "${abs}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as fh:
    content = fh.read()

# Find heredoc blocks that feed into python
# Pattern: python3 ... <<'MARKER' or <<MARKER ... MARKER
pattern = r"python3?[^<]*<<-?\s*['\"]?(\w+)['\"]?\n(.*?)\n\s*\1"
matches = re.findall(pattern, content, re.DOTALL)
if matches:
    for marker, body in matches:
        print(body)
else:
    sys.exit(1)
PYEOF
    )

    if [[ -z $extracted ]]; then
      qa_skip "${f}" "no inline Python heredocs found or extraction failed"
      continue
    fi

    # Validate the extracted Python
    local err
    err=$(echo "$extracted" | python3 -c "import sys; compile(sys.stdin.read(), '${f}', 'exec')" 2>&1) || true
    if [[ -z $err ]]; then
      qa_pass "inline Python syntax OK: ${f}"
    else
      qa_fail "inline Python syntax error: ${f}"
      printf "       %s\n" "$err"
    fi
  done
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  run_inline_python_checks
  qa_summary
fi
