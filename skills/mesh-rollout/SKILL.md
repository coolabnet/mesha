# SKILL: mesh-rollout

## Purpose

The `mesh-rollout` skill performs approved changes to the LibreMesh / OpenWrt mesh network. This includes applying configuration updates, performing staged firmware upgrades, rebooting nodes, and rolling back changes when validation fails. Every change is planned before execution, executed in a canary-first sequence, validated after each stage, and logged in the maintenance record.

This is a write skill. It must never execute without explicit approval from an authorized maintainer.

---

## Responsibilities

### Must do

- Accept a structured change request and a confirmed approval record before proceeding.
- Generate a written execution plan before any change is applied. The plan must state: what will change, which nodes are affected, in what order, what the rollback path is, and what the success criteria are.
- Present the execution plan to the requesting maintainer and wait for explicit confirmation.
- Execute changes canary-first: apply to one or a small group of non-critical nodes first, validate, then proceed to the rest of the ring.
- Validate after each stage: check that affected nodes are reachable, correctly configured, and behaving as expected before advancing to the next stage.
- Stop immediately on failure: if validation fails at any stage, halt the rollout and do not advance.
- Execute rollback when instructed or when a failure threshold is reached.
- Write a maintenance log entry after every stage, and a final entry at completion or failure. Include: timestamp, what was applied, which nodes succeeded, which failed, and current status.
- Respect rollout policy from `desired-state/mesh/rollout-policy.yaml`: upgrade rings, canary thresholds, approved maintenance windows, and approval requirements.
- Apply configuration from community profile and node-override files only — do not invent or improvise configuration.
- Route failures and post-rollout anomalies to `incident-triage` for diagnosis.

### Must not do

- Execute any change without a confirmed written plan and an explicit approval from an authorized maintainer.
- Perform mass upgrades on all nodes simultaneously.
- Modify configuration in ways not defined in `desired-state/mesh/` files.
- Hide changes from the maintenance log.
- Proceed past a failed validation stage.
- Override rollout policy settings without an explicit updated policy file.
- Perform changes outside the configured maintenance window unless an emergency override is explicitly granted.
- Accept approval from an untrusted channel (public group, unverified user).

---

## Inputs

- Change request: structured description of what should change (firmware version, config setting, node list, scope).
- Approval record: explicit confirmation from an authorized maintainer, received through the trusted approval channel.
- Rollout policy: `desired-state/mesh/rollout-policy.yaml`
- Firmware policy: `desired-state/mesh/firmware-policy.yaml`
- Community profile: `desired-state/mesh/community-profile/`
- Node overrides: `desired-state/mesh/node-overrides/`
- Node inventory: `inventories/mesh-nodes.yaml`, `inventories/gateways.yaml`
- Pre-rollout snapshot from `mesh-readonly` (required before any change execution)
- Adapter tools in `adapters/mesh/` and scripts in `skills/mesh-rollout/scripts/`

---

## Outputs

- **Execution plan** (before changes): written, human-readable plan with stages, affected nodes, rollback path, and success criteria.
- **Stage reports**: post-validation summary after each stage — which nodes passed, which failed, overall status.
- **Rollback report** (when applicable): what was rolled back, why, which nodes are now in what state.
- **Maintenance log entry**: appended to `logs/` — timestamp, scope, what changed, approval reference, outcome. Handed to `knowledge-curator` for filing.
- **Post-rollout snapshot**: updated state snapshot for comparison with pre-rollout baseline.

---

## Risk Class

**Class C (configuration changes, single-node or small-group updates) or Class D (firmware rollouts, gateway changes, community-wide config changes, mass node operations)**

- Class C: requires explicit maintainer approval before execution; rollback path required.
- Class D: requires explicit approval, defined change window, canary-first execution, rollback hooks, and post-change validation.

**This skill must never execute in Class D scope without all of: written plan, explicit approval, defined maintenance window, and canary node selected.**

**Scope boundary:** This skill covers only changes to nodes that are already active and enrolled in the mesh. Adding a new, previously unconfigured node to the mesh is the exclusive scope of `mesh-onboarding`. Do not use this skill for first-time node provisioning.

---

## Activation Examples

- "Apply the new community profile to the rooftop nodes." (requires plan + approval)
- "Upgrade the stable ring to firmware 23.05." (requires plan + approval + maintenance window)
- "Reboot node at the school after the maintenance window." (requires approval)
- "Roll back the config change on node clinic-01." (requires approval or auto-triggered by failed validation)
- "Push the updated DNS settings to all nodes." (requires plan + approval)
- "Apply the node override for the gateway antenna." (requires approval)
- "Stage a firmware upgrade — canary first." (requires plan + approval + maintenance window)

---

## Constraints and Guardrails

1. **No approval, no execution**: the skill must refuse to execute any change if it cannot verify a written approval from an authorized maintainer via the trusted channel. This is non-negotiable.
2. **Plan first, always**: a written execution plan must be produced and confirmed before any change is applied. The plan is a required step, not optional.
3. **Canary-first for all multi-node operations**: even for "low-risk" config changes, start with one non-critical node and validate before expanding.
4. **Halt on failure**: do not proceed past a failed validation stage under any circumstances. Log the failure and wait for human decision.
5. **Rollback must be defined before execution begins**: if there is no rollback path, the plan must not be approved. The skill should refuse to proceed if rollback is undefined.
6. **Maintenance window enforcement**: Class D operations must only execute in the defined maintenance window unless an emergency override is granted with an explicit reason recorded.
7. **No freeform config improvisation**: only use configuration from the `desired-state/` files. Do not invent new settings or apply configurations that are not in a reviewed file.
8. **Log everything**: every change, every validation result, every failure, and every rollback must appear in the maintenance log. Incomplete logs are a failure condition.
9. **Approval channel trust**: approval must come through the configured trusted maintainer channel. A message in a public group or from an unverified identity is not valid approval.
10. **Post-change visibility**: after any successful rollout, trigger a `mesh-readonly` snapshot to confirm the new state and attach it to the maintenance log.
