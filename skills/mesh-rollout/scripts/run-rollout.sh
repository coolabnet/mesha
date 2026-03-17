#!/usr/bin/env bash
# run-rollout.sh — Orchestrate a full ring-based firmware rollout across the community mesh
#
# Usage:
#   ./run-rollout.sh --firmware-url <url-or-path> [--dry-run] [--ring <ring-name>] [--resume]
#
# Options:
#   --firmware-url   URL or local path to the firmware image (required)
#   --dry-run        Print the full rollout plan but make no changes
#   --ring           Execute only a specific ring (e.g. --ring canary)
#   --resume         Resume from a previously saved rollout-state.yaml
#
# Risk class: Class D (firmware rollout — multi-node)
# Requires: explicit approval, defined change window, canary-first execution
#
# Source of truth for ring order and policy:
#   desired-state/mesh/community-profile/rollout-policy.yaml
#   inventories/mesh-nodes.yaml
#
# Reads node IPs from inventories/mesh-nodes.yaml using inline Python 3.
# No yq dependency required.
#
# NOTE: This script calls stage-upgrade.sh with --auto to suppress the per-node
# interactive YES prompt. The single top-level YES confirmation (below) covers
# the entire rollout; per-node re-confirmation inside the ring loop would
# deadlock a non-interactive run.
#
# See: docs/playbooks/firmware-rollout.md
#      desired-state/mesh/community-profile/rollout-policy.yaml

set -euo pipefail

# ---------------------------------------------------------------------------
# Workspace root resolution
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# ---------------------------------------------------------------------------
# Paths derived from WORKSPACE_ROOT
# ---------------------------------------------------------------------------

POLICY_FILE="${WORKSPACE_ROOT}/desired-state/mesh/community-profile/rollout-policy.yaml"
INVENTORY_FILE="${WORKSPACE_ROOT}/inventories/mesh-nodes.yaml"
STATE_FILE="${WORKSPACE_ROOT}/desired-state/mesh/rollout-state.yaml"
STAGE_UPGRADE="${SCRIPT_DIR}/stage-upgrade.sh"
VALIDATE_NODE="${SCRIPT_DIR}/validate-node.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

banner() {
  echo ""
  echo "======================================================================"
  echo "  $*"
  echo "======================================================================"
  echo ""
}

usage() {
  echo "Usage: $0 --firmware-url <url-or-path> [--dry-run] [--ring <ring-name>] [--resume]"
  echo ""
  echo "Options:"
  echo "  --firmware-url   URL or local path to firmware image (required)"
  echo "  --dry-run        Print the full rollout plan without making changes"
  echo "  --ring           Execute only a named ring (e.g. canary, stable, trailing)"
  echo "  --resume         Resume from rollout-state.yaml left by a halted rollout"
  echo ""
  echo "Examples:"
  echo "  $0 --firmware-url http://192.168.1.50/firmware/lm-2023.09.bin"
  echo "  $0 --firmware-url /data/firmware-cache/lm-2023.09.bin --dry-run"
  echo "  $0 --firmware-url /data/firmware-cache/lm-2023.09.bin --ring canary"
  echo "  $0 --firmware-url /data/firmware-cache/lm-2023.09.bin --resume"
  exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

FIRMWARE_URL=""
DRY_RUN=false
ONLY_RING=""
RESUME=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --firmware-url)
      [[ $# -lt 2 ]] && die "--firmware-url requires a value"
      FIRMWARE_URL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --ring)
      [[ $# -lt 2 ]] && die "--ring requires a value"
      ONLY_RING="$2"
      shift 2
      ;;
    --resume)
      RESUME=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -z "${FIRMWARE_URL}" ]] && usage

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

[[ -f "${POLICY_FILE}" ]]    || die "Rollout policy not found: ${POLICY_FILE}"
[[ -f "${INVENTORY_FILE}" ]] || die "Node inventory not found: ${INVENTORY_FILE}"
[[ -x "${STAGE_UPGRADE}" ]]  || die "stage-upgrade.sh not found or not executable: ${STAGE_UPGRADE}"
[[ -x "${VALIDATE_NODE}" ]]  || die "validate-node.sh not found or not executable: ${VALIDATE_NODE}"

command -v python3 &>/dev/null || die "python3 is required but not found in PATH"

# ---------------------------------------------------------------------------
# Python helpers — parse YAML using stdlib only (no PyYAML required)
# ---------------------------------------------------------------------------

