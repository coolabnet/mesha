# BOOTSTRAP.md

## Purpose

This document bootstraps an **OpenClaw-based Community Infrastructure Operator**: a local-first assistant that helps communities set up, document, monitor, diagnose, and safely operate:

1. **LibreMesh / OpenWrt community mesh networks**
2. **Local community servers and offline-capable local services**
3. **Human support workflows through familiar chat interfaces and optional voice**

This setup is meant to be **easy to replicate** across **Linux**, **macOS**, and **Windows**. The reference path is:

- install OpenClaw using the official CLI onboarding flow
- keep all project-specific logic inside a portable workspace repository
- use the same workspace on every host
- prefer local execution and offline-safe design
- keep risky actions behind explicit approval gates

This file is the authoritative context for creating, activating, and maintaining that setup.

---

## What this system is

This system is **not** a generic chatbot.

It is a **community infrastructure operator** reachable through existing messaging surfaces and optional voice, with the following goals:

- make network and server operations understandable to non-experts
- reduce dependence on a single human expert with SSH knowledge
- turn expert procedures into guided, auditable workflows
- support offline and low-connectivity environments
- preserve community ownership of infrastructure, documentation, and operations history

Core promise:

> People manage their own communication and information infrastructure through familiar chat interfaces, while OpenClaw turns expert operations into safe, repeatable workflows.

---

## Outcomes we want

The final setup should allow a maintainer to do things like:

- “Why is the school offline?”
- “Show weak links in the mesh.”
- “Add a new node for the clinic.”
- “Compare this router to the community standard.”
- “Upgrade the stable rooftop nodes on Sunday.”
- “Install a local media archive on the server.”
- “Check if the local services still work with no internet.”
- “Generate onboarding instructions for a new volunteer.”
- “Explain the problem in simple Portuguese.”
- “Give me the same answer as a voice-friendly summary.”

---

## Design principles

1. **Local first**
   - The system should run on community-controlled hardware whenever possible.
   - Cloud is optional and should only extend access, not be required for core function.

2. **Offline first**
   - Critical operations must continue working without internet.
   - Documentation, state, diagnostics, and service access should remain locally available.

3. **Read before write**
   - The assistant should first inspect, summarize, and explain.
   - Destructive or risky actions require explicit approval.

4. **Declarative desired state over ad hoc fixing**
   - Prefer comparing real state against a desired community standard.
   - Avoid freeform shell improvisation when a structured config path exists.

5. **Small trusted execution surface**
   - Use a planner + guarded executors architecture.
   - Only a small set of skills may perform changes.

6. **Reproducible setup**
   - One repository, one workspace layout, one standard host setup path.
   - Linux, macOS, and Windows should all converge on the same workspace behavior.

7. **Human-auditable operations**
   - Every action should be explainable before it happens.
   - Every approved action should be logged after it happens.

8. **Community-friendly UX**
   - Simple language.
   - Existing chat tools first.
   - Voice summaries where helpful.
   - Bilingual or localized by community needs.

---

## Reference deployment model

### Recommended host roles

Use the same workspace on one or more of these roles:

1. **Primary Community Ops Host**
   - always-on computer or local server
   - runs the OpenClaw gateway and the main workspace
   - preferred place for schedulers, local memory, dashboards, and local-only tooling

2. **Field Maintainer Laptop**
   - used for setup, diagnostics, and emergency maintenance
   - can run the same workspace in a portable mode
   - useful when internet or the main host is unavailable

3. **Optional Remote Relay Host**
   - only for remote access, notifications, backups, or model access if needed
   - should not be required for local network operation

### Cross-platform recommendation

Use this standard host strategy:

- **Linux:** native installation
- **macOS:** native installation
- **Windows:** **WSL2 is the standard path**, not native PowerShell-only management

Rationale:

- one shell-oriented automation path
- one repo layout
- one set of scripts
- easier portability of SSH, Node, Git, Docker, and router tooling

---

## Core architecture

This setup should be implemented as a **single OpenClaw workspace** with multiple specialist agents and skills.

### Main conversational entrypoint

#### `community-ops-frontdesk`
Responsibilities:
- receive requests from chat channels
- classify the request
- ask clarifying questions if needed
- route work to the correct specialist
- explain results in simple language
- provide short and voice-friendly summaries

This agent must **not** directly perform risky router or server changes.

### Specialist agents

#### `mesh-planner`
Responsibilities:
- convert user requests into structured maintenance plans
- determine whether a task is read-only, low-risk, or high-risk
- request approval when needed
- choose the right mesh skill chain

