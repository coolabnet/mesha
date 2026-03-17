# Node Onboarding Playbook

**Purpose:** Step-by-step guide for adding a new LibreMesh/OpenWrt router to the community mesh network.

Follow these steps in order. Do not skip steps. When in doubt, ask the operator before making changes.

**Risk class:** Class B/C (gathering metadata is Class A; applying config is Class C — requires approval)

---

## Before You Start

### What you need

- [ ] Physical access to the new router (or it has already been flashed with LibreMesh/OpenWrt)
- [ ] The router's hardware model and serial number
- [ ] Site information: location name, address or GPS coordinates, site contact person
- [ ] A laptop or phone connected to the same local network as the router
- [ ] SSH access to at least one existing mesh node (for testing the new node joins correctly)
- [ ] A maintainer with approval rights available (for the config application step)

### When NOT to proceed

- If the router is already serving live traffic and removing it from service would cause an outage
- If you do not have a written or verbal approval from the site contact
- If the community profile (`lime-community`) has not been set up yet — set it up first

> Note: The file `desired-state/mesh/community-profile/lime-community` must exist before Phase 2 of this playbook. Only `rollout-policy.yaml` is present in this directory by default. Create `lime-community` with your community's LibreMesh settings before continuing to Phase 2.
> The `desired-state/mesh/node-overrides/` directory is also not yet created — create it when you have your first per-node override to record.

---

## Phase 1 — Gather Site and Node Metadata

This phase is read-only. No changes are made to anything.

### Step 1 — Identify the hardware

1. Check the router's label (usually on the bottom or back) for:
   - Model name (e.g., "TP-Link Archer C7 v4")
   - MAC address (usually labeled as "MAC" or "LAN")
   - Serial number (optional but useful)

2. Check if this hardware model is in the community hardware notes:
   ```bash
   grep -i "<model-name>" inventories/hardware-models.yaml
   ```
   Replace `<model-name>` with the actual model, for example: `grep -i "archer" inventories/hardware-models.yaml`
   If the model is not listed, add it to `inventories/hardware-models.yaml` before continuing.

### Step 2 — Identify the site

1. Confirm the site name matches an entry in `inventories/sites.yaml`.
   ```bash
   grep -i "<site-name>" inventories/sites.yaml
   ```
2. If the site is new, add it first:
   - Name (short identifier, no spaces, e.g., `escola-central`)
   - Full name (human-readable)
   - Location (address or GPS coordinates)
   - Site contact name and phone
   - Notes about the physical installation (rooftop, pole, window mount, etc.)

### Step 3 — Connect to the new router

1. Connect to the router's default WiFi network (usually printed on the label), or connect a cable from your laptop to the router's LAN port.

2. Open a browser and go to `http://192.168.1.1` (or the default IP for this model).

3. If the router already has LibreMesh/OpenWrt installed and you can access the LuCI web interface or SSH, confirm this by running:
   ```bash
   ssh root@192.168.1.1
   uname -a
   cat /etc/openwrt_release
   ```

4. Note the firmware version and confirm it matches the approved firmware in `desired-state/mesh/firmware-policy.yaml`.

### Step 4 — Record the node's current state

Ask the operator to collect a snapshot, or do it manually:

```bash
ssh root@<router-ip>

# Record these values:
hostname
cat /etc/config/lime-node 2>/dev/null || echo "no lime-node config yet"
cat /etc/config/lime-community 2>/dev/null || echo "no lime-community config yet"
uci show network
iwinfo
```

Write down or copy the output. You will need this to verify the node is working correctly at the end.

---

## Phase 2 — Prepare the Configuration

This phase produces a config proposal. No changes are applied yet.

### Step 5 — Ask the operator to prepare the node config

Send the operator a message like:

> "I want to add a new node. Site is [site-name], hardware is [model], location is [description]. Generate the onboarding config for me."

The operator (using the `mesh-onboarding` skill) will:
1. Look up the community profile from `desired-state/mesh/community-profile/lime-community`
2. Generate a `lime-node` config with the correct community settings applied
3. Propose a hostname following the community naming convention
4. Output a config diff showing what will be set

### Step 6 — Review the proposed configuration

Check that the proposed config looks right:

- [ ] Hostname follows the community naming convention (e.g., `site-role-number` like `escola-ap-01`)
- [ ] Community SSID is correct
- [ ] Channels are appropriate for the site (avoid channels already congested at this location)
- [ ] Any node-level overrides are documented in `desired-state/mesh/node-overrides/`
- [ ] The node's role is correct (access point, backhaul, gateway, or combined)

If anything looks wrong, correct it before proceeding. Do not apply a config you have not reviewed.

### Step 7 — Write the node to the inventory (draft)

Add the node to `inventories/mesh-nodes.yaml` in draft status. This draft should contain only the durable facts that a live read cannot infer safely on its own:

- site
- human-readable node name
- SSH-reachable hostname or management IP
- hardware model
- intended role
- any physical notes that matter for maintenance

Live status, reachability, topology membership, and recent collection timestamps should come from `mesh-readonly` snapshots after the node is reachable.

Draft example:

```yaml
- hostname: escola-ap-01
  site: escola-central
  model: TP-Link Archer C7 v4
  mac: aa:bb:cc:dd:ee:ff
  role: access-point
  status: onboarding
  firmware: <version>
  notes: "Rooftop installation, facing the square"
```

