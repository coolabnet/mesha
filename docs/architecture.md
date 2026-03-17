# Architecture

**Purpose:** This document describes how the Mesha Community Infrastructure Operator is structured — what the layers are, what each agent does, what skills are available, how adapters work, and how safety is enforced.

Read this first if you want to understand how the pieces fit together before deploying or extending the system.

---

## Overview

Mesha is a **community infrastructure operator** built on OpenClaw. It helps communities manage LibreMesh/OpenWrt mesh networks and local offline-capable servers through familiar chat interfaces.

It is not a generic chatbot. Every action is traceable, explainable, and either read-only or explicitly approved before it runs.

---

## The Three-Layer Model

The entire system is organized into three layers. Each layer has a strict boundary — lower layers cannot be bypassed by higher layers for risky operations.

```
┌─────────────────────────────────────────────────────────┐
│                  CONVERSATION LAYER                     │
│                                                         │
│  Receives messages from chat channels (WhatsApp,        │
│  Telegram, web). Classifies intent. Routes to the       │
│  right specialist. Explains results simply.             │
│  Produces voice-friendly summaries.                     │
│                                                         │
│  Agent: community-ops-frontdesk                         │
└───────────────────────────┬─────────────────────────────┘
                            │ structured request
                            ▼
┌─────────────────────────────────────────────────────────┐
│                    PLANNING LAYER                       │
│                                                         │
│  Turns intent into a structured plan. Determines        │
│  risk class (A/B/C/D). Requests human approval when     │
│  needed. Chooses the right skill chain. Validates       │
│  results after execution.                               │
│                                                         │
│  Agents: mesh-planner, server-planner                   │
└──────────┬───────────────────────────────┬──────────────┘
           │ approved plan                 │ approved plan
           ▼                               ▼
┌──────────────────────┐       ┌───────────────────────────┐
│   EXECUTION LAYER    │       │     EXECUTION LAYER       │
│   (mesh side)        │       │     (server side)         │
│                      │       │                           │
│  Performs approved   │       │  Performs approved        │
│  changes only.       │       │  service installs,        │
│  Node config, staged │       │  config changes,          │
│  upgrades, reboots,  │       │  health checks,           │
│  rollbacks.          │       │  rollbacks.               │
│                      │       │                           │
│  Agent: mesh-        │       │  Agent: server-executor   │
│  executor            │       │                           │
└──────────┬───────────┘       └──────────┬────────────────┘
           │                              │
           ▼                              ▼
     mesh adapters                  server adapters
     (UCI, ubus, SSH)               (SSH, Docker, systemd)
```

**Core rule:** The conversation layer never directly shells into routers or servers for risky work. Every infrastructure change flows through a planner and requires approval.

---

## Agent Roles

### `community-ops-frontdesk`
The single public-facing entry point for all requests.

- Receives messages from chat channels
- Classifies the request (mesh question, server question, documentation, urgency level)
- Asks one clarifying question if truly needed — not multiple questions
- Routes work to the correct specialist agent or skill
- Explains results in simple, non-technical language
- Produces short, voice-friendly summaries
- **Must not** directly perform risky router or server changes

### `mesh-planner`
Translates mesh-related user intent into structured, safe plans.

- Converts requests like "upgrade the rooftop nodes" into step-by-step plans
- Assigns a risk class to the plan (A, B, C, or D — see Safety Model below)
- Requests explicit human approval for Class C and Class D operations
- Chooses the right skill chain (mesh-readonly, mesh-rollout, mesh-onboarding)
- Produces a maintenance log entry after execution

### `mesh-collector`
Gathers facts about the mesh network safely.

- Reads node inventory from `inventories/mesh-nodes.yaml`
- Reads topology, routing state, and neighbor tables
- Collects health indicators: signal strength, link quality, error rates, uptime
- Compares live state to desired state in `desired-state/mesh/`
- Outputs normalized JSON/YAML snapshots — never raw shell output

### `mesh-executor`
Performs approved mesh changes — and nothing else.

- Only runs after a plan has been approved
- Applies safe config updates (UCI, lime-node overrides)
- Stages firmware upgrades using canary-first policy
- Reboots nodes when explicitly approved
- Rolls back automatically when post-change validation fails
- Writes a log entry for every approved action

### `server-planner`
Translates local-server requests into structured plans.

- Determines dependencies, risk class, and rollback path for each operation
- Ensures that offline/local-first assumptions are respected
- Does not approve its own plans — approval comes from a maintainer

### `server-executor`
Performs approved local server changes.

- Uses approved service install recipes only
- Configures local domains and reverse proxy entries
- Manages containers or systemd services
- Validates service health after every change
- Rolls back on failure

### `knowledge-curator`
Keeps the project durable and teachable.