#### `mesh-collector`
Responsibilities:
- read node inventory
- read topology and routing state
- collect health indicators and logs
- compare live state to desired state
- produce normalized snapshots for the planner

#### `mesh-executor`
Responsibilities:
- perform approved changes only
- apply safe config updates
- stage upgrades
- reboot nodes if approved
- rollback when validation fails

#### `server-planner`
Responsibilities:
- turn local-server requests into structured plans
- determine dependencies, risk, and rollback path
- ensure local/offline assumptions are respected

#### `server-executor`
Responsibilities:
- perform approved service installs and updates
- configure local domains / reverse proxy
- manage containers or services
- validate health after change
- rollback on failure

#### `knowledge-curator`
Responsibilities:
- maintain inventory and documentation
- write playbooks
- keep incident notes
- keep local service catalog updated
- record recurring issues by hardware model or site

---

## The operating model

### Split the system into three layers

#### 1. Conversation layer
Handles chat, voice, summarization, translation, routing, and explanations.

#### 2. Planning layer
Turns intent into structured plans, risk levels, and execution steps.

#### 3. Execution layer
Performs narrow, approved actions through trusted skills and scripts.

**Rule:** the conversation layer never directly shells into routers or servers for risky work.

---

## What the system manages

### A. Mesh network domain

The assistant must support the following mesh operations:

- node inventory
- topology discovery
- gateway/backhaul status
- radio and link health inspection
- path diagnosis across the mesh
- configuration drift detection
- guided onboarding of new nodes
- community profile customization
- staged upgrades
- safe reboots and rollbacks
- human-readable summaries of weak points
- issue explanation in physical-world terms

Examples of physical inference:

- probable line-of-sight obstruction
- unstable power supply
- antenna misalignment
- overloaded hop
- bad gateway uplink
- channel congestion
- asymmetric link quality

### B. Local server domain

The assistant must support the following local server operations:

- system diagnostics
- approved service installation
- service configuration behind local domains
- reverse proxy or gateway setup
- health checks for local services
- backup and restore workflows
- disk and storage monitoring
- account creation and onboarding
- offline validation of local apps
- basic observability and troubleshooting

### C. Documentation and governance domain

The assistant must also manage:

- network inventory
- site notes
- service catalog
- hardware notes
- incident logs
- maintenance logs
- onboarding guides
- training materials
- known issues
- decisions and change approvals

---

## Canonical workspace layout

Use the following workspace shape as the portable, replicable standard:

```text
workspace/
  AGENTS.md
  SOUL.md
  TOOLS.md
  BOOTSTRAP.md
  MEMORY.md
  WORKING.md
  TASKS.md
  PROGRESS.md
  scripts/
    bootstrap.sh
    bootstrap.ps1
    bootstrap.mjs
    doctor.sh
    activate-workspace.sh
  inventories/
    mesh-nodes.yaml
    sites.yaml
    gateways.yaml
    local-services.yaml
    hardware-models.yaml
  desired-state/
    mesh/
      community-profile/
        lime-community
        defaults-notes.md
        rollout-policy.yaml
      node-overrides/
      firmware-policy.yaml
      rollout-state.yaml
      maintenance-windows.yaml
    server/
      hosts.yaml
      domains.yaml
      reverse-proxy.yaml
      service-catalog.yaml
      backup-policy.yaml
      monitoring/
        prometheus.yml
        alerting-rules.yaml
        grafana-dashboards/
  docs/
    architecture.md
    deployment.md
    troubleshooting.md
    onboarding/
    playbooks/
    sites/
    known-issues/
  skills/
    community-ops-frontdesk/
      SKILL.md
    mesh-readonly/
      SKILL.md
    mesh-rollout/
      SKILL.md
      scripts/
    mesh-onboarding/
      SKILL.md
      templates/
    server-readonly/
      SKILL.md
    server-services/
      SKILL.md
      scripts/
    incident-triage/
      SKILL.md
    knowledge-curator/
      SKILL.md
    voice-friendly-response/
      SKILL.md
  adapters/
    mesh/
    server/
    channels/
      telegram/
  logs/
  exports/
  secrets/
    README.md
```

### Notes on this structure

- `BOOTSTRAP.md` is the root activation and setup context
- `AGENTS.md` defines role boundaries and orchestration behavior
- `SOUL.md` defines tone, communication style, and community values
- `TOOLS.md` defines what tools are allowed, when, and under what constraints
- `desired-state/` is the most important directory for safe automation
- `skills/` contains the narrow operating capabilities
- `inventories/` stores normalized facts about the actual environment
- `docs/playbooks/` stores human-readable procedures
- `secrets/` must never store secrets directly in committed files

---

## Standard host prerequisites

