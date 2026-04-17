# Incident Response Playbook

**Purpose:** How to respond to a live infrastructure incident — quickly, calmly, and without making things worse.

**Risk class of response actions:** Ranges from Class A (investigation) to Class D (emergency gateway changes). Follow the risk class rules even during an incident.

Read Section 1 and the P1 checklist now, before an incident happens. You do not want to read this for the first time at 2am.

---

## 1. Incident classification

Classify the incident immediately. The classification determines how urgently you need to act and who you need to notify.

### P1 — Total outage

**Definition:** One or more sites have no connectivity. End users cannot reach the internet or community services.

**Examples:**

- Gateway node is offline and not recovering
- Internet uplink is down at the primary site (Escola Municipal)
- All nodes at a site are unreachable

**Response time:** Immediate. Start the P1 checklist within 5 minutes of detection.

**Who to notify:** Lead maintainer immediately. Community group within 15 minutes.

---

### P2 — Degraded service

**Definition:** The network is partially working but with reduced coverage, increased latency, or intermittent drops.

**Examples:**

- One non-gateway node is offline
- Mesh link quality is poor but traffic is still flowing via alternate paths
- One site has reduced but not zero connectivity
- A relay node is down, adding hops for downstream nodes

**Response time:** Within 30 minutes during daytime, next morning for overnight degradation if no one is affected.

**Who to notify:** Lead maintainer via DM. Community group only if the degradation is noticeable to users.

---

### P3 — Isolated issue

**Definition:** A configuration problem, a single node anomaly, or an issue affecting only internal tooling. No end-user service impact.

**Examples:**

- A node is on old firmware but otherwise functional
- Dashboard or monitoring is not updating
- An inventory file is out of date
- A known issue is recurring but the workaround is in place

**Response time:** Within the next planned maintenance window or at maintainer's convenience.

**Who to notify:** Log the issue. Notify maintainer if a decision is needed.

---

## 2. First 5 minutes

These steps apply to any P1. For P2, start with Step 2.

### P1 checklist — first 5 minutes

- [ ] **Note the time** you detected the issue and what triggered it (alert, user report, etc.)
- [ ] **Run server-readonly** to check if the local server and local services are reachable:

  ```text
  Ask the operator: "Run server-readonly and tell me what is up and what is down."
  ```

- [ ] **Run mesh-readonly** to get a current mesh snapshot:

  ```text
  Ask the operator: "Run mesh-readonly and show me the current node status."
  ```

- [ ] **Identify the scope:** which nodes are offline? Which sites? Is it isolated or widespread?
- [ ] **Check if it is an uplink issue:** is the internet down at Escola Municipal, or is the mesh itself broken?
- [ ] **Check if it is a power issue:** was there a storm? Call the site contact if needed.
- [ ] **Do not start making changes yet.** Understand the situation first.

---

## 3. Investigation

### Using the incident-triage skill

```text
Ask the operator: "Run incident triage for [affected site or node]. I am seeing [describe symptoms]."
```

The incident-triage skill will:

- Check node reachability and topology
- Look for recent log entries and error patterns
- Compare current state to desired state
- Propose likely causes based on the symptoms
- Suggest field steps if physical access is needed

### Checking logs

On any node that is reachable:

```bash
ssh root@<node-ip> "logread | tail -50"
```

Look for:

- `kernel: Oops` or `kernel panic` — hardware or driver failure
- `uhttpd` errors — management interface problem
- `batadv` warnings — mesh protocol issues
- Authentication failures — SSH or management access problem
- `power` references — power interruption logs

### Checking topology

```bash
# On any online node, check mesh neighbors
ssh root@<node-ip> "batctl n"

# Check routing table
ssh root@<node-ip> "batctl o"
```

If a node shows no neighbors, it is isolated from the mesh even if it is technically online.

### Common patterns and likely causes

| Symptom | Likely cause | First check |
|---------|-------------|-------------|
| Single node offline, neighbors online | Power loss, reboot loop, or hardware failure | Call site contact to check power |
| Single node offline after recent change | Change caused the problem | Rollback the change |
| Multiple nodes at one site offline | Local power issue or switch failure | Call site contact |
| Gateway offline, all sites downstream affected | Power or uplink problem at gateway site | Call Escola Municipal contact |
| Mesh topology broken but nodes individually online | Mesh interface problem after update | Check `batctl n` on affected nodes |
| Degraded link quality without hardware change | Channel congestion (evening) or new physical obstruction | Check `docs/known-issues/channel-congestion-2ghz.md` |
| Node does not recover after power cut | Flash corruption (TL-WR841N v13) | Physical access required — see `docs/known-issues/tplink-wr841n-power-loss.md` |

---

## 4. Communication

### Who to notify

| Situation | Notify |
|-----------|--------|
| P1 outage detected | Lead maintainer immediately (DM) |
| P1 affecting end users | Community group within 15 minutes |
| P2 requiring investigation | Lead maintainer (DM) within 30 minutes |
| P1/P2 requiring physical access to a site | Site contact directly |
| Any active incident (any priority) | Maintainer group channel for awareness |

### What to say in the community group

**Initial notification (P1 — send within 15 minutes):**

```text
[PROBLEMA NA REDE]

Identificamos uma interrupção na rede comunitária. Já estamos investigando.

📍 Afetados: [NOME DO SITE OU "parte da rede"]
⏰ Detectado: [HORÁRIO]
🔍 O que sabemos: [BREVE DESCRIÇÃO, ex: "o roteador principal parece sem energia"]

Vamos atualizar aqui assim que tivermos mais informações.
— Equipe de Manutenção
```

