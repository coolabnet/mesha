# TASKS.md — Mesha Bootstrap Task Registry

Source of truth: `BOOTSTRAP.md`
All three phases complete as of 2026-03-16.

---

## Summary

| Phase | Description | Groups | Files | Status |
|-------|-------------|--------|-------|--------|
| Phase 1 | Safe Visibility | A–D | 33 | ✅ complete |
| Phase 2 | Approved Low-Risk Operations | E–H | 32 | ✅ complete |
| Phase 3 | Rollouts and Controlled Change | I–L | 25 | ✅ complete |

---

## Phase 1 — Safe Visibility

### GROUP A — Root Context Files
| ID | File | Status | Agent |
|----|------|--------|-------|
| A1 | `AGENTS.md` | ✅ done | Codex-A |
| A2 | `SOUL.md` | ✅ done | Codex-A |
| A3 | `TOOLS.md` | ✅ done | Codex-A |
| A4 | `MEMORY.md` | ✅ done | Codex-A |
| A5 | `WORKING.md` | ✅ done | Codex-A |

### GROUP B — Inventories + Desired State
| ID | File | Status | Agent |
|----|------|--------|-------|
| B1 | `inventories/mesh-nodes.yaml` | ✅ done | Codex-B |
| B2 | `inventories/sites.yaml` | ✅ done | Codex-B |
| B3 | `inventories/gateways.yaml` | ✅ done | Codex-B |
| B4 | `inventories/local-services.yaml` | ✅ done | Codex-B |
| B5 | `inventories/hardware-models.yaml` | ✅ done | Codex-B |
| B6 | `desired-state/mesh/community-profile/rollout-policy.yaml` | ✅ done | Codex-B |
| B7 | `desired-state/mesh/firmware-policy.yaml` | ✅ done | Codex-B |
| B8 | `desired-state/server/service-catalog.yaml` | ✅ done | Codex-B |
| B9 | `desired-state/server/hosts.yaml` | ✅ done | Codex-B |
| B10 | `desired-state/server/domains.yaml` | ✅ done | Codex-B |
| B11 | `desired-state/server/reverse-proxy.yaml` | ✅ done | Codex-B |
| B12 | `desired-state/server/backup-policy.yaml` | ✅ done | Codex-B |

### GROUP C — Documentation
| ID | File | Status | Agent |
|----|------|--------|-------|
| C1 | `docs/architecture.md` | ✅ done | Codex-C |
| C2 | `docs/deployment.md` | ✅ done | Codex-C |
| C3 | `docs/troubleshooting.md` | ✅ done | Codex-C |
| C4 | `docs/playbooks/node-onboarding.md` | ✅ done | Codex-C |
| C5 | `docs/playbooks/firmware-rollout.md` | ✅ done | Codex-C |
| C6 | `docs/playbooks/local-service-install.md` | ✅ done | Codex-C |

### GROUP D — Skills
| ID | File | Status | Agent |
|----|------|--------|-------|
| D1 | `skills/community-ops-frontdesk/SKILL.md` | ✅ done | Codex-D |
| D2 | `skills/mesh-readonly/SKILL.md` | ✅ done | Codex-D |
| D3 | `skills/server-readonly/SKILL.md` | ✅ done | Codex-D |
| D4 | `skills/incident-triage/SKILL.md` | ✅ done | Codex-D |
| D5 | `skills/knowledge-curator/SKILL.md` | ✅ done | Codex-D |
| D6 | `skills/voice-friendly-response/SKILL.md` | ✅ done | Codex-D |
| D7 | `skills/mesh-rollout/SKILL.md` | ✅ done | Codex-D |
| D8 | `skills/mesh-onboarding/SKILL.md` | ✅ done | Codex-D |
| D9 | `skills/server-services/SKILL.md` | ✅ done | Codex-D |
| D10 | `secrets/README.md` | ✅ done | Codex-D |

---

## Phase 2 — Approved Low-Risk Operations

### GROUP E — Bootstrap Scripts
| ID | File | Status |
|----|------|--------|
| E1 | `scripts/bootstrap.sh` | ✅ done |
| E2 | `scripts/bootstrap.ps1` | ✅ done |
| E3 | `scripts/bootstrap.mjs` | ✅ done |
| E4 | `scripts/doctor.sh` | ✅ done |
| E5 | `scripts/activate-workspace.sh` | ✅ done |