- Maintains `inventories/` files (mesh-nodes, sites, services)
- Writes and updates playbooks in `docs/playbooks/`
- Keeps incident notes and maintenance logs
- Records recurring issues by hardware model or site
- Updates the local service catalog

---

## Skill Catalog

Skills are narrow, reviewable capability units. Each skill lives in `skills/<name>/SKILL.md`.

| Skill | Type | Risk Class | Purpose |
|---|---|---|---|
| `community-ops-frontdesk` | Conversation | A | Receive, classify, route, explain |
| `mesh-readonly` | Read | A | Inspect mesh safely — no changes |
| `mesh-rollout` | Write | C/D | Staged config and firmware rollouts |
| `mesh-onboarding` | Write | B/C | Add a new node to the mesh |
| `server-readonly` | Read | A | Inspect local server safely — no changes |
| `server-services` | Write | C | Install and manage approved local services |
| `incident-triage` | Read+Plan | A/B | Diagnose outages, propose field steps |
| `knowledge-curator` | Write | B | Update docs, inventories, logs |
| `voice-friendly-response` | Conversation | A | Adapt output for voice or low-literacy contexts |

### What each skill must NOT do

- `mesh-readonly` and `server-readonly`: no write operations of any kind
- `community-ops-frontdesk`: no direct infrastructure commands
- `mesh-rollout` and `server-services`: no unapproved execution

---

## Adapter Model

Adapters convert raw infrastructure state into normalized data that planners can reason about.

### Mesh adapters (`adapters/mesh/`)

Read from:
- OpenWrt/LibreMesh configuration files (`/etc/config/lime-node`, `lime-community`, `lime-defaults`)
- UCI-backed configuration state
- `ubus` exposed information (network interfaces, wireless state, system info)
- Routing tables and neighbor information (batman-adv, babeld)
- Hostnames, interface addresses, radio channel/band/SSID
- Selected logs and `logread` output
- Optional: Prometheus exporters, custom collectors

Output:
- Normalized YAML or JSON snapshot of node state
- Topology graph with link quality scores
- Drift report comparing live state to `desired-state/mesh/`

### Server adapters (`adapters/server/`)

Read from:
- SSH-accessible host diagnostics (`df`, `free`, `systemctl status`)
- Container runtime state (Docker, Podman)
- Reverse proxy configuration (Nginx, Caddy)
- Local DNS or `/etc/hosts` entries
- Health-check HTTP endpoints for each service
- Backup hook outputs

Output:
- Normalized host health snapshot
- Service reachability map
- Offline validation results

### Channel adapters (`adapters/channels/`)

Channel adapters are the outermost layer — they bridge external messaging platforms to the `community-ops-frontdesk` agent. They handle platform-specific message format, sender authentication, and trust level assignment. They have no knowledge of mesh networks or server operations.

**Implemented:**
- `adapters/channels/telegram/` — Telegram Bot API adapter (long-polling or webhook, trust level assignment by user ID, Docker Compose deployment). See `adapters/channels/telegram/README.md`.

**Planned (future implementation):**
- `adapters/channels/whatsapp/` — WhatsApp Business API adapter
- `adapters/channels/web-dashboard/` — Local web interface adapter

Trust levels assigned by channel adapters map directly to the risk class system in `TOOLS.md`. See `adapters/channels/README.md` for the full trust model and interface contract.

### Adapter rule

All adapters must output normalized JSON or YAML. No specialist agent should have to parse raw shell output. If the adapter cannot normalize the data, it should return an error rather than pass through garbage.

---

## Monitoring and Observability

The monitoring stack is defined as desired state in `desired-state/server/monitoring/`.

| File | Purpose |
|------|---------|
| `desired-state/server/monitoring/prometheus.yml` | Prometheus scrape configuration — server health, services, optional mesh node exporters |
| `desired-state/server/monitoring/alerting-rules.yaml` | Alerting rules for service and mesh node health |
| `desired-state/server/monitoring/grafana-dashboards/community-overview.json` | Grafana dashboard for community infrastructure overview |

The Prometheus stack is deployed via `skills/server-services/scripts/prometheus/docker-compose.yaml`. Grafana is bundled in the same compose file. Node Exporter provides host-level metrics. Optional: `prometheus-node-exporter-lua` on OpenWrt nodes for mesh metrics (see `prometheus.yml` for commented-out mesh targets).

---

## Bootstrap and Maintenance Scripts

Bootstrap scripts live in `scripts/`. They handle host setup, workspace activation, and pre-flight checks.

| Script | Purpose | Risk Class |
|--------|---------|------------|
| `scripts/bootstrap.sh` | Linux/macOS host setup (Git, Node, OpenClaw, workspace link) | B |
| `scripts/bootstrap.ps1` | Windows PowerShell host setup | B |
| `scripts/bootstrap.mjs` | Node.js cross-platform bootstrap helper | B |
| `scripts/doctor.sh` | Read-only pre-flight check: verifies prerequisites and workspace health | A |
| `scripts/activate-workspace.sh` | Activates the workspace in the OpenClaw runtime | B |