**Update during investigation:**

```text
[ATUALIZAÇÃO — PROBLEMA NA REDE]

Ainda estamos investigando o problema em [SITE].

🔍 Causa provável: [DESCRIÇÃO BREVE, ex: "parece ser falta de energia no local"]
🔄 Próximo passo: [ex: "aguardando contato com Dona Lúcia para verificar a energia"]

Estimativa de resolução: [HORA ESTIMADA, ou "ainda não definida"]
```

**Resolution notification:**

```text
[REDE RESTAURADA]

✅ O problema em [SITE] foi resolvido às [HORÁRIO].

O que aconteceu: [EXPLICAÇÃO SIMPLES, ex: "o roteador ficou sem energia durante a queda de luz e precisou ser reiniciado manualmente"]

Se ainda estiverem com dificuldades de conexão, nos avisem aqui.

Obrigado pela paciência!
— Equipe de Manutenção
```

**Still unresolved at end of day:**

```text
[ATUALIZAÇÃO FINAL DO DIA — PROBLEMA NA REDE]

Infelizmente ainda não conseguimos resolver o problema em [SITE] hoje.

O que sabemos: [STATUS ATUAL]
Próximo passo: [ex: "visita técnica agendada para amanhã às 9h"]

Pedimos desculpas pelo transtorno.
— Equipe de Manutenção
```

---

## 5. Resolution

### Before making any change during an incident

Even in an emergency:

1. Know what you are about to do and why.
2. Know what the rollback is if the change makes things worse.
3. Announce to the lead maintainer what you are about to do.

For Class D emergency changes (e.g., gateway failover), get verbal or message approval from the lead maintainer before proceeding. Log the approval.

### Fixing the issue

Follow the relevant procedure:

- Power recovery: contact site contact, power-cycle PoE injector or router
- Node reboot: `ssh root@<node-ip> "reboot"` (requires approval if it will cause an outage)
- Config rollback: see `docs/playbooks/firmware-rollout.md` rollback section
- Emergency window (disruptive fix required outside a scheduled window): see `docs/playbooks/maintenance-window.md` Section 5
- Manual node recovery (bricked): see hardware-model notes in `inventories/hardware-models.yaml`

### Validating the fix

After the fix is applied:

- [ ] Affected node is reachable via SSH
- [ ] Mesh interface is up and shows neighbors
- [ ] Sites downstream of the fixed node have connectivity
- [ ] No new errors in logs
- [ ] End users confirm connectivity is restored (if reachable)

### Confirming service restored

Do not close the incident until you have confirmed:

- [ ] All affected sites are back online
- [ ] No residual degradation
- [ ] Post-fix mesh snapshot looks healthy

---

## 6. Post-incident

### Writing the incident log

Write an incident log entry in `logs/incidents/` within 24 hours. Use the format from `MEMORY.md`:

**Filename:** `logs/incidents/YYYY-MM-DD-brief-description.md`

**Template:**

```markdown
# Incident: [site/node] — [brief description]
Date: YYYY-MM-DD
Detected: HH:MM (local time)
Resolved: HH:MM (or "ongoing")
Affected: [list of affected nodes/services/sites]
Reported by: [person or automated alert]

## What happened
[Description of the failure and its impact on users]

## Likely cause
[Best determination of root cause]

## Steps taken
1. [What was done]
2. [What was done]

## Resolution
[What fixed it]

## Follow-up
[Preventive actions needed, or "none"]
```

### Updating known issues

If this incident is a **recurrence of a known pattern** (same hardware model, same symptom, same root cause), update the relevant file in `docs/known-issues/`:

- Increment `recurrence-count`
- Add the date of this occurrence in a note
- Update the workaround if you found a better one

If this is a **new pattern** that has appeared twice or more:

- Ask `knowledge-curator` to create a new known-issue file
- Document the pattern, symptoms, root cause, and workaround

### Reviewing for systemic issues

After any P1, ask:

- Could this have been prevented?
- Is there a desired-state change that would reduce this risk? (e.g., adding a UPS, repositioning an antenna)
- Should this change a maintenance priority?

Document the answers in the incident log under "Follow-up."

---

## P1 incident checklist (print this)

Use this during an active P1 outage. Read it fast and check boxes as you go.

**Detection**

- [ ] Time noted: ___________
- [ ] Who reported it: ___________
- [ ] Lead maintainer notified (DM)

**First 5 minutes**

- [ ] server-readonly run — results noted
- [ ] mesh-readonly run — results noted
- [ ] Scope determined: which sites/nodes affected
- [ ] Uplink vs. mesh issue identified
- [ ] Power issue ruled in or out

**Investigation**

- [ ] incident-triage skill run
- [ ] Logs checked on reachable nodes
- [ ] Topology checked (`batctl n`)
- [ ] Likely cause identified
- [ ] Community group notified (within 15 min)

**Resolution**

- [ ] Fix identified
- [ ] Rollback for fix identified
- [ ] Fix announced to lead maintainer before execution
- [ ] Fix applied
- [ ] Validation complete — all affected sites back online
- [ ] Community group notified (service restored)

**Post-incident**

- [ ] Incident log written (`logs/incidents/`)
- [ ] Known issues updated if recurrence
- [ ] Inventory updated if any node state changed
- [ ] Follow-up actions noted