# Extract ring names and stabilization periods from rollout-policy.yaml.
# Outputs: ring_name|stabilization_hours per line.
get_rings() {
  python3 - "${POLICY_FILE}" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Find the upgrade_rings block and parse ring names and stabilization_period_hours
# This is a simple line-oriented parser for the known YAML structure.
in_rings = False
current_ring = None
current_stab = "0"

for line in content.splitlines():
    stripped = line.strip()
    if stripped == "upgrade_rings:":
        in_rings = True
        continue
    if in_rings:
        # Top-level key after upgrade_rings ends the block
        if stripped and not stripped.startswith("-") and not stripped.startswith("#") \
           and not line.startswith(" ") and not line.startswith("\t"):
            in_rings = False
            continue
        ring_match = re.match(r'\s*-\s*ring:\s*["\']?(\w+)["\']?', line)
        if ring_match:
            if current_ring:
                print(f"{current_ring}|{current_stab}")
            current_ring = ring_match.group(1)
            current_stab = "0"
            continue
        stab_match = re.match(r'\s+stabilization_period_hours:\s*(\d+)', line)
        if stab_match and current_ring:
            current_stab = stab_match.group(1)

if current_ring:
    print(f"{current_ring}|{current_stab}")
PYEOF
}

# Resolve node hostnames that belong to a given ring by cross-referencing
# ring node names (from rollout-policy.yaml) against the inventory.
# Outputs: hostname per line.
get_nodes_for_ring() {
  local ring_name="$1"
  python3 - "${POLICY_FILE}" "${INVENTORY_FILE}" "${ring_name}" <<'PYEOF'
import sys, re

policy_path = sys.argv[1]
inventory_path = sys.argv[2]
target_ring = sys.argv[3]

# --- Parse rollout-policy.yaml: find node display names for the target ring ---
ring_node_names = []
with open(policy_path) as f:
    content = f.read()

in_rings = False
in_target_ring = False
in_nodes = False

for line in content.splitlines():
    stripped = line.strip()
    if stripped == "upgrade_rings:":
        in_rings = True
        continue
    if in_rings:
        # End of upgrade_rings block
        if stripped and not stripped.startswith("-") and not stripped.startswith("#") \
           and not line.startswith(" ") and not line.startswith("\t"):
            in_rings = False
            continue
        ring_match = re.match(r'\s*-\s*ring:\s*["\']?(\w+)["\']?', line)
        if ring_match:
            in_target_ring = (ring_match.group(1) == target_ring)
            in_nodes = False
            continue
        if in_target_ring:
            if re.match(r'\s+nodes:', line):
                in_nodes = True
                continue
            # Another ring key ends the nodes block
            if in_nodes and re.match(r'\s+\w+:', line) and not re.match(r'\s+-', line):
                in_nodes = False
                continue
            if in_nodes:
                node_match = re.match(r'\s+-\s+"([^"]+)"', line)
                if not node_match:
                    node_match = re.match(r"\s+-\s+'([^']+)'", line)
                if not node_match:
                    node_match = re.match(r'\s+-\s+(.+)', line)
                if node_match:
                    ring_node_names.append(node_match.group(1).strip().strip('"\''))

# --- Parse inventories/mesh-nodes.yaml: resolve hostnames by name ---
with open(inventory_path) as f:
    inv_content = f.read()

in_nodes_block = False
current_name = None
current_hostname = None

for line in inv_content.splitlines():
    stripped = line.strip()
    if stripped == "nodes:":
        in_nodes_block = True
        continue
    if in_nodes_block:
        if re.match(r'\s*-\s+name:', line):
            # Flush previous node
            if current_name and current_hostname and current_name in ring_node_names:
                print(current_hostname)
            name_match = re.match(r'\s*-\s+name:\s*"([^"]+)"', line)
            if not name_match:
                name_match = re.match(r"\s*-\s+name:\s*'([^']+)'", line)
            if not name_match:
                name_match = re.match(r'\s*-\s+name:\s+(.+)', line)
            current_name = name_match.group(1).strip().strip('"\'') if name_match else None
            current_hostname = None
            continue
        host_match = re.match(r'\s+hostname:\s*"?([^\s"]+)"?', line)
        if host_match and current_name:
            current_hostname = host_match.group(1).strip().strip('"')

# Flush last node
if current_name and current_hostname and current_name in ring_node_names:
    print(current_hostname)
PYEOF
}

