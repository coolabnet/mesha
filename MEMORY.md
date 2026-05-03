# MEMORY.md — Mesha Memory Model and Knowledge Storage

Source of truth: `BOOTSTRAP.md`
Last updated: 2026-03-17

---

## Purpose

This file defines how the Mesha workspace stores, retrieves, and maintains knowledge about the infrastructure it manages. Memory is what makes this system safe to use over time — it is what allows the system to answer "what is normal here?" before it answers "what should change?"

All memory in this workspace is stored as files in the repository. There is no separate database. This is a deliberate choice: files are offline-safe, version-controllable, human-readable, and can be inspected by any maintainer without special tooling.

---

## Memory Categories

### 1. Inventory — What exists

Inventories describe the durable identity and known structure of the physical and logical infrastructure.
They are seeded manually once, then supplemented by machine-generated observations.

**Location:** `inventories/`

| File | Contents |
|------|----------|
| `inventories/mesh-nodes.yaml` | All known router nodes: name, site, hardware model, SSH target, firmware baseline, role, curated notes, and optional cached observation fields |
| `inventories/sites.yaml` | All known sites: name, location, notes, node list, site contact |
| `inventories/gateways.yaml` | Gateway nodes and uplinks: ISP, bandwidth, backup path, current status |
| `inventories/local-services.yaml` | All locally hosted services: name, host, port/domain, status, owner |
| `inventories/hardware-models.yaml` | Known hardware models: manufacturer, model, notes, known issues, flash size, supported firmware |

**Update rules:**

- Inventories are updated by `knowledge-curator` after any approved change
- Inventories hold durable context that cannot be discovered safely from telemetry alone: site names, local contacts, physical notes, ownership, and intended node roles
- `mesh-collector` may refresh observation fields such as last-seen timestamps after reads, but should not invent site metadata or governance context
- Inventories must never reflect a desired state — they reflect actual known structure and confirmed facts
- When a node is decommissioned, it is marked inactive, not deleted

**Seed vs. refresh:**

- Seed manually once: node names, SSH targets, site mapping, hardware model, gateway identity, uplink notes, local contacts
- Refresh automatically: reachability, collected-at timestamp, cached snapshot, firmware version observed from the node
- If a field comes from live reads and may change often, prefer storing it in `exports/` snapshots and syncing it back into inventory only when that improves long-term clarity

**Freshness:**

- Node status fields may be stale.
- If an inventory entry includes cached observed fields, it should also include a `last_updated` timestamp.
- Agents must check freshness before relying on inventory data for planning.

---

### 1A. Observed Snapshots — What the system last saw

Observed snapshots are machine-generated records from live adapters and heartbeat runs.
They are the preferred cached source for recent status when live reads are unavailable.

**Location:** `exports/`

| File | Contents |
|------|----------|
| `exports/mesh/latest.json` | Most recent full mesh heartbeat snapshot |
| `exports/mesh/snapshots/*.json` | Timestamped historical mesh snapshots for comparison and audit |

**Update rules:**

- Snapshots are written automatically by read-only collectors and heartbeat jobs
- Snapshots may be overwritten or rotated; they are runtime artifacts, not curated knowledge
- Agents should prefer a fresh live read first, then a recent snapshot, and only then fall back to inventory status fields

**Freshness:**

- A snapshot is cached operational state, not a source of truth for site identity
- If `exports/mesh/latest.json` is older than the local heartbeat interval, agents should say it is stale before relying on it

---

### 2. Desired State — What should exist

Desired state files define what the infrastructure should look like according to community decisions and documented standards. They are the reference for drift detection and planning.

**Location:** `desired-state/`

