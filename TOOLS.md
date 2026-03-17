# TOOLS.md — Mesha Tool Permissions, Risk Classes, and Constraints

Source of truth: `BOOTSTRAP.md`
Last updated: 2026-03-16

---

## Purpose

This file defines what tools, commands, and operations are available in this workspace, which agents may use them, under what conditions, and what approval is required.

The guiding principle is: **read before write, plan before execute, approve before change.**

---

## Risk Classification System

All operations in this workspace are assigned to one of four risk classes. Risk class determines required approval, required rollback planning, and required logging.

---

### Class A — Read-Only

**Definition:** Operations that inspect, read, or report on state without modifying anything.

**Approval required:** No. These operations may be performed automatically in response to a query.

**Rollback required:** No.

**Log required:** Optional. Snapshots may be written for audit purposes but are not required.

**Examples:**
- Read node inventory from `inventories/mesh-nodes.yaml`
- Collect mesh topology and routing state (read-only SSH: `ubus call`, `uci show`, `ip route`, `iwinfo`)
- Read router logs (`logread`)
- Read firmware version from a node
- Detect configuration drift by comparing live config to desired state
- Ping or reach a node to verify connectivity
- Check host disk, memory, and service status (read-only)
- Check container status (`docker ps`, `systemctl status`)
- Verify local domain DNS resolution
- Read service catalog and desired-state files
- Produce status summaries and health reports
- Search playbooks and documentation

**Agents authorized:** Any agent in the workspace.

---

### Class B — Low-Risk Write

**Definition:** Operations that write, restart, or update in a way that is easily reversible and has limited blast radius. Typically affects a single service or document, not critical infrastructure.

**Approval required:** Yes for infrastructure changes. Not required for documentation updates.

**Rollback required:** Informally — maintain awareness of prior state. Formal rollback plan not required.

**Log required:** Yes. All Class B infrastructure actions must produce a log entry in `logs/`.

**Examples:**

Infrastructure (approval needed):
- Restart a single local service (`systemctl restart`, `docker restart`)
- Restart a non-gateway router node when it is not the only path for critical sites
- Clear a stuck process on a server
- Update a single reverse proxy rule for a non-critical domain
- Schedule a maintenance window (no execution, just scheduling)

Documentation (no approval needed):
- Update `inventories/` after an already-completed change
- Update playbooks
- Add a site note
- Write a new onboarding guide
- Update the service catalog to reflect current state
- Add a known issue entry
- Write an incident report

**Agents authorized:**
- Infrastructure Class B: `mesh-executor`, `server-executor` (with approval signal)
- Documentation Class B: `knowledge-curator` (no approval required)

---

### Class C — Medium-Risk Infrastructure Change

**Definition:** Operations that modify infrastructure configuration or install services, with a meaningful risk of service disruption if something goes wrong. Requires a plan, an approval, and a defined rollback path before execution begins.

**Approval required:** Yes. Explicit confirmation from an authorized maintainer in an authorized channel.

**Rollback required:** Yes. Rollback path must be defined in the execution plan before the plan is approved.

**Log required:** Yes. Detailed log entry required, including plan, approval signal, steps taken, and outcome.

**Change window required:** Recommended but not mandatory. Prefer off-peak hours.

**Examples:**

Mesh network:
- Apply a configuration change to an individual router node
- Apply a node-level override to community settings
- Change gateway selection for a site
- Change radio channel or power settings on a node
- Apply a new community-profile setting to a subset of nodes (≤5 nodes)

Local server:
- Install a new approved service
- Update an existing installed service
- Change reverse proxy or local DNS configuration
- Create a user account on a server
- Change backup configuration
- Modify container configuration and redeploy

**Agents authorized:** `mesh-executor` (mesh), `server-executor` (server).
Both require a prior approved plan from the corresponding planner agent.

---

### Class D — High-Risk or Multi-Host Change

**Definition:** Operations that affect many hosts simultaneously, affect core network infrastructure (gateways, community-wide config, firmware), or could cause a widespread outage if they fail. Require the highest level of planning, approval, and validation.

**Approval required:** Yes. Explicit named approval from an authorized maintainer. The approval must name the scope of the change.

**Rollback required:** Yes. Full rollback plan must be documented and validated before execution begins.

**Log required:** Yes. Comprehensive before/after log with validation results.

**Change window required:** Yes. Must be scheduled and announced to the community before execution.

**Canary required:** Yes. At minimum one node or one host must be validated successfully before the rollout continues.

**Examples:**

Mesh network:
- Firmware rollout across multiple nodes
- Community-wide LibreMesh profile change (`lime-community` update)
- Change to gateway or backhaul configuration
- Mass node reboot
- Any change affecting more than 5 nodes at once (6 or more nodes; 5 or fewer is Class C unless gateway or community-profile scope)
- Removing a node from the mesh permanently

Local server:
- Restore from backup over live data
- Migrating a service to a new host
- Operating system or kernel update on a production server
- Any change that requires the host to be offline for more than 5 minutes

**Agents authorized:** `mesh-executor` (mesh), `server-executor` (server).
Both require a completed and approved plan with canary stage defined.

---

## Tool Inventory by Agent

### community-ops-frontdesk

