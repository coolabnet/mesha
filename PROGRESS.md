# PROGRESS.md — Mesha Bootstrap Progress

Last updated: 2026-03-17

---

## Overall Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Safe Visibility — workspace scaffold | ✅ complete — reviewed + committed |
| Phase 2 | Approved low-risk operations — scripts, adapters, service recipes | ✅ complete — reviewed + committed |
| Phase 3 | Rollouts and controlled change — orchestration, Telegram, monitoring | ✅ complete — reviewed + committed |

---

## Phase 1 Progress — Safe Visibility

| Group | Description | Files | Done | Status |
|-------|-------------|-------|------|--------|
| A | Root context files | 5 | 5 | ✅ complete |
| B | Inventories + desired state | 12 | 12 | ✅ complete |
| C | Documentation | 6 | 6 | ✅ complete |
| D | Skills (SKILL.md files + secrets) | 10 | 10 | ✅ complete |
| **Total** | | **33** | **33** | ✅ complete |

**Group A — Root context files**
- `AGENTS.md`, `SOUL.md`, `TOOLS.md`, `MEMORY.md`, `WORKING.md`

**Group B — Inventories + desired state**
- `inventories/mesh-nodes.yaml`, `sites.yaml`, `gateways.yaml`, `local-services.yaml`, `hardware-models.yaml`
- `desired-state/mesh/community-profile/rollout-policy.yaml`, `firmware-policy.yaml`
- `desired-state/server/service-catalog.yaml`, `hosts.yaml`, `domains.yaml`, `reverse-proxy.yaml`, `backup-policy.yaml`

**Group C — Documentation**
- `docs/architecture.md`, `deployment.md`, `troubleshooting.md`
- `docs/playbooks/node-onboarding.md`, `firmware-rollout.md`, `local-service-install.md`

**Group D — Skills**
- `skills/community-ops-frontdesk/SKILL.md`, `mesh-readonly/SKILL.md`, `server-readonly/SKILL.md`
- `skills/incident-triage/SKILL.md`, `knowledge-curator/SKILL.md`, `voice-friendly-response/SKILL.md`
- `skills/mesh-rollout/SKILL.md`, `mesh-onboarding/SKILL.md`, `server-services/SKILL.md`
- `secrets/README.md`

---

## Phase 2 Progress — Approved Low-Risk Operations

| Group | Description | Files | Done | Status |
|-------|-------------|-------|------|--------|
| E | Bootstrap + maintenance scripts | 5 | 5 | ✅ complete |
| F | Mesh + server adapters | 6 | 6 | ✅ complete |
| G | Mesh desired state + rollout scripts (canary stage) + onboarding templates | 9 | 9 | ✅ complete |
| H | Server service recipes (Nextcloud, Jellyfin, Kolibri) + user onboarding docs | 14 | 14 | ✅ complete |
| **Total** | | **34** | **34** | ✅ complete |

**Group E — Bootstrap + maintenance scripts**
- `scripts/bootstrap.sh`, `bootstrap.ps1`, `bootstrap.mjs`, `doctor.sh`, `activate-workspace.sh`

**Group F — Mesh + server adapters**
- `adapters/mesh/collect-nodes.sh`, `collect-topology.sh`, `normalize.py`
- `adapters/server/collect-health.sh`, `collect-services.sh`
- `adapters/channels/README.md`

**Group G — Mesh desired state + rollout scripts + onboarding templates**
- `desired-state/mesh/community-profile/lime-community`, `defaults-notes.md`
- `desired-state/mesh/node-overrides/README.md`, `lm-escola-telhado.uci`
- `skills/mesh-rollout/scripts/stage-upgrade.sh`, `validate-node.sh`, `rollback-node.sh`
- `skills/mesh-onboarding/templates/node-checklist.md`, `site-metadata-form.md`

**Group H — Service recipes + user onboarding docs**
- `skills/server-services/scripts/README.md`, `create-network.sh`
- Nextcloud: `docker-compose.yaml`, `install.sh`, `.env.example`
- Jellyfin: `docker-compose.yaml`, `install.sh`, `.env.example`
- Kolibri: `docker-compose.yaml`, `install.sh`, `.env.example`
- `docs/onboarding/nextcloud.md`, `jellyfin.md`, `kolibri.md`

---

## Phase 3 Progress — Rollouts and Controlled Change

| Group | Description | Files | Done | Status |
|-------|-------------|-------|------|--------|
| I | Rollout orchestration scripts + state files | 5 | 5 | ✅ complete |
| J | Telegram channel adapter | 5 | 5 | ✅ complete |
| K | Homer dashboard + Prometheus/Grafana monitoring stack | 9 | 9 | ✅ complete |
| L | Site notes + rollout playbooks + known-issues catalog | 9 | 9 | ✅ complete |
| **Total** | | **28** | **28** | ✅ complete |

