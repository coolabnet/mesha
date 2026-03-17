# WORKING.md — Mesha Current Working State

Source of truth: `BOOTSTRAP.md`
Last updated: 2026-03-17

---

Last synced: 2026-03-17 — all three phases scaffolded and committed. See PROGRESS.md for full phase breakdown.

## Overall Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Safe Visibility — workspace scaffold and read-only operations | Complete |
| Phase 2 | Approved low-risk operations — service restarts, installs, config-diff | Complete |
| Phase 3 | Rollouts and controlled multi-host change | Complete |

---

## Phase 1 — Safe Visibility (Complete)

All Phase 1 files exist on disk. The workspace scaffold is complete: root context files, inventories, desired-state stubs, documentation, and skill definitions.

| Group | Files | Status |
|-------|-------|--------|
| A — Root context files | AGENTS.md, SOUL.md, TOOLS.md, MEMORY.md, WORKING.md | Complete |
| B — Inventories + desired state | 12 YAML files | Complete |
| C — Documentation | 6 docs + additional playbooks and site notes | Complete |
| D — Skills | 9 SKILL.md files + secrets/README.md | Complete |

---

## Phase 2 — Approved Low-Risk Operations (Complete)

Phase 2 deliverables are on disk.

| Deliverable | Location | Status |
|-------------|----------|--------|
| Bootstrap scripts | `scripts/` (bootstrap.sh, bootstrap.ps1, bootstrap.mjs, doctor.sh, activate-workspace.sh) | Complete |
| Mesh adapters | `adapters/mesh/` (collect-nodes.sh, collect-topology.sh, normalize.py) | Complete |
| Server adapters | `adapters/server/` (collect-health.sh, collect-services.sh) | Complete |
| Channel adapter — Telegram | `adapters/channels/telegram/` (adapter.mjs, health.mjs, docker-compose.yaml, README.md) | Complete |
| Channel adapter README | `adapters/channels/README.md` | Complete |
| Mesh-rollout scripts | `skills/mesh-rollout/scripts/` (run-rollout.sh, stage-upgrade.sh, validate-node.sh, rollback-node.sh, check-drift.sh, schedule-maintenance.sh) | Complete |
| Server-services scripts | `skills/server-services/scripts/` (nextcloud, jellyfin, kolibri, homer, prometheus install recipes + create-network.sh + README.md) | Complete |
| Mesh-onboarding templates | `skills/mesh-onboarding/templates/` (node-checklist.md, site-metadata-form.md) | Complete |
| Node override example | `desired-state/mesh/node-overrides/lm-escola-telhado.uci` | Complete |
| Maintenance windows desired state | `desired-state/mesh/maintenance-windows.yaml` | Complete |
| Rollout state tracking | `desired-state/mesh/rollout-state.yaml` | Complete |
| Additional playbooks | `docs/playbooks/incident-response.md`, `maintenance-window.md`, `rollout-orchestration.md` | Complete |
| Site notes | `docs/sites/escola-municipal.md`, `clinica-do-bairro.md`, `README.md` | Complete |
| Service onboarding guides | `docs/onboarding/nextcloud.md`, `jellyfin.md`, `kolibri.md` | Complete |
| Known issues | `docs/known-issues/tplink-wr841n-power-loss.md`, `channel-congestion-2ghz.md`, `README.md` | Complete |

---

## Phase 3 — Rollouts and Controlled Change (Complete)

Phase 3 deliverables are on disk.

| Deliverable | Location | Status |
|-------------|----------|--------|
| Monitoring desired state | `desired-state/server/monitoring/prometheus.yml`, `alerting-rules.yaml`, `grafana-dashboards/community-overview.json` | Complete |
| Rollout orchestration playbook | `docs/playbooks/rollout-orchestration.md` | Complete |
| Maintenance window playbook | `docs/playbooks/maintenance-window.md` | Complete |
| Canary and staged upgrade scripts | `skills/mesh-rollout/scripts/` (stage-upgrade.sh, validate-node.sh, rollback-node.sh, schedule-maintenance.sh) | Complete (shared with Phase 2) |

---

## Pending Decisions

The following questions must be answered by a maintainer before the system can be connected to real infrastructure. None block workspace coherence, but all are required before live operations.

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

- All inventories contain example/stub data. Real node IPs, site names, firmware versions, and service details must be added by a maintainer who knows the environment.
- No secrets or credentials have been configured. The system cannot connect to any router or server until `secrets/` is populated per `secrets/README.md`.
- `logs/` directory does not exist yet — it is created on first approved write action. Subdirectories needed: `logs/incidents/`, `logs/maintenance/`, `logs/decisions/`, `logs/channel-errors/`.
- `exports/` directory does not exist yet — it is created when the first snapshot is exported.
- The Telegram adapter (`adapters/channels/telegram/`) requires a bot token in `secrets/telegram.env` before it can operate.
- No live infrastructure data has been collected. All desired-state files are stubs.

---

## Blockers

None. All three phases are complete. The workspace is ready for a maintainer to supply real infrastructure data and credentials.

---

## Next Actions

1. Review all workspace files for correctness against your actual environment
2. Populate inventories with real data (nodes, sites, gateways, services)
3. Configure `secrets/` per `secrets/README.md`
4. Set up the Telegram bot per `adapters/channels/telegram/README.md`
5. Run `scripts/doctor.sh` on the target host to verify prerequisites
6. Activate the workspace using the prompt in `BOOTSTRAP.md`

---

## Notes for the Next Agent or Maintainer

- All Phase 1–3 files are scaffolds — they have correct structure and real content, but they describe an example environment, not a live deployment
- Real data must be added by a maintainer who knows the actual infrastructure
- `BOOTSTRAP.md` is the source of truth for all architectural decisions
- `PROGRESS.md` contains the full phase completion record with agent dispatch log
- `TASKS.md` is the per-file task registry used by bootstrap agents — it covers all three phases and is now an archive record
