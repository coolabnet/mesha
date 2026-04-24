#!/usr/bin/env bash
# tests/06-uci-validate.sh — Validate UCI config files
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run_uci_checks() {
  cd "$WORKSPACE_ROOT" || exit 1

  # -----------------------------------------------------------------------
  qa_section "UCI syntax validation"
  # -----------------------------------------------------------------------

  # Validate lime-community
  local lime_community="desired-state/mesh/community-profile/lime-community"
  if [[ -f $lime_community ]]; then
    # Check that every non-comment, non-blank line is a valid UCI directive
    # UCI lines: config <type> '<name>', option <key> '<value>', list <key> '<value>'
    # These may be indented with tabs/spaces; comments may also be indented
    local invalid
    invalid=$(grep -nE '^[[:space:]]*[^#[:space:]]' "$lime_community" |
      grep -vE '^[0-9]+:[[:space:]]*(config|option|list)[[:space:]]')
    if [[ -z $invalid ]]; then
      qa_pass "UCI syntax OK: ${lime_community}"
    else
      qa_fail "UCI syntax error: ${lime_community}"
      printf "       %s\n" "$invalid"
    fi
  else
    qa_skip "lime-community" "file not found"
  fi

  # Validate node override .uci files
  local uci_files=()
  while IFS= read -r -d '' f; do
    uci_files+=("$f")
  done < <(find desired-state/mesh/node-overrides -name '*.uci' -print0 2>/dev/null | sort -z)

  for f in "${uci_files[@]}"; do
    local invalid
    invalid=$(grep -nE '^[[:space:]]*[^#[:space:]]' "$f" |
      grep -vE '^[0-9]+:[[:space:]]*(config|option|list)[[:space:]]')
    if [[ -z $invalid ]]; then
      qa_pass "UCI syntax OK: ${f}"
    else
      qa_fail "UCI syntax error: ${f}"
      printf "       %s\n" "$invalid"
    fi
  done

  # -----------------------------------------------------------------------
  qa_section "UCI hostname cross-reference"
  # -----------------------------------------------------------------------

  # For each .uci file, extract hostname and verify it matches a node in mesh-nodes.yaml
  local have_pyyaml=0
  if ! check_command python3; then
    qa_skip "UCI hostname cross-reference" "python3 required for UCI cross-reference"
  elif python3 -c "import yaml" 2>/dev/null; then
    have_pyyaml=1
  else
    qa_skip "UCI hostname cross-reference" "PyYAML not installed (install python3-yaml or pip install pyyaml)"
  fi

  if [[ $have_pyyaml -eq 1 ]]; then
    for f in "${uci_files[@]}"; do
      local hostname
      hostname=$(grep -E "^[[:space:]]*option[[:space:]]+hostname" "$f" |
        sed -E "s/.*hostname[[:space:]]+'([^']+)'.*/\1/" | head -1)
      if [[ -z $hostname ]]; then
        qa_skip "${f}" "no hostname option found"
        continue
      fi

      # Cross-reference with mesh-nodes.yaml (pass hostname via argv to avoid quoting issues)
      local node_hostname="$hostname"
      if python3 -c '
import yaml, sys
with open("inventories/mesh-nodes.yaml") as fh:
    data = yaml.safe_load(fh)
names = {n["hostname"] for n in data.get("nodes", [])}
if sys.argv[1] not in names:
    print(f"hostname {sys.argv[1]!r} not found in mesh-nodes.yaml")
    sys.exit(1)
' "$node_hostname" 2>/dev/null; then
        qa_pass "UCI hostname cross-ref OK: ${hostname} in ${f}"
      else
        qa_fail "UCI hostname cross-ref FAIL: ${hostname} in ${f} not in mesh-nodes.yaml"
      fi
    done
  fi

  # -----------------------------------------------------------------------
  qa_section "UCI secret check"
  # -----------------------------------------------------------------------

  # Check that no UCI file contains secrets in option values
  # mesh_bssid, anygw_mac, mesh_key are public identifiers, not secrets
  local uci_all=("$lime_community" "${uci_files[@]}")
  for f in "${uci_all[@]}"; do
    [[ -f $f ]] || continue
    local secrets_found
    secrets_found=$(grep -inE "option[[:space:]]+.*(password|secret|key)[[:space:]]+'[^']+'" "$f" |
      grep -viE '(mesh_bssid|anygw_mac|mesh_key)')
    if [[ -z $secrets_found ]]; then
      qa_pass "no secrets in: ${f}"
    else
      qa_fail "potential secret in: ${f}"
      printf "       %s\n" "$secrets_found"
    fi
  done
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  run_uci_checks
  qa_summary
fi
