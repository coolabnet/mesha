#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
# schedule-maintenance.sh — Create and manage scheduled maintenance windows
#
# Usage:
#   ./schedule-maintenance.sh add --date "YYYY-MM-DD HH:MM" --duration <Nh|Nm> \
#       --scope <scope> --description "<text>" [--created-by <username>]
#   ./schedule-maintenance.sh list
#   ./schedule-maintenance.sh cancel <window-id>
#   ./schedule-maintenance.sh check
#
# Subcommands:
#   add      Schedule a new maintenance window (Class B — write, creates an entry)
#   list     Show all upcoming and recent windows (Class A — read-only)
#   cancel   Cancel a scheduled window by ID (Class B — write, marks as cancelled)
#   check    Exit 0 if a maintenance window is currently active, 1 if not (Class A — read-only)
#
# Risk classes:
#   add, cancel  — Class B (low-risk write: scheduling metadata only, no infrastructure change)
#   list, check  — Class A (read-only)
#
# Windows are stored in: desired-state/mesh/maintenance-windows.yaml
#
# See: desired-state/mesh/community-profile/rollout-policy.yaml — change_windows
#      TOOLS.md — Class B approval requirements

set -euo pipefail

# ---------------------------------------------------------------------------
# Workspace root resolution
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

WINDOWS_FILE="${WORKSPACE_ROOT}/desired-state/mesh/maintenance-windows.yaml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $0 add --date "YYYY-MM-DD HH:MM" --duration <Nh|Nm> \\
         --scope <scope> --description "<text>" [--created-by <username>]
  $0 list
  $0 cancel <window-id>
  $0 check

Subcommands:
  add      Schedule a new maintenance window
           --date         Required. Start date/time in "YYYY-MM-DD HH:MM" format
           --duration     Required. Duration as Nh (hours) or Nm (minutes), e.g. 2h, 90m
           --scope        Required. Scope of the window: "ring:canary", "ring:stable",
                          "ring:trailing", "node:<hostname>", or "all"
           --description  Required. Human-readable description of the planned work
           --created-by   Optional. Username of the maintainer scheduling the window
                          (defaults to current shell user)

  list     Show all maintenance windows (upcoming, active, and recent completed/cancelled)

  cancel   Cancel a scheduled maintenance window
           <window-id>    The window ID to cancel (shown in 'list' output)

  check    Check whether a maintenance window is currently active
           Exits 0 (zero) if a window is active right now
           Exits 1 (one) if no window is currently active

Examples:
  $0 add --date "2026-03-16 22:00" --duration 2h \\
         --scope "ring:stable" --description "Firmware upgrade ring 2"
  $0 list
  $0 cancel maint-20260316T220000
  $0 check && echo "In maintenance window" || echo "Not in maintenance window"
EOF
  exit 1
}

# ---------------------------------------------------------------------------
# Ensure the windows file exists with a minimal valid header
# ---------------------------------------------------------------------------

ensure_windows_file() {
  if [[ ! -f ${WINDOWS_FILE} ]]; then
    mkdir -p "$(dirname "${WINDOWS_FILE}")"
    cat >"${WINDOWS_FILE}" <<'YAML'
# desired-state/mesh/maintenance-windows.yaml
# Managed by: skills/mesh-rollout/scripts/schedule-maintenance.sh
# Do not edit manually while an add or cancel operation is in progress.
maintenance_windows: []
YAML
    log "Created new maintenance windows file: ${WINDOWS_FILE}"
  fi
}

# ---------------------------------------------------------------------------
# Parse duration string (e.g. "2h", "90m") to minutes
# ---------------------------------------------------------------------------

