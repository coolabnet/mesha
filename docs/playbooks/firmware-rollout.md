# Firmware Rollout Playbook

**Purpose:** How to safely upgrade firmware on community mesh nodes. Covers planning, canary testing, ring-based rollout, validation, and rollback.

Do not start a firmware rollout unless you have read this entire playbook first. A badly executed upgrade can take multiple sites offline at once.

**Risk class:** Class D — requires explicit approval, a change window, canary testing, and rollback preparation.

---

## Before You Start

### When firmware upgrades are needed

- A security vulnerability has been patched in the upstream firmware
- A bug that is affecting the community has been fixed
- The firmware policy in `desired-state/mesh/firmware-policy.yaml` defines a new target version
- A hardware model is end-of-life on the current version

### When NOT to start a rollout

- [ ] You do not have an approved change window
- [ ] You do not have a tested rollback procedure
- [ ] More than 20% of nodes are already offline
- [ ] There is an active incident in the network
- [ ] The canary node has not been validated
- [ ] You have not confirmed the new firmware boots correctly on this hardware model

---

## Phase 1 — Plan and Prepare

### Step 1 — Review the firmware policy

```bash
cat desired-state/mesh/firmware-policy.yaml
```

Confirm:
- [ ] Target firmware version is specified
- [ ] Approved hardware models are listed
- [ ] Upgrade rings are defined (canary, ring-1, ring-2, etc.)
- [ ] Rollback firmware version is specified
- [ ] Change window is defined (day and time)

If the policy file is missing or incomplete, stop and fill it in before continuing.

> Note: `desired-state/mesh/firmware-policy.yaml` exists in this workspace but may contain only stub content. Fill in the target version, hardware models, upgrade rings, and change window before running a real rollout. The `desired-state/mesh/community-profile/lime-community` file must also be present — only `rollout-policy.yaml` is in that directory by default.

### Step 2 — Identify all nodes to upgrade

Ask the operator:

> "List all nodes that are not on the target firmware version."

Or check manually:

```bash
# On each node you can reach
ssh root@<node-ip> "cat /etc/openwrt_release | grep RELEASE"
```

Compare against the target version in `desired-state/mesh/firmware-policy.yaml`.

Build a list of nodes to upgrade, grouped by their upgrade ring (see Step 3).

### Step 3 — Confirm the upgrade rings

Upgrade rings define the order in which nodes are upgraded. The community should define these rings in the firmware policy. A typical ring structure:

| Ring | Contents | Purpose |
|---|---|---|
| Canary | 1 non-critical node, ideally with physical access | First test — if it fails, no other nodes are touched |
| Ring 1 | 2–3 non-critical nodes at different sites | Broader test — validates at scale |
| Ring 2 | Remaining non-critical nodes | Main rollout |
| Ring 3 | Critical nodes (gateways, backbone) | Last — only after all others pass |

If rings are not defined in the policy, define them now. Gateways and backbone nodes must always be last.

### Step 4 — Download and verify the firmware image

1. Download the correct firmware image for each hardware model involved.
2. Verify the checksum:
   ```bash
   sha256sum <firmware-image-file>
   ```
   Compare against the official checksum published by the firmware project.
3. Store the verified image in a location accessible during the rollout.
4. Also have the current (rollback) firmware image available.

### Step 5 — Prepare the rollback firmware

For each hardware model, confirm you have the previous firmware image ready:
- It should be the version listed as `rollback_version` in `desired-state/mesh/firmware-policy.yaml`
- Verify its checksum
- Confirm it can be flashed back if needed

### Step 6 — Notify maintainers and get approval

Send a rollout plan to all maintainers with approval rights:

> "Firmware rollout plan:
> - Target version: [version]
> - Hardware models: [list]
> - Nodes to upgrade: [count]
> - Change window: [date and time]
> - Canary node: [hostname]
> - Rollback plan: [brief description]
> Please approve."

**Do not proceed until you have explicit written approval.**

---

## Phase 2 — Canary Upgrade

The canary is a single non-critical node upgraded first. If anything goes wrong, you stop here.

### Step 7 — Choose the canary node

The canary node should be:
- A non-critical node (not a gateway or backbone)
- A site where loss of service during the test is acceptable
- Ideally a site where someone is physically present or nearby

Record the canary hostname:
```
Canary node: ____________________
```

### Step 8 — Back up the canary node config before upgrading

```bash
ssh root@<canary-node-ip>
# Export UCI config as plain text and compress it
uci export | gzip > /tmp/config-backup-$(hostname)-$(date +%Y%m%d).uci.gz
```

Copy the backup to a safe location outside the node:
```bash
scp root@<canary-node-ip>:/tmp/config-backup-*.uci.gz ./backups/
```

### Step 9 — Upgrade the canary node

Use the `mesh-rollout` skill (recommended) or do it manually:

```bash
ssh root@<canary-node-ip>

# Transfer the firmware image to the node
scp <firmware-image> root@<canary-node-ip>:/tmp/

# On the node: verify the checksum again
sha256sum /tmp/<firmware-image>

# Perform the upgrade (LibreMesh/OpenWrt sysupgrade)
# -n flag: do NOT preserve config (recommended for major upgrades)
# -c flag: preserve config (use for minor/patch upgrades if safe)
sysupgrade -n /tmp/<firmware-image>
```

The node will reboot automatically. Wait 3–5 minutes.

### Step 10 — Validate the canary node

After the node comes back up:

