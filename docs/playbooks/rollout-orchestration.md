# Rollout Orchestration Playbook

**Purpose:** How to run a full firmware or configuration rollout using the mesh-rollout scripts. Covers the complete lifecycle from pre-flight checks through post-rollout validation.

**Risk class:** Class D — requires explicit approval, a maintenance window, canary testing, and rollback preparation.

This playbook is the operational guide for using the orchestration scripts. For background on the ring structure and rollout policy, see `docs/playbooks/firmware-rollout.md`. For scheduling and communicating the maintenance window, see `docs/playbooks/maintenance-window.md`.

Do not run a live rollout without completing the dry run first.

---

## 1. Pre-rollout checklist

Complete every item on this checklist before touching any node. Skip nothing.

### Firmware and image

- [ ] Target firmware version is documented in `desired-state/mesh/firmware-policy.yaml`
- [ ] Firmware image downloaded for each hardware model in the rollout
- [ ] SHA-256 checksum verified against the official firmware project checksum
- [ ] Rollback firmware image is available and its checksum verified
- [ ] Both images stored in a location accessible during the rollout (e.g., `./backups/firmware/`)

### Change window and approval

- [ ] Maintenance window scheduled per `docs/playbooks/maintenance-window.md`
- [ ] Window falls within a preferred change window (Sunday 05h–08h or weeknight 22h–23h30)
- [ ] No blackout period conflicts (school exams, community assembly Thursday 18h30–22h30, public holidays)
- [ ] Community group notified at least 24 hours in advance
- [ ] Affected site contacts notified directly (check `docs/sites/` for contacts and hours)
- [ ] Written approval received from lead maintainer via DM
- [ ] Approval message text copied into draft maintenance log entry

### Rollout policy

- [ ] Upgrade rings confirmed in `desired-state/mesh/community-profile/rollout-policy.yaml`
- [ ] Canary node identified (must be non-critical, low impact if it fails)
- [ ] Rollout order confirmed: canary → stable → trailing
- [ ] Stabilization periods noted: canary 24h, stable 48h, trailing 72h

### Network state

- [ ] Pre-rollout drift check run (`check-drift.sh`) and output saved
- [ ] No nodes already offline that are not expected to be offline
- [ ] No active incident in progress
- [ ] Canary node is reachable and healthy

---

## 2. Running the rollout

### Step 1 — Run the dry run first

Always run with `--dry-run` before executing live. The dry run shows you exactly what the script would do without making any changes.

```bash
./skills/mesh-rollout/scripts/run-rollout.sh \
  --firmware desired-state/mesh/firmware-policy.yaml \
  --ring canary \
  --dry-run
```

Review the output carefully:
- Which nodes will be affected
- In what order
- What commands would be sent to each node
- What validation checks will be performed after each node

If the dry run output does not match your expectations, stop. Do not proceed until you understand why.

Repeat the dry run for each ring:
```bash
./skills/mesh-rollout/scripts/run-rollout.sh --ring stable --dry-run
./skills/mesh-rollout/scripts/run-rollout.sh --ring trailing --dry-run
```

### Step 2 — Start the live rollout (canary only)

After confirming the dry run looks correct, start with the canary ring only:

```bash
./skills/mesh-rollout/scripts/run-rollout.sh \
  --firmware desired-state/mesh/firmware-policy.yaml \
  --ring canary
```

The script will:
1. Back up the canary node's UCI config
2. Transfer the firmware image to the node
3. Run `sysupgrade`
4. Wait for the node to come back up
5. Run post-upgrade validation checks
6. Write a stage report to `logs/maintenance/`
7. Update the rollout state in `desired-state/mesh/rollout-state.yaml`

**Do not start the stable ring until you have manually reviewed the canary result** and confirmed stabilization. The canary stabilization period is 24 hours by policy.

### Step 3 — Promote to stable ring (manual step)

After the canary has been stable for 24 hours, review and promote:

```bash
# Check canary stabilization status
cat desired-state/mesh/rollout-state.yaml

# If canary is confirmed stable, promote to stable ring
./skills/mesh-rollout/scripts/run-rollout.sh \
  --firmware desired-state/mesh/firmware-policy.yaml \
  --ring stable
```

Wait for the stable ring to complete and stabilize (48 hours by policy).

### Step 4 — Promote to trailing ring (manual step)

After the stable ring has been stable for 48 hours:

```bash
./skills/mesh-rollout/scripts/run-rollout.sh \
  --firmware desired-state/mesh/firmware-policy.yaml \
  --ring trailing
```

The trailing ring always requires human review before each node. The script will pause and prompt for confirmation before upgrading each node in this ring.

---

## 3. Monitoring the rollout

### Reading rollout-state.yaml

The script maintains `desired-state/mesh/rollout-state.yaml` throughout the rollout. This file is your live status board.

```bash
cat desired-state/mesh/rollout-state.yaml
```

Key fields to watch:

```yaml
rollout_id: "2026-03-16-firmware-2023.09"
status: in_progress        # pending | in_progress | paused | completed | failed
current_ring: stable
rings:
  canary:
    status: completed      # pending | in_progress | completed | failed | halted
    nodes_total: 1
    nodes_succeeded: 1
    nodes_failed: 0
    promoted_at: "2026-03-15T07:30:00"
  stable:
    status: in_progress
    nodes_total: 3
    nodes_succeeded: 1
    nodes_failed: 0
    nodes_remaining: 2
```

**What to watch for:**

| Field | Warning sign |
|-------|-------------|
| `status: failed` | Rollout halted due to error — check stage reports |
| `nodes_failed > 0` | One or more nodes did not pass validation |
| Any ring `status: halted` | Script detected a problem and stopped — human action required |
| Long gap since last `last_updated` | Script may have stalled — check if the terminal is waiting for input |

