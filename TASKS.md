# TASKS.md — Mesha Bootstrap Task Registry

Source of truth: `BOOTSTRAP.md`
Phase: **1 — Safe Visibility**

---

## Task Groups

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

## Phase 2 Tasks (not yet started)
- [ ] Bootstrap scripts (`scripts/bootstrap.sh`, `.ps1`, `.mjs`, `doctor.sh`, `activate-workspace.sh`)
- [ ] Skill adapter stubs (`adapters/mesh/`, `adapters/server/`, `adapters/channels/`)
- [ ] Mesh-rollout scripts (`skills/mesh-rollout/scripts/`)
- [ ] Server-services scripts (`skills/server-services/scripts/`)
- [ ] Mesh-readonly adapters (`skills/mesh-readonly/adapters/`)

---

## Notes
- All Phase 1 files are scaffolds — stubs with correct structure and intent, not production-ready implementations
- BOOTSTRAP.md is the canonical source of truth for content
- Do not start Phase 2 until Phase 1 is reviewed and accepted