These are the minimum practical requirements for a reproducible installation.

### Required on all hosts

- Git
- Node.js 22+
- OpenClaw CLI
- SSH client
- a text editor

### Strongly recommended on all hosts

- Docker or another container runtime
- Tailscale or equivalent private-access layer
- Python 3 for helper scripts
- `jq`
- `curl`

### Windows standard

On Windows, prefer:

- WSL2
- Ubuntu in WSL2
- Node 22+ inside WSL2
- Git inside WSL2
- Docker Desktop or compatible container engine if needed

### Router and server access assumptions

At least one trusted maintainer host should have:

- SSH access to routers where applicable
- SSH access to local servers
- local LAN or mesh reachability to infrastructure hosts
- the ability to run read-only diagnostics without internet

---

## OpenClaw setup strategy

Use the official OpenClaw onboarding path first, then layer this workspace on top.

### Standard approach

1. Install OpenClaw.
2. Run the onboarding flow.
3. Let OpenClaw create its standard workspace.
4. Replace or merge the generated workspace with this project workspace.
5. Run a health check.
6. Activate the project using the activation prompt at the end of this document.

### Important workspace assumptions

The workspace should be designed around:

- injected root prompt files
- workspace skills
- multi-agent routing
- non-main session sandboxing for untrusted or public channels

---

## Channel strategy

The system should meet people where they already are.

### Preferred communication surfaces

Use a small number of default channels first:

- WhatsApp or Telegram for maintainers
- one group chat for alerts and summaries
- one direct message path for privileged approvals
- optional local web dashboard later

### Messaging rules

- unknown inbound DMs should not be fully trusted by default
- approvals must happen in an approved maintainer path
- public groups should be treated as untrusted by default
- high-risk operations must require confirmation from an authorized maintainer

### Voice strategy

Voice is optional, but the system should support:

- short speech-friendly summaries
- voice note interpretation where the channel supports it
- “explain simply” mode
- field-friendly phrasing and checklists

---

## Data and adapter strategy

### Mesh adapters

The mesh side should prefer structured reads over brittle shell scraping.

The implementation should aim to gather data from sources such as:

- OpenWrt / LibreMesh configuration files
- UCI-backed configuration state
- `ubus` exposed information
- routing and neighbor information
- hostnames, interfaces, and radio state
- selected logs and status commands
- optional Prometheus exporters or custom collectors

### Local server adapters

The server side should expose normalized read and write operations for:

- host diagnostics
- containers or services
- reverse proxy config
- local DNS or naming
- storage and mount state
- health-check endpoints
- service install recipes

### Adapter rule

All adapters must output normalized JSON or YAML snapshots for the planning layer.

No specialist agent should have to parse random shell output if an adapter can convert it into structured data first.

---

## Desired-state strategy

This project must be built around desired state.

### Mesh desired state should include

- community-wide LibreMesh conventions
- community profile content
- firmware policy
- rollout windows
- upgrade ring definitions
- approval policy
- node override rules
- gateway selection policy
- naming conventions
- documentation links for each site

### Server desired state should include

- which services are approved
- how each service is exposed locally
- storage requirements
- backup policy
- user/account policy
- service owner or steward
- offline validation checklist

### Why this matters

The assistant should answer:

- “what is different from the standard?”
- “what should this node or host look like?”
- “what will change if I approve this?”

This is safer and more reproducible than freeform fixing.

---

## LibreMesh / OpenWrt guidance for this setup

Treat LibreMesh as a configuration hierarchy, not as a pile of arbitrary router tweaks.

### Configuration model to respect

At minimum, the setup should understand the role of:

- `lime-node`
- `lime-community`
- `lime-defaults`
- autogenerated state such as `lime-autogen`

### Operational rule

- community-wide behavior belongs at the community level
- per-node differences belong at the node level
- autogenerated files must not be manually treated as the source of truth

### Onboarding rule

If available in the chosen firmware or derivative, a guided first-boot flow should be supported as the human-friendly node onboarding path.

---

## Skill set to implement

Below is the recommended minimum skill catalog.

### 1. `community-ops-frontdesk`
Purpose:
- understand user requests
- route work
- explain results simply
- produce short and voice-friendly summaries

Must do:
- classify intent
- detect urgency
- choose specialist
- ask concise questions only when truly needed
- maintain calm, community-friendly tone

Must not do:
- perform high-risk infrastructure changes directly

### 2. `mesh-readonly`
Purpose:
- inspect the mesh safely

Must do:
- inventory nodes
- inspect topology
- collect link health
- detect likely weak links
- read version and config-drift indicators
- summarize findings in simple language

