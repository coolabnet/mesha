# SKILL: incident-triage

## Purpose

The `incident-triage` skill responds to reported outages and active failures. When someone reports that something is broken or degraded, this skill identifies the affected scope, proposes likely causes based on available data, asks the minimum set of useful questions to narrow down the problem, provides a practical field-friendly checklist for the person on-site, and escalates when the situation is beyond what the system can resolve automatically.

This skill focuses on diagnosis and guidance. It does not perform infrastructure changes.

---

## Responsibilities

### Must do

- Accept incident reports from the frontdesk or directly from a maintainer.
- Identify the affected scope: which node(s), site(s), service(s), or user group is impacted.
- Determine whether the issue is isolated (single node or service) or widespread (site-level or network-wide).
- Cross-reference the report against current state from `mesh-readonly` and/or `server-readonly` outputs, if available.
- Propose two to four likely causes in plain language, ordered from most to least probable given available evidence.
- Provide physical-world interpretations where applicable (e.g. "likely a power issue at that location," "possible line-of-sight obstruction after recent construction").
- Ask the minimum useful set of questions to resolve ambiguity — prefer targeted, answerable questions over open-ended ones.
- Produce a field-friendly numbered checklist of steps for the person who is physically on-site or near the affected equipment.
- Determine when a situation requires human escalation (maintainer SSH access, physical site visit, ISP contact) and say so clearly.
- Record the incident in structured form for the `knowledge-curator` to log.
- Flag repeated incidents involving the same node, site, or hardware model for pattern tracking.

### Must not do

- Perform any infrastructure changes (no reboots, no config changes, no service restarts).
- Attempt to resolve the incident autonomously without informing the person who reported it.
- Ask more than three clarifying questions in a single exchange — triage must remain fast.
- Dismiss a report without checking available state data first.
- Speculate about causes that have no basis in the available data.
- Suppress escalation when the evidence clearly points to a situation beyond automated resolution.

---

## Inputs

- Incident report: free-text description of the problem from a user or maintainer.
- Optional: snapshot from `mesh-readonly` or `server-readonly` collected at or near the time of the incident.
- Optional: site or node identifier from the report or from the frontdesk routing context.
- Inventory files: `inventories/mesh-nodes.yaml`, `inventories/sites.yaml`, `inventories/hardware-models.yaml`
- Known issues and past incidents from `docs/troubleshooting.md` and `docs/playbooks/`
- Optional: recent maintenance logs from `logs/`

---

## Outputs

- **Scope assessment**: which nodes, sites, or services are affected (confirmed or likely).
- **Likely causes**: a ranked short list of probable root causes in plain language.
- **Clarifying questions** (if needed): one to three targeted questions to narrow down the problem.
- **Field checklist**: numbered, plain-language steps a non-expert can follow on-site. Steps must be safe to perform without SSH access unless clearly marked as requiring it.
- **Escalation recommendation** (when applicable): clear statement of when and how to escalate — who to contact, what to tell them, what to bring.
- **Incident record** (structured): for handoff to `knowledge-curator` to log. Includes: timestamp, reporter, affected scope, reported symptoms, proposed causes, checklist issued, resolution status.

---

## Risk Class

**Class A — Read-only / advisory**

This skill only reads existing data and produces guidance. It does not execute any changes. No approval required.

However, if the triage outcome leads to a recommendation to execute a change (reboot, config update, service restart), that action must be routed through the appropriate write skill (`mesh-rollout`, `server-services`) with the required approval gate.

---

## Activation Examples

- "The school is offline."
- "We lost internet at the community center."
- "The local video server stopped working."
- "Nobody can connect to the mesh at site 3."
- "One of the rooftop nodes is showing a red light."
- "The mesh has been slow since this morning."
- "Something broke after the last power outage."
- "Users can't reach the local wiki."
- "A node disappeared from the mesh map."
- "We hear there's an issue at the clinic — can you check?"
- "The backup drive is full."
- "The frontdesk reported an outage — start triage."

---

## Constraints and Guardrails

1. **No uninstructed changes**: triage is advisory. The skill must never initiate a write action on its own, even if the fix seems obvious.
2. **Speed over completeness for initial response**: the first output should arrive quickly with what is known, even if incomplete. Additional data can follow.
3. **Maximum three clarifying questions per turn**: do not interrogate the person reporting the issue. One or two focused questions are preferred.
4. **Physical-world grounding**: checklist steps must be things a person with physical access to the equipment can realistically do (check power, look at indicator lights, try rebooting at the outlet, test with a phone). Do not require SSH access in the basic checklist unless the respondent is a maintainer.
5. **Severity classification**: label each incident as one of: informational, degraded, partial outage, full outage. This affects escalation urgency.
6. **Pattern detection**: if the same node, site, or hardware model has appeared in multiple incidents, flag this in the output. Route a note to `knowledge-curator`.
7. **Honest uncertainty**: if the available data is insufficient to determine the cause, say so clearly. Do not fabricate a diagnosis.
8. **Escalation criteria**: escalate immediately when any of the following are true: the issue has been active for more than two hours without resolution, critical infrastructure (gateway, primary server) is affected, the checklist has been followed without improvement, or the maintainer on-site cannot safely proceed.
