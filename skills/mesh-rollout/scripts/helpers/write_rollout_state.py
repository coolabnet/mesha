#!/usr/bin/env python3
"""Write or update the rollout-state.yaml file.

Usage:
    write_rollout_state.py <policy_file> <inventory_file> <rollout_id> \\
        <firmware_url> <status> <timestamp_field> <now> <state_file>
"""

import sys
import re
import os


def yaml_ts(val):
    """Return a quoted timestamp string or bare null."""
    if val in (None, 'null', ''):
        return 'null'
    return f'"{val}"'


def main():
    expected_args = 8
    if len(sys.argv) < expected_args + 1:
        print(
            f"Usage: write_rollout_state.py <policy_file> <inventory_file> "
            f"<rollout_id> <firmware_url> <status> <timestamp_field> <now> <state_file>",
            file=sys.stderr,
        )
        sys.exit(1)

    policy_path = sys.argv[1]
    inv_path = sys.argv[2]
    rollout_id = sys.argv[3]
    firmware_url = sys.argv[4]
    status = sys.argv[5]
    ts_field = sys.argv[6]
    now = sys.argv[7]
    state_path = sys.argv[8]

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
    started_at = existing_ts.get('started_at', (now if ts_field == 'started_at' else 'null'))
    completed_at = existing_ts.get('completed_at', (now if ts_field == 'completed_at' else 'null'))
    halted_at = existing_ts.get('halted_at', (now if ts_field == 'halted_at' else 'null'))
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
                        ring_nodes[cur_ring].append(nm.group(1).strip().strip("\"'"))

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
                cur_name = nm.group(1).strip().strip("\"'")
            hm = re.match(r'\s+hostname:\s*"?([^\s"]+)"?', line)
            if hm and cur_name:
                name_to_host[cur_name] = hm.group(1).strip().strip('"')

    # ------------------------------------------------------------------
    # Write state file
    # ------------------------------------------------------------------
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


if __name__ == "__main__":
    main()