```text
desired-state/
  mesh/
    community-profile/
      lime-community          # The canonical LibreMesh community profile
      defaults-notes.md       # Human notes on why defaults are set as they are
      rollout-policy.yaml     # Which nodes, in what order, under what conditions
    node-overrides/           # Per-node configuration exceptions (documented)
    firmware-policy.yaml      # Approved firmware versions by hardware model
  server/
    hosts.yaml                # Expected server hosts and their roles
    domains.yaml              # Approved local domain names
    reverse-proxy.yaml        # Expected reverse proxy rules
    service-catalog.yaml      # Approved services: what, who, why, install recipe ref
    backup-policy.yaml        # Backup frequency, retention, destinations
```

**Update rules:**

- Desired state is changed only by deliberate community or maintainer decision
- `knowledge-curator` updates these files after a community decision is documented
- Every change to desired-state should include a note on why it changed
- These files are not edited as part of a live fix — they reflect the standard, not a workaround

---

### 3. Incident Log — What went wrong

Incidents record service disruptions, unexpected failures, and any event that required maintainer attention outside of planned maintenance.

**Location:** `logs/incidents/`

> Note: The `logs/` directory and all subdirectories (`logs/incidents/`, `logs/maintenance/`, `logs/decisions/`, `logs/channel-errors/`) are created at runtime by agents on their first write. They do not exist in the initial workspace scaffold. This is intentional — the workspace contains only structured knowledge files, and runtime outputs are generated as the system operates.

**Format:** One file per incident, named by date and brief description.

Example filename: `logs/incidents/2026-03-15-escuela-offline.md`

**Minimum incident record:**

```markdown
# Incident: [site/node] — [brief description]
Date: YYYY-MM-DD
Detected: HH:MM (local time)
Resolved: HH:MM (or "ongoing")
Affected: [list of affected nodes/services]
Reported by: [person or automated alert]

## What happened
[Description of the failure and its impact]

## Likely cause
[Best determination of root cause, even if not confirmed]

## Steps taken
1. [What was done]
2. [What was done]

## Resolution
[What fixed it, or current status if ongoing]

## Follow-up
[Any actions needed to prevent recurrence, or "none"]
```

**Who writes incidents:** `knowledge-curator`, or any agent at the end of an incident-triage session.

---

### 4. Maintenance Log — What was done intentionally

Maintenance records document planned and approved changes: firmware updates, service installs, config changes, and scheduled maintenance windows.

**Location:** `logs/maintenance/`

**Format:** One file per maintenance event, named by date and scope.

Example filename: `logs/maintenance/2026-03-16-firmware-ring1.md`

**Minimum maintenance record:**

```markdown
# Maintenance: [description]
Date: YYYY-MM-DD
Executed by: [agent or person]
Approved by: [maintainer name and channel]
Risk class: [A / B / C / D]
Affected: [list of nodes/services]

## Plan summary
[Brief description of what was planned]

## Steps executed
1. [Step and result]
2. [Step and result]

## Validation
[How success was verified]

## Outcome
[Successful / partial / failed + rollback]

## Notes
[Any observations for future reference]
```

**Who writes maintenance logs:** `mesh-executor` and `server-executor` write these automatically at the end of approved operations. `knowledge-curator` may supplement or correct them.

---

### 5. Playbooks — How to do things

Playbooks are human-readable, step-by-step guides for operations that happen repeatedly or require precise coordination.

**Location:** `docs/playbooks/`

**Current playbooks:**

| File | Purpose |
|------|---------|
| `docs/playbooks/node-onboarding.md` | How to add a new router node to the mesh |
| `docs/playbooks/firmware-rollout.md` | How to safely upgrade firmware on mesh nodes |
| `docs/playbooks/local-service-install.md` | How to install a new service on the local server |

**Guidelines for playbooks:**

- Written for a maintainer with basic technical knowledge, not an expert
- Use numbered steps
- Include "what success looks like" after each step
- Include "what to do if this fails" at key decision points
- Keep them short enough to follow on a phone screen
- Update them when the procedure changes

**Who writes playbooks:** `knowledge-curator`, or any agent instructed to document a procedure.

---

### 6. Site Notes — Local knowledge