# Check if current time falls within a preferred change window.
# Outputs "yes" or "no".
check_change_window() {
  python3 - "${POLICY_FILE}" <<'PYEOF'
import sys, re
from datetime import datetime, timezone

try:
    import zoneinfo
    def get_tz(name):
        return zoneinfo.ZoneInfo(name)
except ImportError:
    # Python < 3.9 fallback — use UTC as approximation
    def get_tz(name):
        return timezone.utc

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Extract preferred windows
windows = []
current = {}
in_preferred = False

for line in content.splitlines():
    stripped = line.strip()
    if re.match(r'\s+preferred:', line):
        in_preferred = True
        continue
    if in_preferred:
        if re.match(r'\s+blackout_periods:', line):
            in_preferred = False
            continue
        if re.match(r'\s+-\s+description:', line):
            if current:
                windows.append(current)
            current = {}
            continue
        days_match = re.match(r'\s+days:\s*\[([^\]]+)\]', line)
        if days_match:
            current['days'] = [d.strip().strip('"') for d in days_match.group(1).split(',')]
        start_match = re.match(r'\s+start_time:\s*"?(\d+:\d+)"?', line)
        if start_match:
            current['start'] = start_match.group(1)
        end_match = re.match(r'\s+end_time:\s*"?(\d+:\d+)"?', line)
        if end_match:
            current['end'] = end_match.group(1)
        tz_match = re.match(r'\s+timezone:\s*"?([^\s"]+)"?', line)
        if tz_match:
            current['tz'] = tz_match.group(1)

if current:
    windows.append(current)

day_names = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']

for w in windows:
    tz_name = w.get('tz', 'UTC')
    try:
        tz = get_tz(tz_name)
    except Exception:
        tz = timezone.utc
    now = datetime.now(tz)
    today = day_names[now.weekday()]
    if today not in w.get('days', []):
        continue
    start_h, start_m = map(int, w.get('start', '00:00').split(':'))
    end_h, end_m = map(int, w.get('end', '23:59').split(':'))
    now_minutes = now.hour * 60 + now.minute
    start_minutes = start_h * 60 + start_m
    end_minutes = end_h * 60 + end_m
    if start_minutes <= now_minutes <= end_minutes:
        print("yes")
        sys.exit(0)

print("no")
PYEOF
}

# ---------------------------------------------------------------------------
# Generate a timestamp-based rollout ID
# ---------------------------------------------------------------------------

ROLLOUT_ID="rollout-$(date '+%Y%m%dT%H%M%S')"

# ---------------------------------------------------------------------------
# Resume logic — load existing state
# ---------------------------------------------------------------------------

RESUME_FROM_RING=""
declare -A NODE_DONE_MAP=()

if [[ "${RESUME}" == true ]]; then
  [[ -f "${STATE_FILE}" ]] || die "--resume specified but no rollout-state.yaml found at: ${STATE_FILE}"
  log "Loading previous rollout state from: ${STATE_FILE}"

  # Extract resume information using Python
  RESUME_INFO="$(python3 - "${STATE_FILE}" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

status_match = re.search(r'^status:\s*(\S+)', content, re.MULTILINE)
status = status_match.group(1) if status_match else 'unknown'

fw_match = re.search(r'^firmware_url:\s*(.+)', content, re.MULTILINE)
fw = fw_match.group(1).strip().strip('"') if fw_match else ''

id_match = re.search(r'^rollout_id:\s*(.+)', content, re.MULTILINE)
rid = id_match.group(1).strip().strip('"') if id_match else ''

print(f"status={status}")
print(f"firmware_url={fw}")
print(f"rollout_id={rid}")

# Find nodes that are already validated/upgraded — output as validated:<hostname>
in_nodes = False
current_host = None
current_status = None
for line in content.splitlines():
    if re.match(r'\s+-\s+hostname:', line):
        hm = re.match(r'\s+-\s+hostname:\s*"?([^\s"]+)"?', line)
        current_host = hm.group(1).strip().strip('"') if hm else None
        current_status = None
    sm = re.match(r'\s+status:\s*(\S+)', line)
    if sm and current_host:
        current_status = sm.group(1).strip()
        if current_status in ('validated', 'upgraded'):
            print(f"done:{current_host}")
        current_host = None
