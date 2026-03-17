# Maintenance Window Playbook

**Purpose:** How to schedule, execute, and close a planned maintenance window for community infrastructure operations.

**Risk class:** Class C or Class D (this playbook covers the window management process for both)

Read this before scheduling any disruptive work. The window is not just a time slot — it is a commitment to the community, a coordination protocol, and a safety boundary.

---

## 1. When is a maintenance window required?

A maintenance window is required for any operation that:

- Is classified **Class D** (firmware rollout, gateway changes, community-wide config changes, mass node operations, backup restore over live data)
- Involves **rebooting a gateway node** (causes a full site outage during reboot)
- Involves **multi-node upgrades** even when individual nodes are Class C
- Has a **known risk of service interruption** lasting more than 5 minutes
- Cannot be **immediately rolled back** if something goes wrong

A maintenance window is recommended (but not strictly required) for:

- Single-node Class C changes at non-critical sites
- Service restarts on the local server that may cause a brief interruption

**When in doubt, schedule a window.** An unscheduled disruption is always worse than a scheduled one that was communicated clearly.

Blackout periods (from `desired-state/mesh/community-profile/rollout-policy.yaml`):
- School exam weeks — check the school calendar
- Thursday evenings 18h30–22h30 (community assembly)
- National and local public holidays

---

## 2. How to schedule a maintenance window

### Step 1 — Confirm the preferred time

Check `desired-state/mesh/community-profile/rollout-policy.yaml` for preferred windows:

| Window | Days | Time (BRT) |
|--------|------|------------|
| Sunday early morning | Sunday | 05h00–08h00 |
| Weeknight low-traffic | Mon–Fri | 22h00–23h30 |

For site-specific constraints (e.g., clinic hours), check the site note in `docs/sites/` before choosing a time.

### Step 2 — Use the scheduling script

```bash
./skills/mesh-rollout/scripts/schedule-maintenance.sh \
  --date "YYYY-MM-DD" \
  --start "HH:MM" \
  --end "HH:MM" \
  --scope "brief description of what will be done" \
  --risk-class "C|D" \
  --approver "name of authorizing maintainer"
```

This script:
- Validates that the proposed time is not in a blackout period
- Creates a draft maintenance entry in `logs/maintenance/`
- Outputs the community notification templates (see Section 4)

### Step 3 — Required advance notice

| Risk class | Minimum advance notice |
|------------|----------------------|
| Class C | 12 hours |
| Class D | 24 hours (48 hours preferred) |
| Emergency window | As much as possible — see Section 5 |

### Step 4 — Notify the community

Send the pre-window message to the community group (template in Section 4) **at least as early as the minimum advance notice** before the window starts.

Also notify the affected site contacts directly if the site will experience an outage. Check `inventories/sites.yaml` and `docs/sites/` for contact information.

### Step 5 — Confirm approval

- Class C: receive written approval from one maintainer via DM
- Class D: receive written approval from the lead maintainer via DM

**Do not begin the window without written approval.** A verbal agreement is not enough. The approval message must be stored in the maintenance log entry.

---

## 3. During the maintenance window

### Step 1 — Pre-window check (required)

Before making any changes, run a drift check to establish a baseline:

```bash
./skills/mesh-rollout/scripts/check-drift.sh
```

Record the output. This is your before-state. If the check reveals unexpected issues (nodes already offline, degraded links), reassess whether it is safe to proceed.

- [ ] Drift check completed
- [ ] No unexpected pre-existing outages
- [ ] All nodes that should be reachable are reachable
- [ ] Rollback firmware or config is staged and verified

### Step 2 — Execute changes

Follow the appropriate playbook for the type of work:
- Firmware rollout: `docs/playbooks/firmware-rollout.md`
- Rollout orchestration with scripts: `docs/playbooks/rollout-orchestration.md`
- Node onboarding: `docs/playbooks/node-onboarding.md`
- Local service install: `docs/playbooks/local-service-install.md`

**Rules during execution:**

1. Make one change at a time unless the approved plan explicitly calls for parallel changes.
2. Validate after each step before moving to the next.
3. Do not skip validation steps to save time.
4. If anything unexpected happens, stop and assess before continuing.
5. Keep the maintenance log entry open and note each step as it completes.

### Step 3 — Validate after each step

After every significant change, confirm:

- [ ] Affected node or service is reachable
- [ ] Node shows correct firmware/config version
- [ ] Mesh topology is intact
- [ ] No new errors in logs (`logread | tail -30` on each affected node)
- [ ] Any service that was restarted has come back up and is responding

---

## 4. Closing the maintenance window

### Step 1 — Final validation

After all planned changes are complete:

```bash
./skills/mesh-rollout/scripts/check-drift.sh
```

Compare the after-state to the before-state (from pre-window check). Confirm:

- [ ] All affected nodes are online and on the expected firmware/config
- [ ] Mesh topology matches expected topology in `inventories/mesh-nodes.yaml`
- [ ] All sites have connectivity
- [ ] No degraded nodes that were healthy before the window
- [ ] Local services (if affected) are reachable

### Step 2 — Write the maintenance log

Complete the maintenance log entry started in Step 1 of Section 3. The minimum record must include:

- Date and time of window (start and end)
- Risk class
- What was planned
- What was actually executed (with any deviations noted)
- Which nodes or services were affected
- Outcome (success / partial / failed + rollback)
- Name of approver and approval channel
- Any observations for future reference

Ask the `knowledge-curator` skill to file the log entry if working through the operator.

### Step 3 — Update inventory if needed

If any node changed firmware version, status, or configuration, update `inventories/mesh-nodes.yaml` to reflect the new state.

### Step 4 — Notify the community

Send the post-window message (template below) to the community group.

---

## Communication templates

### Pre-window message (send before the window)

```
[MANUTENÇÃO PROGRAMADA]

Olá pessoal! Vamos realizar uma manutenção na rede comunitária no horário abaixo:

📅 Data: [DATA]
⏰ Horário: [HORA INÍCIO] – [HORA FIM]
📍 O que será feito: [DESCRIÇÃO BREVE, ex: "atualização do software dos roteadores"]

Durante este período, pode haver interrupção temporária da internet em [SITES AFETADOS].

Qualquer problema fora deste horário ou que dure mais do que [DURAÇÃO ESPERADA], entrem em contato: [CONTATO DO MANTENEDOR].

Obrigado pela compreensão!
— Equipe de Manutenção
```

### Post-window message (send after the window closes)

```
[MANUTENÇÃO CONCLUÍDA]

A manutenção programada foi finalizada às [HORA FIM].

✅ O que foi feito: [DESCRIÇÃO BREVE]
✅ Status da rede: [tudo normal / com ressalvas — descrever brevemente]

Se vocês estiverem com problemas de conexão agora, avisem aqui ou entrem em contato: [CONTATO DO MANTENEDOR].

Obrigado!
— Equipe de Manutenção
```

### Post-window message when something went wrong

```
[ATUALIZAÇÃO DE MANUTENÇÃO]

A manutenção de hoje encontrou um problema.

⚠️ O que aconteceu: [DESCRIÇÃO BREVE DO PROBLEMA]
🔄 O que estamos fazendo: [AÇÃO EM ANDAMENTO, ex: "revertendo a atualização", "aguardando acesso físico ao local"]
📡 Status atual: [SITES AFETADOS] pode estar sem conexão no momento.

Vamos atualizar assim que tivermos mais informações. Estimativa: [HORA ESTIMADA].

Pedimos desculpas pelo inconveniente.
— Equipe de Manutenção
```

---

## 5. Emergency window

An emergency window is used when something breaks outside of a scheduled window and requires a disruptive fix.

### When to declare an emergency window

- A gateway is offline and automatic recovery has not worked after 15 minutes
- A critical service is down and a fix requires rebooting infrastructure
- A security vulnerability requires immediate patching

### Emergency window procedure

1. **Notify the lead maintainer immediately.** Get verbal or message approval to proceed.
2. **Announce in the community group** using the emergency template below.
3. **Run a pre-change check** (check-drift.sh) even if brief — this is your baseline.
4. **Make the minimum necessary change** — do not use the emergency as an opportunity for unrelated improvements.
5. **Validate and announce recovery** as soon as services are restored.
6. **Write a full maintenance log entry** within 24 hours of the emergency window.
7. **Write an incident log entry** if services were disrupted (see `MEMORY.md` for the incident log format).

### Emergency notification template

```
[MANUTENÇÃO DE EMERGÊNCIA]

Identificamos um problema na rede e precisamos fazer uma intervenção agora.

🔴 Problema: [DESCRIÇÃO BREVE]
📍 Afetados: [SITES OU SERVIÇOS]
⏰ Previsão: [TEMPO ESTIMADO PARA RESOLUÇÃO]

Vamos avisar quando estiver resolvido.
— Equipe de Manutenção
```

---

## Quick checklist

### Before the window
- [ ] Time chosen within a preferred window, no blackout period
- [ ] Site notes checked for access and operating hour constraints
- [ ] Advance notice sent to community group
- [ ] Affected site contacts notified directly
- [ ] Written approval received and stored
- [ ] Rollback plan defined
- [ ] Rollback firmware/config staged

### During the window
- [ ] Pre-window drift check completed
- [ ] Changes executed per approved plan
- [ ] Validated after each step
- [ ] Stopped immediately on any unexpected failure

### After the window
- [ ] Final drift check completed
- [ ] Maintenance log entry written and filed
- [ ] Inventory updated
- [ ] Post-window community message sent