**Group I — Rollout orchestration scripts + state**
- `skills/mesh-rollout/scripts/run-rollout.sh`, `schedule-maintenance.sh`, `check-drift.sh`
- `desired-state/mesh/rollout-state.yaml`, `maintenance-windows.yaml`

**Group J — Telegram channel adapter**
- `adapters/channels/telegram/adapter.mjs`, `health.mjs`, `docker-compose.yaml`
- `adapters/channels/telegram/.env.example`, `README.md`

**Group K — Homer dashboard + Prometheus/Grafana monitoring**
- `skills/server-services/scripts/homer/docker-compose.yaml`, `install.sh`, `config/config.yaml`
- `skills/server-services/scripts/prometheus/docker-compose.yaml`, `install.sh`, `.env.example`
- `desired-state/server/monitoring/prometheus.yml`, `alerting-rules.yaml`
- `desired-state/server/monitoring/grafana-dashboards/community-overview.json`

**Group L — Site notes + playbooks + known-issues**
- `docs/sites/README.md`, `escola-municipal.md`, `clinica-do-bairro.md`
- `docs/playbooks/maintenance-window.md`, `rollout-orchestration.md`, `incident-response.md`
- `docs/known-issues/README.md`, `tplink-wr841n-power-loss.md`, `channel-congestion-2ghz.md`

---

## Agent Dispatch Log

### Phase 1 Builder Agents

| Agent | Group | Dispatched | Completed | Notes |
|-------|-------|------------|-----------|-------|
| Codex-A | A — Root context files | 2026-03-16 | 2026-03-16 | 5 files: AGENTS/SOUL/TOOLS/MEMORY/WORKING; 7-agent roster, risk classes, community tone |
| Codex-B | B — Inventories + desired state | 2026-03-16 | 2026-03-16 | 12 YAML files; example data for Escola Municipal + Clínica do Bairro community |
| Codex-C | C — Documentation | 2026-03-16 | 2026-03-16 | 6 docs; 3-layer ASCII architecture diagram, deployment paths, troubleshooting structure |
| Codex-D | D — Skills | 2026-03-16 | 2026-03-16 | 9 SKILL.md files + secrets/README.md; safety guardrails verified per BOOTSTRAP.md |

### Phase 1 Reviewer Agents

| Agent | Group | Dispatched | Completed | Notes |
|-------|-------|------------|-----------|-------|
| Review-A | A — Root context files | 2026-03-16 | 2026-03-16 | Approval table split into B-infra/B-doc; maintainer list given a home in AGENTS.md |
| Review-B | B — Inventories + desired state | 2026-03-16 | 2026-03-16 | YAML cross-references validated (role, firmware version, service names) |
| Review-C | C — Documentation | 2026-03-16 | 2026-03-16 | UCI backup/restore commands corrected in firmware-rollout playbook; cat\|grep antipatterns removed |
| Review-D | D — Skills | 2026-03-16 | 2026-03-16 | mesh-onboarding/mesh-rollout scope boundaries made explicit |

### Phase 2 Builder Agents

| Agent | Group | Dispatched | Completed | Notes |
|-------|-------|------------|-----------|-------|
| Codex-E | E — Bootstrap scripts | 2026-03-17 | 2026-03-17 | 5 scripts; Linux/macOS/WSL2 paths; coloured output; --check-only flag on bootstrap.sh |
| Codex-F | F — Mesh + server adapters | 2026-03-17 | 2026-03-17 | 6 files; SSH node collector, topology snapshot, Python normalizer, host health + service checks |
| Codex-G | G — Mesh desired state + rollout scripts | 2026-03-17 | 2026-03-17 | 9 files; UCI lime-community config, node-override pattern, canary stage-upgrade + validate + rollback |
| Codex-H | H — Service recipes + user docs | 2026-03-17 | 2026-03-17 | 14 files; Nextcloud/Jellyfin/Kolibri compose stacks, install scripts, plain-language user guides |

### Phase 2 Reviewer Agents

| Agent | Group | Dispatched | Completed | Notes |
|-------|-------|------------|-----------|-------|
| Review-E | E — Bootstrap scripts | 2026-03-17 | 2026-03-17 | find operator grouping bug fixed in doctor.sh; ls antipattern removed from activate-workspace.sh |
| Review-F | F — Adapters | 2026-03-17 | 2026-03-17 | SSH_OPTS word-splitting fixed (string→array); Python 3.9 Optional compat; memory field dedup |
| Review-G | G — Mesh scripts | 2026-03-17 | 2026-03-17 | StrictHostKeyChecking=yes hardened; bmx7 --links (not --neighbors); busybox nc compat |
| Review-H | H — Service recipes | 2026-03-17 | 2026-03-17 | DB conflict resolved (MariaDB throughout); duplicate Nextcloud volume mount removed; domain URLs corrected |

### Phase 3 Builder Agents