### GROUP F — LibreMesh Config + Adapters
| ID | File | Status |
|----|------|--------|
| F1 | `desired-state/mesh/community-profile/lime-community` | ✅ done |
| F2 | `desired-state/mesh/community-profile/defaults-notes.md` | ✅ done |
| F3 | `desired-state/mesh/node-overrides/README.md` | ✅ done |
| F4 | `desired-state/mesh/node-overrides/lm-escola-telhado.uci` | ✅ done |
| F5 | `adapters/mesh/collect-nodes.sh` | ✅ done |
| F6 | `adapters/mesh/collect-topology.sh` | ✅ done |
| F7 | `adapters/mesh/normalize.py` | ✅ done |
| F8 | `adapters/server/collect-health.sh` | ✅ done |
| F9 | `adapters/server/collect-services.sh` | ✅ done |
| F10 | `adapters/channels/README.md` | ✅ done |

### GROUP G — Service Recipes
| ID | File | Status |
|----|------|--------|
| G1 | `skills/server-services/scripts/README.md` | ✅ done |
| G2 | `skills/server-services/scripts/nextcloud/install.sh` | ✅ done |
| G3 | `skills/server-services/scripts/nextcloud/docker-compose.yaml` | ✅ done |
| G4 | `skills/server-services/scripts/jellyfin/install.sh` | ✅ done |
| G5 | `skills/server-services/scripts/jellyfin/docker-compose.yaml` | ✅ done |
| G6 | `skills/server-services/scripts/kolibri/install.sh` | ✅ done |
| G7 | `skills/server-services/scripts/kolibri/docker-compose.yaml` | ✅ done |
| G8 | `skills/server-services/scripts/create-network.sh` | ✅ done |

### GROUP H — Mesh Rollout Scripts + Onboarding Templates + User Docs
| ID | File | Status |
|----|------|--------|
| H1 | `skills/mesh-rollout/scripts/run-rollout.sh` | ✅ done |
| H2 | `skills/mesh-rollout/scripts/stage-upgrade.sh` | ✅ done |
| H3 | `skills/mesh-rollout/scripts/validate-node.sh` | ✅ done |
| H4 | `skills/mesh-rollout/scripts/rollback-node.sh` | ✅ done |
| H5 | `skills/mesh-onboarding/templates/node-checklist.md` | ✅ done |
| H6 | `skills/mesh-onboarding/templates/site-metadata-form.md` | ✅ done |
| H7 | `docs/onboarding/nextcloud.md` | ✅ done |
| H8 | `docs/onboarding/jellyfin.md` | ✅ done |
| H9 | `docs/onboarding/kolibri.md` | ✅ done |

---

## Phase 3 — Rollouts and Controlled Change

### GROUP I — Rollout Orchestration + Desired-State Extensions
| ID | File | Status |
|----|------|--------|
| I1 | `skills/mesh-rollout/scripts/schedule-maintenance.sh` | ✅ done |
| I2 | `skills/mesh-rollout/scripts/check-drift.sh` | ✅ done |
| I3 | `desired-state/mesh/rollout-state.yaml` | ✅ done |
| I4 | `desired-state/mesh/maintenance-windows.yaml` | ✅ done |

### GROUP J — Telegram Channel Adapter
| ID | File | Status |
|----|------|--------|
| J1 | `adapters/channels/telegram/README.md` | ✅ done |
| J2 | `adapters/channels/telegram/adapter.mjs` | ✅ done |
| J3 | `adapters/channels/telegram/docker-compose.yaml` | ✅ done |
| J4 | `adapters/channels/telegram/health.mjs` | ✅ done |

### GROUP K — Homer Dashboard + Prometheus/Grafana Monitoring
| ID | File | Status |
|----|------|--------|
| K1 | `skills/server-services/scripts/homer/install.sh` | ✅ done |
| K2 | `skills/server-services/scripts/homer/docker-compose.yaml` | ✅ done |
| K3 | `skills/server-services/scripts/homer/config/config.yaml` | ✅ done |
| K4 | `skills/server-services/scripts/prometheus/install.sh` | ✅ done |
| K5 | `skills/server-services/scripts/prometheus/docker-compose.yaml` | ✅ done |
| K6 | `desired-state/server/monitoring/prometheus.yml` | ✅ done |
| K7 | `desired-state/server/monitoring/alerting-rules.yaml` | ✅ done |
| K8 | `desired-state/server/monitoring/grafana-dashboards/community-overview.json` | ✅ done |