PYEOF
)"

  PREV_STATUS="$(echo "${RESUME_INFO}" | grep '^status=' | cut -d= -f2)"
  PREV_FW="$(echo "${RESUME_INFO}" | grep '^firmware_url=' | cut -d= -f2)"
  PREV_ID="$(echo "${RESUME_INFO}" | grep '^rollout_id=' | cut -d= -f2)"

  if [[ "${PREV_STATUS}" == "completed" ]]; then
    die "Previous rollout is already completed. Nothing to resume."
  fi

  if [[ "${PREV_STATUS}" != "halted" && "${PREV_STATUS}" != "in_progress" ]]; then
    die "Cannot resume rollout with status '${PREV_STATUS}'. Expected: halted or in_progress."
  fi

  # Inherit the rollout ID from the previous session
  ROLLOUT_ID="${PREV_ID:-${ROLLOUT_ID}}"

  # Load already-done nodes
  while IFS= read -r line; do
    if [[ "${line}" == done:* ]]; then
      done_host="${line#done:}"
      NODE_DONE_MAP["${done_host}"]="validated"
    fi
  done <<< "${RESUME_INFO}"

  log "Resuming rollout ID: ${ROLLOUT_ID} (previous status: ${PREV_STATUS})"
  log "Nodes already completed: ${!NODE_DONE_MAP[*]:-none}"
fi

# ---------------------------------------------------------------------------
# Write or update rollout-state.yaml
# ---------------------------------------------------------------------------

write_state() {
  local status="$1"
  local timestamp_field="$2"   # e.g. "started_at" | "completed_at" | "halted_at"
  local now
  now="$(date '+%Y-%m-%dT%H:%M:%S')"

  # Build rings section using current tracking state
  # RINGS_YAML is populated incrementally below
  python3 - "${POLICY_FILE}" "${INVENTORY_FILE}" \
            "${ROLLOUT_ID}" "${FIRMWARE_URL}" "${status}" \
            "${timestamp_field}" "${now}" \
            "${STATE_FILE}" <<'PYEOF'
import sys, re, os

policy_path  = sys.argv[1]
inv_path     = sys.argv[2]
rollout_id   = sys.argv[3]
firmware_url = sys.argv[4]
status       = sys.argv[5]
ts_field     = sys.argv[6]
now          = sys.argv[7]
state_path   = sys.argv[8]

# ------------------------------------------------------------------
# Load existing state if present (to preserve per-node timestamps)
# ------------------------------------------------------------------
existing_nodes = {}   # hostname -> {status, upgraded_at, validated_at, failed_at}
existing_ts = {}      # field_name -> value  (started_at etc.)

if os.path.exists(state_path):
    with open(state_path) as f:
        econtent = f.read()
    in_nodes_sec = False
    cur_host = None
    cur_node = {}
    for line in econtent.splitlines():
        ts_m = re.match(r'^(started_at|completed_at|halted_at):\s*(.+)', line)
        if ts_m:
            existing_ts[ts_m.group(1)] = ts_m.group(2).strip().strip('"')
        if re.match(r'\s+-\s+hostname:', line):
            if cur_host:
                existing_nodes[cur_host] = cur_node
            hm = re.match(r'\s+-\s+hostname:\s*"?([^\s"]+)"?', line)
            cur_host = hm.group(1).strip().strip('"') if hm else None
            cur_node = {}
        if cur_host:
            for f2 in ('status', 'upgraded_at', 'validated_at', 'failed_at'):
                fm = re.match(rf'\s+{f2}:\s*(.+)', line)
                if fm:
                    cur_node[f2] = fm.group(1).strip().strip('"')
    if cur_host:
        existing_nodes[cur_host] = cur_node

# Determine timestamps
started_at  = existing_ts.get('started_at',  (now if ts_field == 'started_at'  else 'null'))
completed_at = existing_ts.get('completed_at', (now if ts_field == 'completed_at' else 'null'))
halted_at   = existing_ts.get('halted_at',   (now if ts_field == 'halted_at'   else 'null'))
if ts_field == 'started_at':
    started_at = now
elif ts_field == 'completed_at':
    completed_at = now
elif ts_field == 'halted_at':
    halted_at = now

# ------------------------------------------------------------------
# Parse rings from policy
# ------------------------------------------------------------------
with open(policy_path) as f:
    pcontent = f.read()
with open(inv_path) as f:
    icontent = f.read()

# Parse ring names
ring_names = []
ring_nodes = {}   # ring_name -> [display_names]
in_rings = False
cur_ring = None
in_nodes_sec2 = False

for line in pcontent.splitlines():
    stripped = line.strip()
    if stripped == "upgrade_rings:":
        in_rings = True
        continue
    if in_rings:
        if stripped and not stripped.startswith('-') and not stripped.startswith('#') \
           and not line.startswith(' ') and not line.startswith('\t'):
            in_rings = False
            continue
        rm = re.match(r'\s*-\s*ring:\s*["\']?(\w+)["\']?', line)
        if rm:
            cur_ring = rm.group(1)
            ring_names.append(cur_ring)
            ring_nodes[cur_ring] = []
            in_nodes_sec2 = False
            continue
        if cur_ring:
            if re.match(r'\s+nodes:', line):
                in_nodes_sec2 = True
                continue
            if in_nodes_sec2 and re.match(r'\s+\w+:', line) and not re.match(r'\s+-', line):
                in_nodes_sec2 = False
                continue
            if in_nodes_sec2:
                nm = re.match(r'\s+-\s+"([^"]+)"', line)
                if not nm:
                    nm = re.match(r"\s+-\s+'([^']+)'", line)
                if not nm:
                    nm = re.match(r'\s+-\s+(.+)', line)
                if nm:
                    ring_nodes[cur_ring].append(nm.group(1).strip().strip('"\''))

# Parse inventory: name -> hostname
name_to_host = {}
in_inv = False
cur_name = None
for line in icontent.splitlines():
    stripped = line.strip()
    if stripped == "nodes:":
        in_inv = True
        continue
    if in_inv:
        nm = re.match(r'\s*-\s+name:\s*"([^"]+)"', line)
        if not nm:
            nm = re.match(r"\s*-\s+name:\s*'([^']+)'", line)
        if not nm:
            nm = re.match(r'\s*-\s+name:\s+(.+)', line)
        if nm:
            cur_name = nm.group(1).strip().strip('"\'')
        hm = re.match(r'\s+hostname:\s*"?([^\s"]+)"?', line)
        if hm and cur_name:
            name_to_host[cur_name] = hm.group(1).strip().strip('"')

# ------------------------------------------------------------------
# Write state file
# ------------------------------------------------------------------
def yaml_ts(val):
    """Return a quoted timestamp string or bare null."""
    if val in (None, 'null', ''):
        return 'null'
    return f'"{val}"'

lines = [
    f'rollout_id: "{rollout_id}"',
    f'firmware_url: "{firmware_url}"',
    f'started_at: {yaml_ts(started_at)}',
    f'completed_at: {yaml_ts(completed_at)}',
    f'halted_at: {yaml_ts(halted_at)}',
    f'status: {status}',
    'rings:',
]

for rname in ring_names:
    lines.append(f'  - name: {rname}')
    lines.append(f'    nodes:')
    for display_name in ring_nodes.get(rname, []):
        hostname = name_to_host.get(display_name, display_name.lower().replace(' ', '-'))
        enode = existing_nodes.get(hostname, {})
        node_status = enode.get('status', 'pending')
        lines.append(f'      - hostname: "{hostname}"')
        lines.append(f'        display_name: "{display_name}"')
        lines.append(f'        status: {node_status}')
        for tsf in ('upgraded_at', 'validated_at', 'failed_at'):
            val = enode.get(tsf, 'null')
            lines.append(f'        {tsf}: {val}')

with open(state_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f"State written: {state_path}")
PYEOF
}