| Agent | Group | Dispatched | Completed | Notes |
|-------|-------|------------|-----------|-------|
| Codex-I | I — Rollout orchestration | 2026-03-17 | 2026-03-17 | 5 files; ring-based run-rollout.sh with --dry-run/--ring/--resume; schedule-maintenance + check-drift |
| Codex-J | J — Telegram adapter | 2026-03-17 | 2026-03-17 | 5 files; long-polling + webhook, trust level by numeric user IDs, zero npm deps, rate-limit backoff |
| Codex-K | K — Homer + monitoring stack | 2026-03-17 | 2026-03-17 | 9 files; Homer dashboard pre-wired to community services; Prometheus + Grafana + node + blackbox exporters |
| Codex-L | L — Site docs + playbooks + known-issues | 2026-03-17 | 2026-03-17 | 9 files; P1/P2/P3 incident-response with PT templates; site notes for 2 community locations |

### Phase 3 Reviewer Agents

| Agent | Group | Dispatched | Completed | Notes |
|-------|-------|------------|-----------|-------|
| Review-I | I — Rollout orchestration | 2026-03-17 | 2026-03-17 | stage-upgrade.sh --auto flag added; check-drift.sh rewrote to delegate to validate-node.sh; timestamp quoting fixed |
| Review-J | J — Telegram adapter | 2026-03-17 | 2026-03-17 | WEBHOOK_PORT added to .env.example; ERROR logs routed to stderr; token never logged verified |
| Review-K | K — Monitoring stack | 2026-03-17 | 2026-03-17 | ServiceDown alert fixed (up→probe_success); Grafana datasource uid hardened; Homer port 8081→8080 across all files |
| Review-L | L — Site docs + playbooks | 2026-03-17 | 2026-03-17 | UCI watchdog syntax corrected; emergency window cross-ref added to incident-response; script paths in quick-reference table fixed |

---

## Review Status

| Phase | Reviewed by | Date | Outcome |
|-------|-------------|------|---------|
| Phase 1 | 4 specialist reviewer agents | 2026-03-16 | Passed — 5 fixes applied pre-commit |
| Phase 2 | 4 specialist reviewer agents | 2026-03-17 | Passed — 6 fixes applied pre-commit |
| Phase 3 | 4 specialist reviewer agents | 2026-03-17 | Passed — 7 fixes applied pre-commit |

---

## Git History

| Commit | Date | Message |
|--------|------|---------|
| `5082279` | 2026-03-16 | feat: scaffold Phase 1 bootstrap for Mesha Community Infrastructure Operator |
| `eac8f3c` | 2026-03-17 | feat: Phase 2 — scripts, adapters, service recipes, mesh tooling |
| `adb56e9` | 2026-03-17 | feat: Phase 3 — rollout orchestration, Telegram adapter, monitoring, site docs |

---

## Blockers

*None. All 3 phases complete.*

---

## Next Actions

The scaffold is done. The workspace can be activated as-is using the prompt in `BOOTSTRAP.md`. The following steps are what a maintainer should do **in the real world** to make this operational:

1. **Populate the inventories with real data** — replace example entries in `inventories/mesh-nodes.yaml`, `sites.yaml`, `gateways.yaml`, `local-services.yaml`, and `hardware-models.yaml` with the community's actual nodes, sites, and services.

2. **Set real desired-state values** — update `desired-state/mesh/firmware-policy.yaml`, `rollout-policy.yaml`, and `desired-state/server/service-catalog.yaml` to reflect the community's actual standards and approved services.

3. **Configure the Telegram adapter** — copy `adapters/channels/telegram/.env.example` to `.env`, set a real bot token from @BotFather, set trusted maintainer Telegram user IDs, and run `docker compose up` in that directory.

4. **Run the bootstrap scripts on the target host** — execute `scripts/bootstrap.sh` (Linux/macOS) or follow `scripts/bootstrap.ps1` guidance (Windows/WSL2), then run `scripts/doctor.sh` and `scripts/activate-workspace.sh`.

5. **Install and verify local services** — use `skills/server-services/scripts/` recipes to install Nextcloud, Jellyfin, Kolibri, Homer, and Prometheus/Grafana on the community server; verify with `adapters/server/collect-services.sh`.

6. **Run a first mesh read** — execute `adapters/mesh/collect-nodes.sh` and `adapters/mesh/collect-topology.sh` against real routers and pipe through `adapters/mesh/normalize.py` to get a baseline snapshot.

7. **Do a dry-run rollout** — run `skills/mesh-rollout/scripts/run-rollout.sh --dry-run` to confirm rollout policy is correctly wired before any real firmware change.

8. **Fill in site notes** — update `docs/sites/escola-municipal.md` and `docs/sites/clinica-do-bairro.md` (or add new site files) with accurate hardware, maintainer contacts, and known access details.

9. **Review secrets posture** — read `secrets/README.md` and confirm all real credentials are in a local `.env` or vault, never committed to the repo.

10. **Activate the operator** — use the activation prompt in `BOOTSTRAP.md` to bring up the full Community Infrastructure Operator and confirm it can answer questions about the mesh and local server.