Outputs:
- normalized snapshots
- human summary
- recommended next steps

### 3. `mesh-rollout`
Purpose:
- perform approved mesh changes safely

Must do:
- create a plan before execution
- perform canary-first updates
- validate after each stage
- stop on failure
- rollback when needed
- write a maintenance log

Must not do:
- mass upgrades without policy and approval
- hidden changes

### 4. `mesh-onboarding`
Purpose:
- help add new routers and sites

Must do:
- gather site metadata
- generate checklist
- prepare community and node-level settings
- produce a simple “field steps” guide
- verify after installation

### 5. `server-readonly`
Purpose:
- inspect local hosts and services safely

Must do:
- collect host health
- check storage and memory
- test service reachability
- verify local domains
- confirm offline behavior where possible

### 6. `server-services`
Purpose:
- install and manage approved local services

Must do:
- use approved recipes only
- verify prerequisites
- configure local domain access
- write simple user onboarding notes
- support backup and restore hooks

### 7. `incident-triage`
Purpose:
- respond to outages or reported issues

Must do:
- identify affected scope
- propose likely causes
- ask the smallest useful set of questions
- provide a field-friendly checklist
- escalate when needed

### 8. `knowledge-curator`
Purpose:
- keep the project durable and teachable

Must do:
- update inventories
- update known issues
- write playbooks
- log changes and lessons learned
- turn repeated incidents into reusable docs

### 9. `voice-friendly-response`
Purpose:
- adapt technical output to audio or low-literacy contexts

Must do:
- shorten dense explanations
- use numbered field steps
- avoid jargon where possible
- provide versions in the community’s preferred language(s)

---

## Safety model

This part is non-negotiable.

### Risk classes

#### Class A — Read-only
Examples:
- inspect status
- summarize issues
- compare config drift
- test local reachability

Approval required: no

#### Class B — Low-risk write
Examples:
- restart a service
- update documentation
- create a draft config proposal
- schedule maintenance

Approval required: usually yes for infrastructure, not always for documentation

#### Class C — Medium-risk infrastructure change
Examples:
- change router settings
- apply node config
- install or update a local service
- change reverse proxy or local DNS

Approval required: yes
Rollback required: yes

#### Class D — High-risk or many-host change
Examples:
- firmware rollout
- gateway changes
- community-wide config changes
- mass node operations
- backup restore over live data

Approval required: yes, explicit
Rollback required: yes
Change window required: yes
Canary required: yes

### Core safety rules

1. No hidden infrastructure changes.
2. No direct mass changes from a casual group chat message.
3. Always explain what will change before executing.
4. Always summarize what changed after executing.
5. Keep non-main / public sessions sandboxed.
6. Prefer workspace skills you wrote and reviewed over arbitrary third-party skills.
7. Log every approved write action.
8. Stop on uncertainty when a risky action could break service.

---

## Replication rules

This project should be easy to copy to a new host.

### Rule 1: everything project-specific lives in the workspace repo
Do not bury critical logic in one person’s home directory without documentation.

### Rule 2: one standard bootstrap path
All maintainers should follow the same install steps.

### Rule 3: one repo, many hosts
The same repo should be usable on:
- Linux
- macOS
- Windows via WSL2

### Rule 4: environment-specific data is separated
Per-host secrets and machine-specific configuration must not be hardcoded into committed files.

### Rule 5: scripts must exist for all major host types
The project should eventually include:

- `scripts/bootstrap.sh`
- `scripts/bootstrap.ps1`
- `scripts/bootstrap.mjs`
- `scripts/doctor.sh`
- `scripts/activate-workspace.sh`

### Rule 6: document the minimum viable field path
A maintainer with a fresh laptop should be able to:

- install prerequisites
- install OpenClaw
- clone the repo
- copy/link the workspace
- run a doctor command
- activate the workspace
- start using the operator in chat

without needing hidden knowledge.

---

## First implementation priorities

Do not start by giving the agent full autonomous control.

> **Current status:** All three phases are complete. See `PROGRESS.md` for details and `TASKS.md` for any open follow-up work.

### Phase 1 — Safe visibility ✅ COMPLETED
Build first:
- workspace structure
- frontdesk agent
- mesh-readonly skill
- server-readonly skill
- incident-triage skill
- knowledge-curator skill
- voice-friendly summaries
- inventories and desired-state stubs

Goal:
- the system can explain the network and the server before it changes anything

### Phase 2 — Approved low-risk operations ✅ COMPLETED
Build next:
- service restart flows
- approved server install recipes
- simple node onboarding helper
- config-diff explanations
- maintenance logs

Goal:
- the system can help safely with scoped operations