### Watching the stage reports

The script writes stage reports to `logs/maintenance/` after each node and each ring. Check these in real time:

```bash
ls -lt logs/maintenance/ | head -5
```

### Validating a specific node manually

If you want to check a node independently of the script:

```bash
./skills/mesh-rollout/scripts/validate-node.sh --node lm-escola-telhado
```

This runs the same health checks the rollout script uses:
- Node reachable via SSH
- Correct firmware version installed
- Mesh interface up
- At least one neighbor visible
- No critical errors in recent logs

---

## 4. If a ring fails: HALT procedure

### When the script halts automatically

The script halts when:
- A node fails post-upgrade validation
- A node does not come back up within the timeout (default: 30 minutes)
- The rollback firmware cannot be transferred or applied

When the script halts, it:
1. Stops upgrading any additional nodes in the current ring
2. Writes a failure entry to `rollout-state.yaml`
3. Writes a detailed stage report to `logs/maintenance/`
4. Sends an alert to the maintainer group channel

### Investigation steps

1. Read the stage report for the failed node:
   ```bash
   cat logs/maintenance/<latest-failure-report>.md
   ```

2. Check what state the node is in:
   ```bash
   ./skills/mesh-rollout/scripts/validate-node.sh --node <failed-node-hostname>
   ```

3. Check if the node is reachable at all:
   ```bash
   ssh root@<node-ip> "cat /etc/openwrt_release; uptime; logread | tail -20"
   ```

4. Check whether the firmware upgrade completed or failed mid-process.

### Deciding whether to resume or rollback

| Situation | Decision |
|-----------|---------|
| Node upgraded correctly but failed one non-critical validation check | Investigate. May be able to resume after manual fix. |
| Node upgraded but has a reproducible problem (e.g., mesh not joining) | Roll back this node. Do not advance the ring. |
| Node is unreachable after upgrade (bricked or failed boot) | Physical access required. Do not advance the ring. See rollback section. |
| Multiple nodes in the same ring failed with the same symptom | Likely a firmware issue. Halt the entire rollout. Roll back all affected nodes. |

**Default rule: when in doubt, roll back and halt.** A partial rollout is recoverable. Advancing a failing rollout makes recovery harder.

### Rollback a single node

```bash
./skills/mesh-rollout/scripts/rollback-node.sh \
  --node <hostname> \
  --rollback-firmware ./backups/firmware/<rollback-image>
```

### Halt the entire rollout

To formally record the halt and prevent accidental resumption:

```bash
./skills/mesh-rollout/scripts/run-rollout.sh --halt \
  --reason "brief description of why the rollout was halted"
```

This updates `rollout-state.yaml` with `status: halted` and sends an alert.

After halting:
1. Roll back all nodes that were upgraded in the failed ring (in reverse order).
2. Validate each rolled-back node (`validate-node.sh`).
3. Write an incident log entry.
4. Notify the community group.

---

## 5. Post-rollout: validate, update, log

### Step 1 — Run the full post-rollout validation

After all rings complete successfully:

```bash
./skills/mesh-rollout/scripts/check-drift.sh
```

Compare the output to the pre-rollout baseline you saved. Confirm:
- [ ] All nodes are on the target firmware version
- [ ] All nodes are reachable
- [ ] Mesh topology is intact
- [ ] No new degraded nodes
- [ ] No sites have lost connectivity
- [ ] Gateways and relay nodes are functioning

### Step 2 — Update the firmware policy

Edit `desired-state/mesh/firmware-policy.yaml`:
- Set `current_version` to the newly deployed version
- Set `rollback_version` to the previous version
- Record the rollout date in `last_rollout`

### Step 3 — Update the node inventory

For each upgraded node, update the `firmware_version` field in `inventories/mesh-nodes.yaml` to reflect the new version.

### Step 4 — Write the maintenance log

Ask the `knowledge-curator` skill to write a maintenance log entry, or write it manually in `logs/maintenance/`. Minimum content:

- Date and duration of rollout
- Firmware version upgraded from and to
- Hardware models affected
- Total nodes upgraded
- Any nodes that required manual intervention
- Issues encountered and how they were resolved
- Approver name and approval channel
- Link to the rollout-state.yaml snapshot

### Step 5 — Notify the community

Send the post-window message from `docs/playbooks/maintenance-window.md`. Mention the firmware update briefly in plain language.

---

## 6. Quick reference: the 5 key commands

All scripts are in `skills/mesh-rollout/scripts/`. Run them from the workspace root.

| Command | Purpose |
|---------|---------|
| `./skills/mesh-rollout/scripts/check-drift.sh` | Show current mesh state vs desired state. Run before and after any rollout. |
| `./skills/mesh-rollout/scripts/run-rollout.sh --ring <ring> --dry-run` | Preview what the rollout would do without making changes. Always run first. |
| `./skills/mesh-rollout/scripts/run-rollout.sh --ring <ring>` | Execute the live rollout for a specific ring. Run only after dry run review. |
| `./skills/mesh-rollout/scripts/validate-node.sh --node <hostname>` | Check a specific node's health and firmware version. Use to investigate failures. |
| `./skills/mesh-rollout/scripts/rollback-node.sh --node <hostname> --rollback-firmware <image>` | Roll back a single node to the previous firmware. Use when validation fails. |

**Policy files:**
- `desired-state/mesh/community-profile/rollout-policy.yaml` — ring definitions, approval requirements, change windows
- `desired-state/mesh/firmware-policy.yaml` — target firmware version, hardware model support, rollback version
- `desired-state/mesh/rollout-state.yaml` — live rollout status (created by the script at rollout start)