Site notes capture context that does not fit in a structured inventory field: physical details, known quirks, access instructions, community contacts, recurring problems.

**Location:** `docs/sites/` (one file per site)

Example: `docs/sites/escuela.md`

**Typical contents:**

```markdown
# Site: Escuela Central
Node(s): node-escuela
Address: Rua das Flores 12
Contact: João (maintainer), +55 11 99999-9999

## Access notes
Router is in the principal's office, top shelf. Key held by the school secretary.
Power strip is shared with the printer — do not disconnect the printer.

## Known issues
- Power cuts 2–3 times per week during storms
- Node goes offline every time power cuts (no UPS)

## History
- 2025-11: First installation
- 2026-02: Moved from hallway to office to reduce tampering
```

**Who writes site notes:** `knowledge-curator`, or any agent at the end of an onboarding or maintenance session involving a site.

---

### 7. Known Issues — Recurring problems by hardware or pattern

Known issues capture patterns that have appeared multiple times, especially by hardware model or specific configuration setup.

**Location:** `docs/known-issues/`

**Who writes:** `knowledge-curator`, typically after two or more incidents with the same cause.

**Example filename:** `docs/known-issues/tplink-wr841n-power-loss.md`

**Minimum record template:**

```markdown
hardware-model-or-pattern: [e.g., TP-Link WR841N]
symptoms: [what the maintainer observes]
confirmed-root-cause: [root cause if known, or "under investigation"]
fix-or-workaround: [what resolves or mitigates the issue]
first-observed: YYYY-MM-DD
recurrence-count: [number of times this has been recorded]
```

Known issues apply to a class of hardware or configuration, not a single incident — use the incident log for one-off events.

---

### 8. Decisions and Governance Log

**Location:** `logs/decisions/`
**Written by:** knowledge-curator, authorized maintainers
**Updated:** when a community governance decision is made, a plan is rejected or deferred, or a policy changes

#### Purpose (Decisions Log)

Covers decisions that did not result in an immediate infrastructure change: rejected upgrade plans, deferred service installs, community standard updates, and approved policy changes. Complements the maintenance log, which covers executed changes.

#### Minimum record format

- **date:** YYYY-MM-DD
- **type:** decision | rejection | deferral | policy-change
- **summary:** one-sentence description
- **rationale:** why this decision was made
- **outcome:** what will or will not happen as a result
- **decided-by:** who authorized or approved

#### Example filename

`logs/decisions/2026-03-16-defer-peertube-install.md`

---

## Memory Retrieval Rules

When an agent needs context before acting, it should retrieve memory in this order:

1. **Inventory** — What is the current known state of the affected node or service?
2. **Desired state** — What should it look like?
3. **Site notes** — Is there local context that matters here?
4. **Incident log** — Has this failed before? What fixed it?
5. **Playbook** — Is there a standard procedure to follow?
6. **Decisions log** — When an agent needs context on why a policy or standard exists, check `logs/decisions/` before assuming defaults.

An agent must not propose a change without first checking whether a desired-state file defines the expected outcome.

An agent must not diagnose a problem without first checking whether the incident log shows a prior occurrence.

---

## Memory Freshness and Gaps

Memory is only useful if it is accurate. The following rules apply:

- If an inventory entry includes cached observed fields, it should include a `last_updated` field
- If `last_updated` is more than 7 days ago for a cached node status, the agent should flag this before relying on it for planning
- After any approved change, `knowledge-curator` is responsible for updating the relevant inventory and log within the same session
- If a file is missing that should exist (e.g., no site notes for a site with known recurring problems), `knowledge-curator` should flag this and propose creating it

---

## What memory does not include

- Secrets, credentials, or keys — these must never appear in workspace files
- Live telemetry streams — this workspace stores normalized snapshots and cached heartbeat outputs, not a permanent time-series database
- Cloud or external state — this workspace only stores what is local and community-controlled