| Tool | Class | Condition |
|------|-------|-----------|
| Read workspace files | A | Always |
| Query inventory | A | Always |
| Invoke mesh-collector snapshot | A | Always |
| Invoke server-readonly snapshot | A | Always |
| Route to specialist agent | A | Always |
| Invoke knowledge-curator | A/B | Always (doc writes are B) |
| Invoke voice-friendly-response | A | Always |
| Request approval from maintainer | — | For Class B+ plans |

### mesh-collector

| Tool | Class | Condition |
|------|-------|-----------|
| SSH read to router nodes | A | Read-only commands only |
| `ubus call` | A | Read-only ubus paths |
| `uci show` | A | All UCI config |
| `logread` | A | Log collection only |
| `iwinfo` | A | Radio status |
| `ip route`, `ip addr` | A | Routing/interface info |
| `ping` | A | Connectivity check |
| Write snapshot to `logs/` | A | Normalized JSON/YAML only |
| Read `inventories/` | A | Always |

### mesh-planner

| Tool | Class | Condition |
|------|-------|-----------|
| Read all workspace files | A | Always |
| Request mesh-collector snapshot | A | Always |
| Write plan to `logs/` | B | Draft plans only. Draft plans written to logs/ before approval are Class B with no approval required (documentation category). |
| Invoke mesh-executor | C/D | Only after approval received |

### mesh-executor

| Tool | Class | Condition |
|------|-------|-----------|
| SSH write to router nodes | C or D | Approved plan only |
| `uci set` / `uci commit` | C | Approved node-level change |
| `lime-config` updates | C/D | Approved community or node scope |
| `sysupgrade` | D | Firmware policy compliant, canary passed |
| `reboot` | B/C/D | B if single non-critical; C/D if gateway or multi-node |
| Write to `logs/` | A | Always after execution |

### server-planner

| Tool | Class | Condition |
|------|-------|-----------|
| Read all workspace files | A | Always |
| Request server-readonly snapshot | A | Always |
| Write plan to `logs/` | B | Draft plans only. Draft plans written to logs/ before approval are Class B with no approval required (documentation category). |
| Invoke server-executor | C/D | Only after approval received |

### server-executor

| Tool | Class | Condition |
|------|-------|-----------|
| SSH write to local server | C or D | Approved plan only |
| `docker compose up/down/pull` | C | Approved recipe |
| `systemctl enable/start/stop` | B/C | B if restart only; C if new config |
| `apt install` / package manager | C | Approved service catalog item only |
| Nginx / Caddy config write | C | Approved domain in `desired-state/server/` |
| `useradd` / account creation | C | Approved user plan |
| Backup restore | D | Explicit Class D plan only |
| Write to `logs/` and `inventories/` | A | Always after execution |

### knowledge-curator

| Tool | Class | Condition |
|------|-------|-----------|
| Read all workspace files | A | Always |
| Write to `docs/` | B | No approval needed |
| Write to `inventories/` | B | To reflect completed changes |
| Write to `desired-state/` | B | After community decision; flag for review |
| Write to `logs/` | A/B | Incident and maintenance logs |

---

## Forbidden Operations

The following are never permitted, regardless of approval:

- Storing secrets, keys, or passwords in any committed workspace file
- Running arbitrary shell commands not covered by an approved plan
- Performing Class D operations from a public or untrusted chat channel
- Accepting approvals from unknown or unverified sources
- Bypassing canary requirements for firmware rollouts
- Modifying `lime-autogen` files and treating them as desired state
- Deleting maintenance logs or incident logs
- Downgrading an assigned risk class without documented justification

---

## Adapter Constraints

All adapters in `adapters/mesh/` and `adapters/server/` must:

- Output normalized JSON or YAML — no raw shell output passed to planner agents
- Never accept write operations in read-only (Class A) mode
- Authenticate using credentials sourced from `secrets/` (never hardcoded)
- Fail safely — on connection error, return a structured error object, not silence

---

## Secrets Handling

- Credentials must never appear in workspace files that are committed to the repository
- All credential references must point to `secrets/` or environment variables
- See `secrets/README.md` for the credential loading convention
- Agents must request credentials only when needed for an approved operation
- Credentials must not be logged in operation logs

---

## Approval Signal Format

When a maintainer approves a Class C or D action, the approval must:

1. Come from an authorized maintainer account in an authorized channel
2. Reference the specific plan (by plan ID or description)
3. Explicitly say "approve" or "yes, proceed" — vague confirmations are not sufficient for Class D
4. Be logged as part of the operation record

Example (Class C approval):
```
Approve: install Nextcloud on server-ops per plan 2026-03-16-nextcloud-install
```

Example (Class D approval):
```
Approve firmware rollout to ring-stable per plan 2026-03-16-firmware-d1. Change window: Sunday 22:00–23:00.
```

---

## Bootstrap and Maintenance Scripts

- `scripts/doctor.sh` — Class A (read-only diagnostics, no approval needed)
- `scripts/bootstrap.sh` / `scripts/activate-workspace.sh` on a trusted host — Class B (maintainer awareness needed, no formal approval required)
- Cross-host or production deployment scripts — Class C (maintainer approval required)

*This section will be expanded in Phase 2 when scripts are implemented.*