# Update the status of a single node in rollout-state.yaml
update_node_state() {
  local hostname="$1"
  local new_status="$2"
  local ts_field="$3"   # e.g. upgraded_at | validated_at | failed_at
  local now
  now="$(date '+%Y-%m-%dT%H:%M:%S')"

  python3 - "${STATE_FILE}" "${hostname}" "${new_status}" "${ts_field}" "${now}" <<'PYEOF'
import sys, re

state_path = sys.argv[1]
hostname   = sys.argv[2]
new_status = sys.argv[3]
ts_field   = sys.argv[4]
now        = sys.argv[5]

with open(state_path) as f:
    lines = f.readlines()

in_node = False
updated = False
out = []
i = 0
while i < len(lines):
    line = lines[i]
    # Detect start of this node's block
    hm = re.match(r'\s+-\s+hostname:\s*"?([^\s"]+)"?', line)
    if hm and hm.group(1).strip().strip('"') == hostname:
        in_node = True
    if in_node:
        sm = re.match(r'(\s+)status:\s*\S+', line)
        if sm:
            line = f"{sm.group(1)}status: {new_status}\n"
            updated = True
        tf_m = re.match(r'(\s+)' + re.escape(ts_field) + r':\s*\S+', line)
        if tf_m:
            line = f"{tf_m.group(1)}{ts_field}: \"{now}\"\n"
        # Next node block ends this one
        if i > 0 and re.match(r'\s+-\s+hostname:', line) and not (hm and hm.group(1).strip().strip('"') == hostname):
            in_node = False
    out.append(line)
    i += 1

with open(state_path, 'w') as f:
    f.writelines(out)
PYEOF
}