Run `scripts/doctor.sh` first on any new host to check that all prerequisites are met before activating the workspace.

---

## Safety Model

Every operation is assigned a risk class before it runs. The class determines whether approval is required.

### Risk Classes

| Class | Name | Examples | Approval | Rollback |
|---|---|---|---|---|
| A | Read-only | Inspect status, compare config drift, test reachability | Not required | N/A |
| B | Low-risk write | Restart a service, update documentation, draft a config | Usually yes for infrastructure | Recommended |
| C | Medium-risk change | Change router settings, install a service, change local DNS | Required | Required |
| D | High-risk / many-host | Firmware rollout, gateway changes, community-wide config, mass ops | Required + explicit | Required + canary first |

### Core safety rules

1. No hidden infrastructure changes.
2. No direct mass changes triggered from a casual group chat message.
3. Always explain what will change before executing.
4. Always summarize what changed after executing.
5. Public and untrusted channels are sandboxed — they cannot trigger write operations.
6. Prefer workspace skills you have reviewed over arbitrary third-party skills.
7. Log every approved write action.
8. Stop on uncertainty — if a risky action could break service, stop and ask.

### Channel trust model

- **Maintainer direct message**: trusted — can approve Class B/C/D operations
- **Maintainer group**: trusted for alerts and summaries — approvals should use DM
- **Public or unknown group**: untrusted — read-only responses only

---

## Data Flow Example

Here is how a request flows through the system end to end:

```
User in WhatsApp: "Why is the school offline?"
        │
        ▼
community-ops-frontdesk
  → classify: mesh diagnostic, Class A
  → route to: mesh-planner
        │
        ▼
mesh-planner
  → identify: school node in inventories/mesh-nodes.yaml
  → build read plan: collect school node state, neighbors, uplinks
  → route to: mesh-collector (via mesh-readonly skill)
        │
        ▼
mesh-collector (mesh-readonly skill)
  → reads node via SSH or ubus adapter
  → collects link quality to neighbors
  → compares to desired-state/mesh/
  → outputs normalized snapshot
        │
        ▼
mesh-planner
  → interprets snapshot
  → identifies: high packet loss on uplink, last seen 2h ago
  → possible cause: power or backhaul issue
        │
        ▼
community-ops-frontdesk
  → produces simple summary:
    "The school router lost its connection about 2 hours ago.
     The most likely cause is a power issue or a broken cable
     to the gateway node. Here are the next steps to check..."
  → produces voice-friendly short version if requested
```

---

## Workspace Layout Summary

```
workspace/
  BOOTSTRAP.md        ← source of truth for architecture and setup
  AGENTS.md           ← agent role boundaries and routing rules
  SOUL.md             ← tone, communication style, community values
  TOOLS.md            ← which tools are allowed and under what constraints
  MEMORY.md           ← memory model and knowledge storage rules
  WORKING.md          ← current phase status and known gaps
  PROGRESS.md         ← full phase completion record
  inventories/        ← facts about the actual environment
  desired-state/      ← what the environment should look like
  docs/               ← human-readable documentation (this file lives here)
  skills/             ← narrow capability units, one folder per skill
  adapters/           ← infrastructure readers and normalizers
  scripts/            ← bootstrap and maintenance scripts
  logs/               ← approved write action logs (created on first write action)
  secrets/            ← never store secrets in committed files (see README)
```

> Note: `logs/` and `exports/` do not exist yet. `logs/` is created on the first approved write action. `exports/` is created when the first snapshot is exported. Both are intentionally absent until live operations begin.

For full workspace layout, see `BOOTSTRAP.md`.

---

## LibreMesh Configuration Model

The system treats LibreMesh as a configuration hierarchy, not a pile of arbitrary tweaks.

| Config file | Scope | Managed by |
|---|---|---|
| `lime-community` | Community-wide defaults | `desired-state/mesh/community-profile/` |
| `lime-defaults` | OpenWrt/LibreMesh base defaults | Reference only |
| `lime-node` | Per-node overrides | `desired-state/mesh/node-overrides/` |
| `lime-autogen` | Auto-generated at boot | Read-only, never treat as source of truth |

Community-wide behavior belongs at the community level. Per-node differences belong at the node level. The autogenerated files are outputs, not inputs.

> Current workspace state: `desired-state/mesh/community-profile/` contains `rollout-policy.yaml`, `lime-community`, and `defaults-notes.md`. The `desired-state/mesh/node-overrides/` directory exists with an example override (`lm-escola-telhado.uci`). Populate both with real community data before running node onboarding or firmware rollouts. See the playbooks in `docs/playbooks/` for guidance.