```bash
ssh root@<canary-node-ip>

# Confirm firmware version
cat /etc/openwrt_release

# Check mesh interfaces
ip link show
iwinfo

# Confirm it joined the mesh
batctl n

# Check logs for errors
logread | tail -30
```

Also ask the operator:
> "Check the health of [canary-hostname] and confirm it upgraded correctly."

**Validation checklist:**
- [ ] Firmware version matches target
- [ ] Node is reachable via SSH
- [ ] Mesh interface is up
- [ ] At least one neighbor is visible with acceptable link quality
- [ ] No critical errors in logs
- [ ] SSID is broadcasting if it is an access point
- [ ] Config has been reapplied (if using `-c` flag or re-running `lime-config`)

**If validation fails:** stop the rollout immediately. Do not proceed to Ring 1. See the Rollback section below.

**If validation passes:** wait 30 minutes and check the canary again before proceeding. Issues sometimes appear after a few minutes.

---

## Phase 3 — Ring-by-Ring Rollout

Repeat the following steps for each ring, in order. Complete and validate each ring fully before starting the next.

### Step 11 — Upgrade the ring

For each node in the ring, repeat Steps 8–10:
1. Back up the node config
2. Transfer the firmware image
3. Run `sysupgrade`
4. Wait for the node to come back up
5. Validate the node

You can upgrade multiple nodes in the same ring in parallel, but only if:
- They are on different sites (not dependent on each other for connectivity)
- You have enough maintainers to monitor each one
- Your rollback capability covers all of them simultaneously

When in doubt, upgrade one at a time.

### Step 12 — Validate the ring before proceeding

After all nodes in a ring are upgraded, run a full mesh health check:

> Ask the operator: "Run a mesh health check and show me any issues."

**Ring validation checklist:**
- [ ] All upgraded nodes are reachable
- [ ] All upgraded nodes show the correct firmware version
- [ ] Mesh topology is intact (no unexpected gaps)
- [ ] Link quality has not degraded
- [ ] No sites have lost connectivity

**If any node in a ring fails validation:** pause the rollout. Fix or roll back the failing node before proceeding to the next ring.

### Step 13 — Proceed through rings in order

```
Canary ✓ → Ring 1 ✓ → Ring 2 ✓ → Ring 3 (gateways last) ✓
```

Do not jump rings. The order exists for safety.

---

## Phase 4 — Final Validation

### Step 14 — Run a full post-rollout health check

After all rings are complete:

> Ask the operator: "Run a full mesh health check. List all nodes, their firmware versions, and any issues."

**Final checklist:**
- [ ] All nodes are on the target firmware version
- [ ] All nodes are reachable
- [ ] Mesh topology matches the expected topology in inventory
- [ ] No sites have degraded connectivity
- [ ] Gateways and backbone nodes are functioning correctly
- [ ] No new errors appeared in node logs

### Step 15 — Update the firmware policy

Update `desired-state/mesh/firmware-policy.yaml`:
- Set `current_version` to the new firmware version
- Set `rollback_version` to the previous version (in case you need it later)
- Record the rollout date

### Step 16 — Write a maintenance log entry

Ask the `knowledge-curator` skill to log:
- Date and time of rollout
- Firmware version upgraded from and to
- Hardware models upgraded
- Number of nodes upgraded
- Any issues encountered
- Who approved and who executed

---

## Rollback Procedure

Use this if any node fails validation or a ring fails after upgrade.

### Single node rollback

If one node fails after upgrade:

```bash
ssh root@<node-ip>

# Transfer the rollback firmware image
scp <rollback-firmware> root@<node-ip>:/tmp/

# Flash the rollback firmware
sysupgrade -n /tmp/<rollback-firmware>
```

Wait for the node to come back up, then validate it (Step 10).

If the node is completely unresponsive after a failed upgrade:
- Physical access is required
- Connect a serial cable to the router's UART pins (check the hardware model notes for pinout)
- Use TFTP recovery or the router's failsafe mode
- See `inventories/hardware-models.yaml` for model-specific recovery notes

### Full rollout halt

If the rollout is failing across multiple nodes:

1. **Stop all upgrades immediately.** Do not upgrade any more nodes.
2. **Assess the damage:** which nodes are affected and which are still on the old firmware.
3. **Rollback in reverse ring order:** start with Ring 3 (the last ring upgraded) and work backwards.
4. **Restore from config backup:** after flashing rollback firmware, restore the config backup you made in Step 8.
5. **Validate each node** after rolling back (Step 10).
6. **Write an incident report** using the `knowledge-curator` skill.

### Config restore after rollback

```bash
# On the rolled-back node
scp ./backups/<config-backup-file>.uci.gz root@<node-ip>:/tmp/

ssh root@<node-ip>
# Restore the UCI config (backup was created with uci export | gzip)
gunzip -c /tmp/<config-backup-file>.uci.gz | uci import
uci commit
reboot
```

---

## Quick Reference

| Stage | Action | Stop if... |
|---|---|---|
| Plan | Review policy, identify nodes, get approval | Policy missing, no approval |
| Canary | Upgrade 1 non-critical node | Validation fails |
| Ring 1 | Upgrade 2–3 non-critical nodes | Any node fails |
| Ring 2 | Upgrade remaining non-critical nodes | Any ring fails |
| Ring 3 | Upgrade gateways and backbone | Any ring fails |
| Final | Full health check, update policy, log | Any critical issue found |

**Rule:** When in doubt, stop and ask. A partial rollout is recoverable. A rushed rollout on a failing path is not.