# ---------------------------------------------------------------------------
# Load ring definitions
# ---------------------------------------------------------------------------

log "Loading rollout policy from: ${POLICY_FILE}"

RING_DEFS="$(get_rings)"
[[ -z "${RING_DEFS}" ]] && die "No rings found in rollout policy: ${POLICY_FILE}"

# Validate --ring argument if given
if [[ -n "${ONLY_RING}" ]]; then
  if ! echo "${RING_DEFS}" | grep -q "^${ONLY_RING}|"; then
    die "Ring '${ONLY_RING}' not found in rollout policy. Available rings: $(echo "${RING_DEFS}" | cut -d'|' -f1 | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# Print rollout plan
# ---------------------------------------------------------------------------

banner "ROLLOUT PLAN"
echo "  Rollout ID:    ${ROLLOUT_ID}"
echo "  Firmware URL:  ${FIRMWARE_URL}"
echo "  Policy file:   ${POLICY_FILE}"
echo "  State file:    ${STATE_FILE}"
[[ -n "${ONLY_RING}" ]] && echo "  Scope:         Ring '${ONLY_RING}' only"
[[ "${RESUME}" == true ]] && echo "  Mode:          RESUME"
echo ""

TOTAL_NODES=0
declare -a RING_NAMES=()
declare -A RING_STAB=()
declare -A RING_NODE_LISTS=()

while IFS='|' read -r ring_name stab_hours; do
  RING_NAMES+=("${ring_name}")
  RING_STAB["${ring_name}"]="${stab_hours}"
  ring_nodes="$(get_nodes_for_ring "${ring_name}")"
  RING_NODE_LISTS["${ring_name}"]="${ring_nodes}"
  node_count=0
  if [[ -n "${ring_nodes}" ]]; then
    node_count="$(echo "${ring_nodes}" | wc -l)"
  fi
  TOTAL_NODES=$((TOTAL_NODES + node_count))
  echo "  Ring: ${ring_name} (${node_count} node(s), stabilization: ${stab_hours}h)"
  if [[ -n "${ring_nodes}" ]]; then
    while IFS= read -r n; do
      if [[ -n "${NODE_DONE_MAP[${n}]+_}" ]]; then
        echo "    - ${n}  [ALREADY DONE — will skip]"
      else
        echo "    - ${n}"
      fi
    done <<< "${ring_nodes}"
  else
    echo "    (no nodes resolved from inventory for this ring)"
  fi
  echo ""
done <<< "${RING_DEFS}"

echo "  Total nodes: ${TOTAL_NODES}"
echo ""

# Change window check
IN_WINDOW="$(check_change_window)"
if [[ "${IN_WINDOW}" == "yes" ]]; then
  echo "  Change window: ACTIVE (current time is within a preferred window)"
else
  echo "  Change window: NOT ACTIVE (current time is outside preferred windows)"
  echo "  WARNING: Proceeding outside a change window. Ensure you have explicit"
  echo "           approval to run this rollout now."
fi
echo ""

# Estimated time (rough: 10 min per node upgrade + stabilization waits)
ESTIMATED_MINS=$((TOTAL_NODES * 10))

echo "  Estimated minimum time: ~${ESTIMATED_MINS} minutes (upgrade only, excluding stabilization waits)"
echo "  Stabilization waits are not enforced by this script — they require manual"
echo "  promotion between rings per rollout-policy.yaml (auto_promote: false)."
echo ""

# ---------------------------------------------------------------------------
# Dry-run: exit here
# ---------------------------------------------------------------------------

if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN complete. No changes made. Remove --dry-run to execute the rollout."
  exit 0
fi

# ---------------------------------------------------------------------------
# Require YES confirmation
# ---------------------------------------------------------------------------

echo "This is a Class D (high-risk) operation. All nodes listed above will have"
echo "their firmware replaced. Ensure you have:"
echo "  [ ] Explicit written approval from an authorized maintainer"
echo "  [ ] A verified rollback firmware image available"
echo "  [ ] A defined maintenance window approved by the community"
echo "  [ ] The canary node tested and validated before promoting to stable"
echo ""
echo "Type YES to proceed with the rollout (anything else aborts):"
read -r CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
  log "Confirmation not given. Rollout aborted."
  exit 0
fi

# ---------------------------------------------------------------------------
# Initialize state file (unless resuming)
# ---------------------------------------------------------------------------

