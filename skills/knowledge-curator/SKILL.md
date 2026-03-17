# SKILL: knowledge-curator

## Purpose

The `knowledge-curator` skill keeps the workspace documentation accurate, current, and useful over time. It updates inventories when the network or servers change, writes playbooks from expert procedures, logs maintenance actions and incidents, and turns recurring problems into reusable reference material. This skill is what prevents the community from depending on a single person's memory.

---

## Responsibilities

### Must do

- Update `inventories/mesh-nodes.yaml`, `inventories/sites.yaml`, `inventories/gateways.yaml`, `inventories/local-services.yaml`, and `inventories/hardware-models.yaml` when changes are reported or confirmed.
- Add, update, or deprecate entries in the local service catalog at `desired-state/server/service-catalog.yaml`.
- Write or update playbooks in `docs/playbooks/` when a procedure has been performed and should be repeatable.
- Log completed maintenance actions in `logs/` with timestamp, description, what changed, who approved, and outcome.
- Log incidents in structured form: timestamp, affected scope, symptoms, diagnosis, resolution, and any follow-up needed.
- Identify recurring incidents involving the same node, site, or hardware model and document the pattern in `docs/troubleshooting.md`.
- Convert lessons learned from incidents into reusable reference sections in troubleshooting or playbook docs.
- Write onboarding guides in `docs/onboarding/` when a new volunteer, maintainer, or site has been added.
- Keep documentation language plain, consistent, and understandable to non-experts as well as maintainers.
- Record decisions and change approvals in the appropriate log file.
- Flag outdated documentation when it no longer matches current inventory or desired-state files.

### Must not do

- Perform any infrastructure changes (no router config, no service restarts, no network changes).
- Overwrite documentation without preserving the previous state (use append or dated entries for logs).
- Invent inventory entries that have not been confirmed — mark unverified data as `status: unconfirmed`.
- Delete incident records or maintenance logs.
- Store credentials, SSH keys, or secrets in documentation files.
- Publish documentation to external systems without explicit instruction.

---

## Inputs

- Incident records from `incident-triage` (structured handoff).
- Maintenance completion reports from `mesh-rollout` or `server-services`.
- Snapshots from `mesh-readonly` or `server-readonly` that represent a confirmed new state.
- Direct requests from maintainers: "log this change," "write a playbook for this," "update the node inventory."
- Reports of new hardware, new sites, or new services being added to the network.
- Feedback on existing docs: "this playbook is wrong," "the inventory is outdated."

---

## Outputs

- Updated YAML inventory files in `inventories/`.
- Updated or new Markdown playbook files in `docs/playbooks/`.
- Updated or new troubleshooting entries in `docs/troubleshooting.md`.
- New or updated onboarding guides in `docs/onboarding/`.
- Maintenance log entries appended to the appropriate file in `logs/`.
- Incident log entries appended to the appropriate log file.
- Summary of what was changed: a short plain-language description of the documentation updates made.

---

## Risk Class

**Class B — Low-risk write (documentation only)**

Documentation and inventory writes do not affect live infrastructure. No approval required for documentation updates.

However, updates to `desired-state/` files (firmware policy, rollout policy, service catalog approval status) represent intent changes and should be confirmed by a maintainer before being written.

---

## Activation Examples

- "Log the maintenance we just did on the rooftop nodes."
- "Update the inventory — we added a new router at the clinic."
- "Write a playbook for adding a new node."
- "The school router has been flaky for weeks — add it to the known issues."
- "Log this incident: the mesh was down at site 2 for 3 hours."
- "Generate onboarding instructions for a new volunteer."
- "The local media service is now installed — add it to the service catalog."
- "Turn what we learned from this outage into a troubleshooting entry."
- "Update the inventory after the firmware rollout."
- "Document how we fixed the gateway issue last week."
- "Mark the old antenna model as end-of-life in the hardware notes."
- "What docs are out of date?"

---

## Constraints and Guardrails

1. **Append, never silently overwrite**: log files must be appended. Inventory and playbook updates should note what changed and when, not just replace the previous content without trace.
2. **Unconfirmed data**: if a change has not been verified by a read-only skill or a maintainer, mark the entry with `status: unconfirmed` and a `needs_verification: true` flag.
3. **No secrets in docs**: all documentation files are potentially committed to version control. Never record credentials, passwords, SSH keys, or API tokens in any doc file. Refer to `secrets/README.md` for the correct handling pattern.
4. **Plain language**: playbooks must be written so that a field volunteer with limited technical experience can follow them. Include context, not just commands.
5. **Recurring incident pattern threshold**: if the same node, site, or hardware model appears in three or more incidents within any 30-day window, escalate a pattern alert to the frontdesk for human review.
6. **Cross-reference consistency**: when updating an inventory entry, check for and update any related references in playbooks, troubleshooting docs, and onboarding guides.
7. **Change records are permanent**: never delete or truncate maintenance or incident logs. If a correction is needed, add an amendment entry rather than editing the original.
8. **Language**: documentation should be written in the community's primary working language. If multilingual docs are needed, create parallel files and note the language in the filename or frontmatter.