parse_duration_minutes() {
  local dur="$1"
  if [[ ${dur} =~ ^([0-9]+)h$ ]]; then
    echo $((BASH_REMATCH[1] * 60))
  elif [[ ${dur} =~ ^([0-9]+)m$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    die "Invalid duration format '${dur}'. Use Nh (hours) or Nm (minutes), e.g. 2h or 90m"
  fi
}

# Generate a deterministic window ID from the scheduled date
make_window_id() {
  local date_str="$1"
  # Convert "YYYY-MM-DD HH:MM" to "maint-YYYYMMDDTHHMMz"
  local slug
  slug="$(echo "${date_str}" | tr -d ' :-' | tr ' ' 'T')"
  echo "maint-${slug}"
}

# ---------------------------------------------------------------------------
# Subcommand: add
# ---------------------------------------------------------------------------

cmd_add() {
  local scheduled_date=""
  local duration_raw=""
  local scope=""
  local description=""
  local created_by
  created_by="${USER:-unknown}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --date)
      [[ $# -lt 2 ]] && die "--date requires a value"
      scheduled_date="$2"
      shift 2
      ;;
    --duration)
      [[ $# -lt 2 ]] && die "--duration requires a value"
      duration_raw="$2"
      shift 2
      ;;
    --scope)
      [[ $# -lt 2 ]] && die "--scope requires a value"
      scope="$2"
      shift 2
      ;;
    --description)
      [[ $# -lt 2 ]] && die "--description requires a value"
      description="$2"
      shift 2
      ;;
    --created-by)
      [[ $# -lt 2 ]] && die "--created-by requires a value"
      created_by="$2"
      shift 2
      ;;
    *)
      die "Unknown argument for add: $1"
      ;;
    esac
  done

  [[ -z ${scheduled_date} ]] && die "--date is required"
  [[ -z ${duration_raw} ]] && die "--duration is required"
  [[ -z ${scope} ]] && die "--scope is required"
  [[ -z ${description} ]] && die "--description is required"

  # Validate date format
  if ! echo "${scheduled_date}" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'; then
    die "Invalid date format '${scheduled_date}'. Expected: YYYY-MM-DD HH:MM"
  fi

  # Validate scope
  if ! echo "${scope}" | grep -qE '^(ring:(canary|stable|trailing)|node:[a-z0-9_-]+|all)$'; then
    die "Invalid scope '${scope}'. Expected: ring:<name>, node:<hostname>, or all"
  fi

  DURATION_MINUTES="$(parse_duration_minutes "${duration_raw}")"
  WINDOW_ID="$(make_window_id "${scheduled_date// /T}")"

  ensure_windows_file

  # Check for duplicate ID
  if grep -q "id: \"${WINDOW_ID}\"" "${WINDOWS_FILE}" 2>/dev/null; then
    die "A window with ID '${WINDOW_ID}' already exists. Use a different date/time."
  fi

  # Append new window using Python to maintain clean YAML formatting
  python3 - "${WINDOWS_FILE}" "${WINDOW_ID}" "${scheduled_date}" \
    "${DURATION_MINUTES}" "${scope}" "${description}" \
    "${created_by}" <<'PYEOF'
import sys, re
from datetime import datetime

windows_path = sys.argv[1]
window_id    = sys.argv[2]
scheduled_at = sys.argv[3]
duration_min = sys.argv[4]
scope        = sys.argv[5]
description  = sys.argv[6]
created_by   = sys.argv[7]
now          = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')

with open(windows_path) as f:
    content = f.read()

new_entry = f"""  - id: "{window_id}"
    scheduled_at: "{scheduled_at}"
    duration_minutes: {duration_min}
    scope: "{scope}"
    description: "{description}"
    created_by: "{created_by}"
    created_at: "{now}"
    status: scheduled
    notes: null
"""

# Insert after 'maintenance_windows:' line or before closing empty list
if 'maintenance_windows: []' in content:
    content = content.replace(
        'maintenance_windows: []',
        'maintenance_windows:\n' + new_entry
    )
elif 'maintenance_windows:' in content:
    content = content.rstrip() + '\n' + new_entry + '\n'
else:
    content = content.rstrip() + '\nmaintenance_windows:\n' + new_entry + '\n'

with open(windows_path, 'w') as f:
    f.write(content)
PYEOF

  log "Maintenance window scheduled:"
  log "  ID:          ${WINDOW_ID}"
  log "  Start:       ${scheduled_date}"
  log "  Duration:    ${DURATION_MINUTES} minutes"
  log "  Scope:       ${scope}"
  log "  Description: ${description}"
  log "  Created by:  ${created_by}"
  log "  File:        ${WINDOWS_FILE}"
  echo ""
  echo "Window '${WINDOW_ID}' added to ${WINDOWS_FILE}"
}

# ---------------------------------------------------------------------------
# Subcommand: list
# ---------------------------------------------------------------------------

cmd_list() {
  ensure_windows_file

  python3 - "${WINDOWS_FILE}" <<'PYEOF'
import sys, re
from datetime import datetime

windows_path = sys.argv[1]

with open(windows_path) as f:
    content = f.read()

now = datetime.now()

# Parse windows from the YAML manually.
# Each entry starts with "  - id: <value>" (id is always the first field).
windows = []
current = {}
in_windows = False

for line in content.splitlines():
    stripped = line.strip()
    if stripped == 'maintenance_windows: []':
        break
    if stripped == 'maintenance_windows:':
        in_windows = True
        continue
    if not in_windows:
        continue
    # Entry boundary: a list item whose first field is id
    idm = re.match(r'\s*-\s+id:\s*(.*)', line)
    if idm:
        if current:
            windows.append(current)
        val = idm.group(1).strip().strip('"').strip("'")
        current = {'id': None if val in ('null', '') else val}
        continue
    # Other fields within an entry
    for field in ('scheduled_at', 'scope', 'description', 'created_by',
                  'status', 'notes', 'created_at'):
        fm = re.match(rf'\s+{field}:\s*(.*)', line)
        if fm:
            val = fm.group(1).strip().strip('"').strip("'")
            current[field] = None if val in ('null', '') else val
    dm = re.match(r'\s+duration_minutes:\s*(\d+)', line)
    if dm:
        current['duration_minutes'] = int(dm.group(1))

if current:
    windows.append(current)

if not windows:
    print("No maintenance windows found.")
    sys.exit(0)

# Sort by scheduled_at
def parse_dt(w):
    try:
        return datetime.strptime(w.get('scheduled_at', ''), '%Y-%m-%d %H:%M')
    except Exception:
        return datetime.min

windows.sort(key=parse_dt)

print(f"{'ID':<35}  {'Scheduled At':<18}  {'Dur':>5}m  {'Scope':<20}  {'Status':<12}  Description")
print("-" * 120)

for w in windows:
    wid        = w.get('id', '?')
    sched      = w.get('scheduled_at', '?')
    dur        = w.get('duration_minutes', '?')
    scope      = w.get('scope', '?')
    status     = w.get('status', '?')
    desc       = (w.get('description') or '')[:45]

    # Mark currently active windows
    try:
        start_dt = datetime.strptime(sched, '%Y-%m-%d %H:%M')
        from datetime import timedelta
        end_dt = start_dt + timedelta(minutes=int(dur))
        if start_dt <= now <= end_dt and status == 'scheduled':
            status = 'ACTIVE NOW'
    except Exception:
        pass

    print(f"{wid:<35}  {sched:<18}  {dur:>5}   {scope:<20}  {status:<12}  {desc}")
PYEOF
}

# ---------------------------------------------------------------------------
# Subcommand: cancel
# ---------------------------------------------------------------------------

cmd_cancel() {
  [[ $# -lt 1 ]] && die "cancel requires a window ID argument"
  local window_id="$1"

  ensure_windows_file

  # Check the window exists and is in a cancellable state
  FOUND="$(
    python3 - "${WINDOWS_FILE}" "${window_id}" <<'PYEOF'
import sys, re

path = sys.argv[1]
target_id = sys.argv[2]

with open(path) as f:
    content = f.read()

in_window = False
found_status = None
in_windows = False

for line in content.splitlines():
    stripped = line.strip()
    if stripped == 'maintenance_windows:':
        in_windows = True
        continue
    if not in_windows:
        continue
    # Entry boundary
    idm = re.match(r'\s*-\s+id:\s*(.*)', line)
    if idm:
        val = idm.group(1).strip().strip('"').strip("'")
        in_window = (val == target_id)
        continue
    if in_window:
        sm = re.match(r'\s+status:\s*(\S+)', line)
        if sm:
            found_status = sm.group(1).strip()

if found_status is None:
    print("NOT_FOUND")
else:
    print(found_status)
PYEOF
  )"

  case "${FOUND}" in
  NOT_FOUND)
    die "Window ID '${window_id}' not found in ${WINDOWS_FILE}"
    ;;
  cancelled)
    die "Window '${window_id}' is already cancelled."
    ;;
  completed)
    die "Window '${window_id}' has already completed and cannot be cancelled."
    ;;
  esac

  # Update status to cancelled and add cancelled_at timestamp
  python3 - "${WINDOWS_FILE}" "${window_id}" <<'PYEOF'
import sys, re
from datetime import datetime

path      = sys.argv[1]
target_id = sys.argv[2]
now       = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')

with open(path) as f:
    lines = f.readlines()

in_target = False
out = []
for line in lines:
    idm = re.match(r'\s+-\s+id:\s*"?([^\s"]+)"?', line)
    if idm:
        in_target = (idm.group(1) == target_id)
    if in_target:
        sm = re.match(r'(\s+)status:\s*\S+', line)
        if sm:
            line = f"{sm.group(1)}status: cancelled\n"
            # Insert cancelled_at after this line
            out.append(line)
            out.append(f"{sm.group(1)}cancelled_at: \"{now}\"\n")
            continue
    out.append(line)

with open(path, 'w') as f:
    f.writelines(out)
PYEOF

  log "Maintenance window '${window_id}' has been cancelled."
  echo "Window '${window_id}' marked as cancelled in ${WINDOWS_FILE}"
}

# ---------------------------------------------------------------------------
# Subcommand: check
# ---------------------------------------------------------------------------

cmd_check() {
  # Class A — read-only
  # Exit 0 if a window is currently active, 1 if not.

  if [[ ! -f ${WINDOWS_FILE} ]]; then
    # No windows file = no active window
    exit 1
  fi

  ACTIVE="$(
    python3 - "${WINDOWS_FILE}" <<'PYEOF'
import sys, re
from datetime import datetime, timedelta

path = sys.argv[1]
now = datetime.now()

with open(path) as f:
    content = f.read()

in_windows = False
current = {}

def check_active(w):
    if w.get('status') != 'scheduled':
        return False
    sched = w.get('scheduled_at')
    dur   = w.get('duration_minutes', 0)
    if not sched:
        return False
    try:
        start = datetime.strptime(sched, '%Y-%m-%d %H:%M')
        end   = start + timedelta(minutes=int(dur))
        return start <= now <= end
    except Exception:
        return False

for line in content.splitlines():
    stripped = line.strip()
    if stripped == 'maintenance_windows: []':
        break
    if stripped == 'maintenance_windows:':
        in_windows = True
        continue
    if not in_windows:
        continue
    # Entry boundary: list item whose first field is id
    idm = re.match(r'\s*-\s+id:\s*(.*)', line)
    if idm:
        if current and check_active(current):
            print(current.get('id', 'unknown'))
            sys.exit(0)
        val = idm.group(1).strip().strip('"').strip("'")
        current = {'id': None if val in ('null', '') else val}
        continue
    for field in ('scheduled_at', 'status'):
        fm = re.match(rf'\s+{field}:\s*(.*)', line)
        if fm:
            val = fm.group(1).strip().strip('"').strip("'")
            current[field] = None if val in ('null', '') else val
    dm = re.match(r'\s+duration_minutes:\s*(\d+)', line)
    if dm:
        current['duration_minutes'] = int(dm.group(1))

if current and check_active(current):
    print(current.get('id', 'unknown'))
    sys.exit(0)

print("none")
sys.exit(1)
PYEOF
  )" || true

  if [[ ${ACTIVE} != "none" ]] && [[ -n ${ACTIVE} ]]; then
    echo "Active maintenance window: ${ACTIVE}"
    exit 0
  else
    echo "No active maintenance window."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------

[[ $# -lt 1 ]] && usage

SUBCOMMAND="$1"
shift

case "${SUBCOMMAND}" in
add)
  cmd_add "$@"
  ;;
list)
  cmd_list "$@"
  ;;
cancel)
  cmd_cancel "$@"
  ;;
check)
  cmd_check "$@"
  ;;
-h | --help)
  usage
  ;;
*)
  die "Unknown subcommand '${SUBCOMMAND}'. Expected: add, list, cancel, check"
  ;;
esac