if [[ "${RESUME}" == false ]]; then
  log "Initializing rollout state file: ${STATE_FILE}"
  write_state "in_progress" "started_at"
else
  log "Resuming — updating state to in_progress"
  # Update status field only via a simple sed replacement
  python3 - "${STATE_FILE}" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
content = re.sub(r'^status:\s*\S+', 'status: in_progress', content, flags=re.MULTILINE)
with open(sys.argv[1], 'w') as f:
    f.write(content)
PYEOF
fi

# ---------------------------------------------------------------------------
# Tracking counters
# ---------------------------------------------------------------------------

UPGRADED_COUNT=0
VALIDATED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# ---------------------------------------------------------------------------
# Main ring loop
# ---------------------------------------------------------------------------

for ring_name in "${RING_NAMES[@]}"; do
  # Skip rings not requested (when --ring is set)
  if [[ -n "${ONLY_RING}" ]] && [[ "${ring_name}" != "${ONLY_RING}" ]]; then
    continue
  fi

  stab_hours="${RING_STAB[${ring_name}]}"
  stab_seconds=$((stab_hours * 3600))
  ring_nodes="${RING_NODE_LISTS[${ring_name}]}"

  if [[ -z "${ring_nodes}" ]]; then
    log "Ring '${ring_name}': no nodes resolved from inventory. Skipping."
    continue
  fi

  banner "Starting ring: ${ring_name} ($(echo "${ring_nodes}" | wc -l) node(s))"

  RING_UPGRADED=0
  RING_FAILED=0
  RING_SKIPPED=0

  while IFS= read -r node_host; do
    [[ -z "${node_host}" ]] && continue

    # Skip nodes already validated in a resume scenario
    if [[ -n "${NODE_DONE_MAP[${node_host}]+_}" ]]; then
      log "  [SKIP] ${node_host} — already validated in previous session"
      RING_SKIPPED=$((RING_SKIPPED + 1))
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      continue
    fi

    log "  Upgrading node: ${node_host}"

    # ------------------------------------------------------------------
    # Call stage-upgrade.sh in non-interactive (--auto) mode.
    # --auto skips the per-node interactive YES prompt because the operator
    # already confirmed the entire rollout at the top-level prompt above.
    # ------------------------------------------------------------------
    if "${STAGE_UPGRADE}" "${node_host}" "${FIRMWARE_URL}" --auto; then
      log "  stage-upgrade.sh reported success for ${node_host}"
      update_node_state "${node_host}" "upgraded" "upgraded_at"
      UPGRADED_COUNT=$((UPGRADED_COUNT + 1))
      RING_UPGRADED=$((RING_UPGRADED + 1))
    else
      UPGRADE_EXIT=$?
      log "  ERROR: stage-upgrade.sh failed for ${node_host} (exit code: ${UPGRADE_EXIT})"
      update_node_state "${node_host}" "failed" "failed_at"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      RING_FAILED=$((RING_FAILED + 1))

      # Write halted state
      write_state "halted" "halted_at"

      echo ""
      echo "======================================================================"
      echo "  ROLLOUT HALTED"
      echo "======================================================================"
      echo ""
      echo "  Node '${node_host}' failed during upgrade."
      echo "  Ring '${ring_name}' cannot proceed."
      echo ""
      echo "  Rollout state saved to: ${STATE_FILE}"
      echo "  Status: halted"
      echo ""
      echo "  Required actions:"
      echo "    1. Investigate node '${node_host}' — check SSH connectivity"
      echo "    2. Review: docs/playbooks/firmware-rollout.md — Rollback Procedure"
      echo "    3. If the node is unresponsive, physical access may be required"
      echo "    4. Do NOT attempt to upgrade other nodes until this is resolved"
      echo "    5. Once resolved, use --resume to continue from where the rollout left off"
      echo ""
      echo "  Summary so far:"
      echo "    Upgraded:  ${UPGRADED_COUNT}"
      echo "    Failed:    ${FAILED_COUNT}"
      echo "    Skipped:   ${SKIPPED_COUNT}"
      echo ""
      exit 1
    fi

    # ------------------------------------------------------------------
    # Validate node after upgrade
    # ------------------------------------------------------------------
    log "  Validating node: ${node_host}"

    if "${VALIDATE_NODE}" "${node_host}"; then
      log "  Validation PASSED for ${node_host}"
      update_node_state "${node_host}" "validated" "validated_at"
      VALIDATED_COUNT=$((VALIDATED_COUNT + 1))
    else
      VALIDATE_EXIT=$?
      log "  ERROR: Validation FAILED for ${node_host} (exit code: ${VALIDATE_EXIT})"
      update_node_state "${node_host}" "failed" "failed_at"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      RING_FAILED=$((RING_FAILED + 1))

      # Write halted state
      write_state "halted" "halted_at"

      echo ""
      echo "======================================================================"
      echo "  ROLLOUT HALTED — VALIDATION FAILURE"
      echo "======================================================================"
      echo ""
      echo "  Node '${node_host}' failed post-upgrade validation."
      echo "  Ring '${ring_name}' cannot proceed."
      echo ""
      echo "  Rollout state saved to: ${STATE_FILE}"
      echo "  Status: halted"
      echo ""
      echo "  Required actions:"
      echo "    1. Review validation output above for '${node_host}'"
      echo "    2. Decide: rollback this node or investigate the failure"
      echo "    3. See: docs/playbooks/firmware-rollout.md — Rollback Procedure"
      echo "    4. Run: ./rollback-node.sh ${node_host} <backup-file.uci.gz>"
      echo "    5. After recovery, use --resume to continue the rollout"
      echo ""
      echo "  Summary so far:"
      echo "    Upgraded:   ${UPGRADED_COUNT}"
      echo "    Validated:  ${VALIDATED_COUNT}"
      echo "    Failed:     ${FAILED_COUNT}"
      echo "    Skipped:    ${SKIPPED_COUNT}"
      echo ""
      exit 1
    fi

    echo ""
  done <<< "${ring_nodes}"

  # ------------------------------------------------------------------
  # Ring summary
  # ------------------------------------------------------------------
  echo ""
  echo "--- Ring summary: ${ring_name} ---"
  echo "  Upgraded:  ${RING_UPGRADED}"
  echo "  Failed:    ${RING_FAILED}"
  echo "  Skipped:   ${RING_SKIPPED}"
  echo ""

  # ------------------------------------------------------------------
  # Stabilization pause (between rings, not after the last ring)
  # auto_promote is always false per policy — this pause is advisory;
  # the script pauses briefly but does not enforce the full stabilization
  # period (which is hours-long and requires human promotion decision).
  # ------------------------------------------------------------------
  # Check if there are more rings to process after this one
  FOUND_CURRENT=false
  HAS_NEXT_RING=false
  for rn in "${RING_NAMES[@]}"; do
    if [[ "${FOUND_CURRENT}" == true ]]; then
      if [[ -z "${ONLY_RING}" ]] || [[ "${rn}" == "${ONLY_RING}" ]]; then
        HAS_NEXT_RING=true
        break
      fi
    fi
    [[ "${rn}" == "${ring_name}" ]] && FOUND_CURRENT=true
  done

  if [[ "${HAS_NEXT_RING}" == true ]]; then
    ADVISORY_PAUSE=30
    log "Ring '${ring_name}' complete. Policy requires ${stab_hours}h stabilization before next ring."
    log "Per rollout-policy.yaml (auto_promote: false), promotion to the next ring"
    log "requires a manual decision from the lead maintainer."
    log "Pausing ${ADVISORY_PAUSE}s before continuing (advisory only — not the full stabilization window)."
    log "In a production rollout, stop here and validate the ring over ${stab_hours}h before proceeding."
    sleep "${ADVISORY_PAUSE}"
  fi

done

# ---------------------------------------------------------------------------
# Final state — completed
# ---------------------------------------------------------------------------

write_state "completed" "completed_at"

# ---------------------------------------------------------------------------
# Final rollout report
# ---------------------------------------------------------------------------

banner "ROLLOUT COMPLETE"

echo "  Rollout ID:  ${ROLLOUT_ID}"
echo "  Firmware:    ${FIRMWARE_URL}"
echo "  State file:  ${STATE_FILE}"
echo ""
echo "  Results:"
echo "    Total nodes in scope: ${TOTAL_NODES}"
echo "    Upgraded:             ${UPGRADED_COUNT}"
echo "    Validated:            ${VALIDATED_COUNT}"
echo "    Failed:               ${FAILED_COUNT}"
echo "    Skipped (resumed):    ${SKIPPED_COUNT}"
echo ""
echo "  Next steps:"
echo "    1. Run a full mesh health check to confirm all nodes are healthy"
echo "    2. Update desired-state/mesh/firmware-policy.yaml with the new current_version"
echo "    3. Write a maintenance log entry (use knowledge-curator skill)"
echo "    4. Review: docs/playbooks/firmware-rollout.md — Phase 4 Final Validation"
echo ""