Do not set `status: active` until Phase 3 is complete.

---

## Phase 3 — Apply Configuration and Verify

This phase makes changes. It requires explicit approval.

### Step 8 — Request approval

Before applying any config, notify a maintainer with approval rights:

> "Ready to configure [hostname] at [site-name]. Here is the proposed config: [paste config]. Please approve."

Wait for explicit approval before continuing.

### Step 9 — Apply the community profile

Once approved, apply the configuration. The operator (using `mesh-onboarding` or `mesh-rollout` skill) will do this, or you can do it manually:

```bash
ssh root@<router-ip>

# Apply the community-level config first
uci import lime-community <<EOF
<paste lime-community content here>
EOF
uci commit lime-community

# Apply the node-level config
uci import lime-node <<EOF
<paste lime-node content here>
EOF
uci commit lime-node

# Regenerate LibreMesh config
lime-config

# Check for errors before rebooting
logread | tail -20
```

### Step 10 — Reboot the node

```bash
ssh root@<router-ip>
reboot
```

Wait 2–3 minutes for the node to come back up. LibreMesh needs time to regenerate interfaces and join the mesh.

### Step 11 — Verify the node joined the mesh

From an existing mesh node:

```bash
ssh root@<existing-node-ip>

# Check if the new node appears in the neighbor table
batctl n       # if using batman-adv
# or
ip neigh       # ARP-based check

# Try to ping the new node by hostname
ping escola-ap-01
```

From your laptop (if connected to the mesh):

```bash
# Check the new node's mesh IP
ssh root@escola-ap-01
# or by its expected IP address
ssh root@<new-node-ip>
```

### Step 12 — Run a post-onboarding health check

Ask the operator:

> "Check the health of escola-ap-01 and verify it is working correctly."

The operator will use `mesh-readonly` to:
- Confirm the node is in the topology
- Check link quality to its neighbors
- Verify the config matches the community profile
- Flag any remaining drift

Expected checks:
- [ ] Node responds to SSH
- [ ] Hostname is correct
- [ ] Mesh interface is up (`bat0` or equivalent)
- [ ] At least one neighbor is visible with good link quality
- [ ] SSID is broadcasting correctly
- [ ] Config matches community profile (no drift)

---

## Phase 4 — Finalize Documentation

### Step 13 — Update the inventory to active

Once the health check passes, update the node status in `inventories/mesh-nodes.yaml`:

```yaml
  status: active
  commissioned: <today's date>
```

### Step 14 — Document the physical installation

Add a note to the node's inventory entry or to `inventories/sites.yaml` describing:
- Mounting location (rooftop, pole height, indoor window)
- Cable run length
- Power source (wall outlet, PoE switch, solar)
- Any notable line-of-sight considerations
- Who installed it and on what date

### Step 15 — Write a brief maintenance log entry

Ask the knowledge-curator skill (or write it yourself) to log:
- Node added: hostname, site, model, date
- Who approved the config
- Any issues encountered during installation
- Any node-level overrides and why they were needed

---

## Post-Onboarding Checklist

- [ ] Node is active in `inventories/mesh-nodes.yaml`
- [ ] Node appears in mesh topology
- [ ] Link quality to neighbors is acceptable (>50% quality, adjust threshold for your community)
- [ ] SSID is visible and clients can connect
- [ ] Config matches community profile
- [ ] Physical installation details are documented
- [ ] Maintenance log entry written
- [ ] Site contact was informed that the node is live

---

## Troubleshooting During Onboarding

**Node does not come back after reboot:**
- Wait 5 minutes. LibreMesh can take longer on first boot after a config change.
- If still unreachable, connect directly via cable and check `logread`.

**Node does not appear in the mesh:**
- Check that the mesh SSID and encryption settings match the community profile.
- Run `lime-config` again and reboot.
- Check for typos in the `lime-node` and `lime-community` config.

**Config drift is reported immediately after onboarding:**
- The node may have `lime-autogen` values conflicting with your settings.
- Check if there is a node override in `desired-state/mesh/node-overrides/` that should be applied.
- Do not edit `lime-autogen` directly — it is regenerated automatically.

**Wrong hostname:**
- Change the hostname in `lime-node`, run `lime-config`, and reboot.
- Update `inventories/mesh-nodes.yaml` to match.

---

## Rolling Back an Onboarding

If you need to undo a node configuration that was applied in Phase 3:

### Reverting to the factory state

If the node was a new device with no prior production config, a factory reset is the safest rollback:

```bash
ssh root@<router-ip>
# OpenWrt factory reset
firstboot && reboot now
```

This wipes all config. The node will come back with a clean LibreMesh/OpenWrt install (or factory firmware if sysupgrade was used).

### Reverting to a previous config

If the node had an existing config before onboarding (e.g., it was already part of the mesh):

1. Restore from the state snapshot you collected in Step 4:
   ```bash
   ssh root@<router-ip>
   # Re-apply the previous lime-node content (from your Step 4 notes)
   uci import lime-node <<EOF
   <paste previous lime-node content here>
   EOF
   uci commit lime-node
   lime-config
   reboot
   ```

2. Update `inventories/mesh-nodes.yaml` to reflect the reverted status.
3. Write a log entry explaining what was reverted and why.
