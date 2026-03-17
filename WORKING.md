# WORKING.md — Mesha Current Working State

Source of truth: `BOOTSTRAP.md`
Last updated: 2026-03-16

---

Last synced: 2026-03-16 — all 33 Phase 1 files exist on disk.

## Overall Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Safe Visibility — workspace scaffold and read-only operations | In progress |
| Phase 2 | Approved low-risk operations — service restarts, installs, config-diff | Not started |
| Phase 3 | Rollouts and controlled multi-host change | Not started |

---

## Current Phase: Phase 1 — Safe Visibility

**Goal:** The system can explain the network and the server before it changes anything.

Phase 1 is complete when a maintainer can:
- Activate the workspace
- Receive a summary of the architecture
- Inspect mesh node status and health
- Inspect local server and service status
- Diagnose a basic incident using the system
- Find a playbook for common operations
- Understand what is missing or incomplete

**Phase 1 is not complete until Phase 1 has been reviewed and accepted by a maintainer.**

---

## What Is In Scope Right Now

### Group A — Root context files (this session)

These are the files currently being created by Codex-A.

| File | Status |
|------|--------|
| `AGENTS.md` | Created |
| `SOUL.md` | Created |
| `TOOLS.md` | Created |
| `MEMORY.md` | Created |
| `WORKING.md` | Created (this file) |

### Group B — Inventories and desired state

Delegated to Codex-B. Status: pending review.

| File | Expected status |
|------|----------------|
| `inventories/mesh-nodes.yaml` | Created — pending review |
| `inventories/sites.yaml` | Created — pending review |
| `inventories/gateways.yaml` | Created — pending review |
| `inventories/local-services.yaml` | Created — pending review |
| `inventories/hardware-models.yaml` | Created — pending review |
| `desired-state/mesh/community-profile/rollout-policy.yaml` | Created — pending review |
| `desired-state/mesh/firmware-policy.yaml` | Created — pending review |
| `desired-state/server/service-catalog.yaml` | Created — pending review |
| `desired-state/server/hosts.yaml` | Created — pending review |
| `desired-state/server/domains.yaml` | Created — pending review |
| `desired-state/server/reverse-proxy.yaml` | Created — pending review |
| `desired-state/server/backup-policy.yaml` | Created — pending review |

### Group C — Documentation

Delegated to Codex-C. Status: pending review.

| File | Expected status |
|------|----------------|
| `docs/architecture.md` | Created — pending review |
| `docs/deployment.md` | Created — pending review |
| `docs/troubleshooting.md` | Created — pending review |
| `docs/playbooks/node-onboarding.md` | Created — pending review |
| `docs/playbooks/firmware-rollout.md` | Created — pending review |
| `docs/playbooks/local-service-install.md` | Created — pending review |

### Group D — Skills

Delegated to Codex-D. Status: pending review.

| File | Expected status |
|------|----------------|
| `skills/community-ops-frontdesk/SKILL.md` | Created — pending review |
| `skills/mesh-readonly/SKILL.md` | Created — pending review |
| `skills/server-readonly/SKILL.md` | Created — pending review |
| `skills/incident-triage/SKILL.md` | Created — pending review |
| `skills/knowledge-curator/SKILL.md` | Created — pending review |
| `skills/voice-friendly-response/SKILL.md` | Created — pending review |
| `skills/mesh-rollout/SKILL.md` | Created — pending review |
| `skills/mesh-onboarding/SKILL.md` | Created — pending review |
| `skills/server-services/SKILL.md` | Created — pending review |
| `secrets/README.md` | Created — pending review |

---

## What Is Not In Scope Yet

The following belong to Phase 2 and Phase 3. Do not begin these until Phase 1 is reviewed and accepted.

### Phase 2 (not started)
- Bootstrap scripts (`scripts/bootstrap.sh`, `scripts/bootstrap.ps1`, `scripts/bootstrap.mjs`, `scripts/doctor.sh`, `scripts/activate-workspace.sh`)
- Mesh adapter stubs (`adapters/mesh/`, `adapters/server/`, `adapters/channels/`)
- Mesh-rollout execution scripts (`skills/mesh-rollout/scripts/`)
- Server-services execution scripts (`skills/server-services/scripts/`)
- Mesh-readonly live adapters (`skills/mesh-readonly/adapters/`)
- Service restart flows
- Config-diff explanation flows
- Simple node onboarding helpers

### Phase 3 (not started)
- Canary firmware upgrade orchestration
- Staged multi-node change workflows
- Rollback automation hooks
- Scheduled maintenance window management
- Dashboards and analytics

---

## Active Agents in This Session

| Agent ID | Role | Current Task |
|----------|------|-------------|
| Codex-A | Root context file generator | Completed — AGENTS.md, SOUL.md, TOOLS.md, MEMORY.md, WORKING.md |
| Codex-B | Inventory and desired-state generator | Completed |
| Codex-C | Documentation generator | Completed |
| Codex-D | Skills generator | Completed |

---

## Pending Decisions

The following questions must be answered by a maintainer before the system can be fully configured. None of these block Phase 1 completion, but they will be required before Phase 2.

1. **Community name and language** — What is the community called? What language(s) should the system use by default?
2. **Site list** — What are the actual site names and locations to populate `inventories/sites.yaml`?
3. **Node inventory** — What router nodes currently exist? Hardware model, hostname, and IP for each.
4. **Gateway and uplink details** — What internet connections serve the mesh?
5. **Local server(s)** — What server(s) exist? What services are currently running?
6. **Authorized maintainers** — Who can approve Class C and D changes? What chat accounts are theirs?
7. **Preferred chat channels** — WhatsApp or Telegram? Which group(s) for alerts? Which for approvals?
8. **Hardware models** — What router hardware is in use? (To populate `inventories/hardware-models.yaml`)
9. **Firmware policy** — What firmware version or build is considered stable for each hardware model?
10. **Service catalog** — What local services are approved for installation?

---

## Known Gaps at This Time

- No live infrastructure data has been collected yet. All inventories are stubs.
- No real desired-state files exist yet. They will be created as stubs in Phase 1 and filled in after maintainer input.
- No skills are wired to real infrastructure. Phase 1 skills are documentation-only.
- No secrets or credentials have been configured. The system cannot connect to any router or server yet.
- Bootstrap scripts do not exist yet.

---

## Blockers

None at this time. Phase 1 is proceeding.

---

## Next Actions After This Session

1. Review all Phase 1 files for correctness and completeness
2. Have a maintainer answer the pending decisions listed above
3. Populate inventories with real data once site information is available
4. Begin Phase 2 planning only after Phase 1 is accepted
5. Do not connect the system to real infrastructure until credentials are configured per `secrets/README.md`

---

## Notes for the Next Agent or Maintainer

- All Phase 1 files are intentional stubs — they have correct structure and real content, but they describe the architecture, not a live deployment
- Real data (node IPs, site names, firmware versions, etc.) must be added by a maintainer who knows the environment
- `BOOTSTRAP.md` is the source of truth for all architectural decisions
- TASKS.md is the per-session task registry used by the Codex agents during bootstrap. It is not a permanent workspace component — it tracks work-in-progress and can be archived after Phase 1 is accepted.
- If a file in this list is missing when you read this, it has not been created yet — check TASKS.md for status