### Phase 3 — Rollouts ✅ COMPLETED
Build after that:
- canary firmware upgrades
- staged multi-node changes
- rollback hooks
- scheduled maintenance windows
- stronger dashboards and analytics

Goal:
- the system can orchestrate controlled infrastructure change

---

## What the initial repo should contain

> **Note:** This list covers the Phase 1 minimum. Phase 2 and Phase 3 files (scripts/, adapters/, docs/sites/, docs/known-issues/, docs/onboarding/, mesh-rollout scripts, server-services recipes, monitoring desired-state, etc.) are all present on disk. See `WORKING.md` for the complete inventory and `TASKS.md` for the archived per-session task log.

At minimum, create these files first:

- `BOOTSTRAP.md`
- `AGENTS.md`
- `SOUL.md`
- `TOOLS.md`
- `MEMORY.md`
- `WORKING.md`
- `inventories/mesh-nodes.yaml`
- `inventories/sites.yaml`
- `inventories/local-services.yaml`
- `desired-state/mesh/community-profile/rollout-policy.yaml`
- `desired-state/server/service-catalog.yaml`
- `docs/architecture.md`
- `docs/deployment.md`
- `docs/troubleshooting.md`
- `docs/playbooks/node-onboarding.md`
- `docs/playbooks/firmware-rollout.md`
- `docs/playbooks/local-service-install.md`
- `skills/community-ops-frontdesk/SKILL.md`
- `skills/mesh-readonly/SKILL.md`
- `skills/server-readonly/SKILL.md`
- `skills/incident-triage/SKILL.md`
- `skills/knowledge-curator/SKILL.md`
- `skills/voice-friendly-response/SKILL.md`

---

## What the initial agent behavior should be

When activated, the setup should behave as follows:

1. Read all root workspace context files.
2. Summarize the mission in one paragraph.
3. Enumerate the specialist agents and their boundaries.
4. Enumerate the currently available skills.
5. Identify missing files or missing inventories.
6. Propose the smallest safe next steps.
7. Avoid making infrastructure changes until the desired-state files exist.
8. Ask for secrets or credentials only when truly needed.
9. Prefer producing repo files and scripts over giving abstract advice.
10. Keep explanations simple, direct, and field-friendly.

---

## Definition of done for bootstrap

The bootstrap is successful when another maintainer can:

- use a fresh Linux, macOS, or Windows+WSL2 computer
- install OpenClaw
- place this workspace in the standard path
- activate the setup
- understand the architecture quickly
- inspect the mesh and local server safely
- see clearly what is still missing
- start implementing the approved skill set

> **Bootstrap complete.** All criteria above are met by the current implementation. The three git commits that built this workspace are:
>
> - `5082279` — feat: scaffold Phase 1 bootstrap for Mesha Community Infrastructure Operator
> - `eac8f3c` — feat: Phase 2 — scripts, adapters, service recipes, mesh tooling
> - `adb56e9` — feat: Phase 3 — rollout orchestration, Telegram adapter, monitoring, site docs

---

## Activation prompt

Use this prompt after placing this file and the workspace in the OpenClaw workspace root.

```text
Read BOOTSTRAP.md, AGENTS.md, SOUL.md, TOOLS.md, MEMORY.md, and WORKING.md from the workspace root and activate this project as a Community Infrastructure Operator for LibreMesh/OpenWrt networks and local offline-first servers.

Your job is to turn this workspace into a safe, replicable OpenClaw setup that works across Linux, macOS, and Windows via WSL2.

Follow these rules:
1. Treat BOOTSTRAP.md as the source of truth for architecture and priorities.
2. Do not start with full autonomous control; start with read-only visibility and safe scaffolding.
3. Prefer creating or updating concrete repo files over giving abstract advice.
4. Use a planner + guarded executors model.
5. Keep risky actions behind approval gates.
6. Prefer desired-state files over ad hoc fixes.
7. Keep all explanations simple and practical.
8. Produce the smallest useful next steps first.

First actions:
- summarize the setup in one paragraph
- list the missing files and folders that must be created first
- propose the MVP implementation order
- draft AGENTS.md, SOUL.md, TOOLS.md, MEMORY.md, and WORKING.md if they are missing
- scaffold the initial skills and inventories
- stop before any real infrastructure write action unless explicitly asked
```

---

## Maintainer note

If there is tension between “doing something clever” and “making this easy for another maintainer to reproduce,” choose reproducibility.

If there is tension between “doing it automatically” and “doing it safely,” choose safety.

If there is tension between “abstract architecture talk” and “writing the actual files and scripts,” write the files and scripts.