### GROUP L — Site Notes + Playbooks + Known Issues
| ID | File | Status |
|----|------|--------|
| L1 | `docs/sites/README.md` | ✅ done |
| L2 | `docs/sites/escola-municipal.md` | ✅ done |
| L3 | `docs/sites/clinica-do-bairro.md` | ✅ done |
| L4 | `docs/playbooks/incident-response.md` | ✅ done |
| L5 | `docs/playbooks/maintenance-window.md` | ✅ done |
| L6 | `docs/playbooks/rollout-orchestration.md` | ✅ done |
| L7 | `docs/known-issues/README.md` | ✅ done |
| L8 | `docs/known-issues/channel-congestion-2ghz.md` | ✅ done |
| L9 | `docs/known-issues/tplink-wr841n-power-loss.md` | ✅ done |

---

## Tracking Files

| File | Purpose | Status |
|------|---------|--------|
| `TASKS.md` | Task registry — groups, IDs, per-file status across all phases | ✅ up to date (this file) |
| `PROGRESS.md` | High-level phase completion and agent dispatch log | ✅ reflects all 3 phases complete — agent log covers Phase 1 only; Phases 2–3 were not dispatched via named agents |
| `BOOTSTRAP.md` | Canonical architecture, design principles, and phase definitions | ✅ authoritative — no changes needed |

Note: PROGRESS.md marks all three phases complete but its agent dispatch log was not updated to record Phase 2 and Phase 3 work. That log should be filled in when authorship is known.

---

## Phase 4 / Future Work

Items not yet implemented. Left for future maintainers.

### Workspace and tooling
- `scripts/bootstrap.mjs` — cross-platform Node.js bootstrap is present but may need testing on all three platforms (Linux, macOS, Windows+WSL2)
- Automated doctor/health-check integration with the frontdesk agent (currently `scripts/doctor.sh` is standalone)
- Workspace activation verification script that confirms all SKILL.md files are loaded

### Mesh operations
- `adapters/mesh/normalize.py` — normalization logic for node snapshots is stubbed; needs real LibreMesh/OpenWrt field testing
- `skills/mesh-readonly/` — no adapter scripts yet under this skill directory; relies on `adapters/mesh/` but no direct wiring documented
- Per-hardware-model override examples beyond the single `lm-escola-telhado.uci` example in `desired-state/mesh/node-overrides/`
- Automated config-drift report generation and diff output formatting
- Upgrade ring definitions in `desired-state/mesh/firmware-policy.yaml` (structure exists, may need community-specific ring assignments)

### Server and services
- `server-readonly` skill scripts — `skills/server-readonly/` contains only `SKILL.md`; no adapter scripts present
- Additional service recipes: Matrix/Element, Gitea, PeerTube, or other community-requested apps
- Backup/restore execution scripts (policy in `desired-state/server/backup-policy.yaml` exists; no executor scripts yet)
- Reverse proxy auto-configuration script driven from `desired-state/server/reverse-proxy.yaml`
- Local DNS/naming automation

### Monitoring and dashboards
- Grafana provisioning automation (dashboard JSON exists; no auto-provisioning script)
- Alertmanager configuration for Telegram or WhatsApp notifications
- Node exporter setup on mesh gateways for Prometheus scraping

### Channel adapters
- WhatsApp adapter (only Telegram is implemented)
- Approval gate wiring: high-risk action approvals routed through a named maintainer DM path
- Non-main session sandboxing for public or untrusted chat groups

### Documentation and governance
- Incident log template and example entries under `docs/` or `logs/`
- Training materials for new community volunteers
- Decision log template for recording change approvals
- Localization/translation of key user-facing docs into community language(s)

### Security and secrets management
- `secrets/` directory currently holds only a README; a real secrets management integration (e.g. pass, age, or environment-based injection) should be documented and scripted
- SSH key management guidance for maintainer access to routers and servers

---

## Notes

- All files across all phases are scaffolds — correct structure and intent, not all production-ready implementations
- `BOOTSTRAP.md` is the canonical source of truth for architecture and phase definitions
- Do not skip desired-state review before executing any mesh or server changes
