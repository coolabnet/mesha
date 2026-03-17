# SKILL: mesh-onboarding

## Purpose

The `mesh-onboarding` skill helps add new routers and sites to the community mesh network. It gathers the necessary site and node metadata, generates a setup checklist, prepares the community-level and node-level configuration, produces a plain-language field guide for the person doing the physical installation, and verifies that the new node joined the network correctly after installation.

Onboarding a new node is a medium-risk write operation. It requires a confirmed plan before any configuration is applied.

---

## Responsibilities

### Must do

- Gather site metadata: location name, physical address or coordinates, purpose of the site, hardware model, assigned maintainer contact, and any physical access notes.
- Check the hardware model against `inventories/hardware-models.yaml` and flag if the model is unsupported or end-of-life.
- Generate an onboarding checklist covering: site survey items, hardware requirements, cable and power needs, LOS (line-of-sight) assessment, IP and naming assignment, config preparation, and post-install checks.
- Prepare node-level configuration: hostname, mesh interface settings, any node-specific overrides, based on the community profile at `desired-state/mesh/community-profile/` and the node override rules at `desired-state/mesh/node-overrides/`.
- Validate that the planned configuration does not conflict with the community profile or naming conventions.
- Produce a "field steps" guide: a numbered, plain-language document the installation volunteer can follow physically on-site. Must not require SSH knowledge for basic physical steps.
- Assign a provisional node entry in `inventories/mesh-nodes.yaml` with `status: provisioned` before installation.
- After installation, verify that the node appears in the mesh, is reachable, and its configuration matches the prepared settings. Update the inventory entry to `status: active`.
- Produce an onboarding summary for `knowledge-curator` to file: site name, node ID, hardware, installation date, installer, and outcome.
- Guide any first-boot or guided onboarding flow if the firmware supports it.

### Must not do

- Apply configuration to a node without a confirmed written plan and explicit approval from an authorized maintainer through the trusted approval channel.
- Execute any write action on a router without a prior approval signal — "acknowledged" or informal consent is not sufficient for Class C operations.
- Create naming or IP assignments that conflict with existing inventory entries.
- Add a node to the mesh without completing post-install verification.
- Mark a node as `active` without confirmed connectivity and configuration validation.
- Use node override settings that are not in the reviewed `desired-state/mesh/node-overrides/` files.
- Share SSH credentials, keys, or router passwords in the field guide document.
- Proceed with onboarding a site that has unresolved physical risks (no power source, no confirmed mounting, flagged LOS issues without acknowledgment).
- Perform any write action on nodes that are already active in the mesh — configuration changes to existing nodes are the scope of `mesh-rollout`, not this skill.

---

## Inputs

- Site information provided by the maintainer: location, purpose, hardware model, contact person.
- Community profile: `desired-state/mesh/community-profile/`
- Existing inventory: `inventories/mesh-nodes.yaml`, `inventories/sites.yaml`, `inventories/hardware-models.yaml`
- Node override rules: `desired-state/mesh/node-overrides/`
- Rollout policy (for naming and ring assignment): `desired-state/mesh/rollout-policy.yaml`
- Onboarding templates in `skills/mesh-onboarding/templates/`
- Post-install verification via `mesh-readonly` adapter

---

## Outputs

- **Site metadata record**: structured entry for `inventories/sites.yaml`.
- **Provisional node inventory entry**: entry for `inventories/mesh-nodes.yaml` with `status: provisioned`.
- **Prepared node configuration**: community profile base + node-specific overrides, ready to apply.
- **Onboarding checklist**: site survey items, hardware check, power and cable requirements, LOS notes.
- **Field steps guide**: plain-language numbered steps for physical installation and first-boot. Safe for a non-expert volunteer to follow.
- **Post-install verification report**: confirmation that the node joined the mesh, is reachable, and configuration is correct.
- **Updated inventory entry**: node entry updated to `status: active` after successful verification.
- **Onboarding summary record**: handed to `knowledge-curator` for filing.

---

## Risk Class

**Class C — Medium-risk infrastructure change**

Adding a new node involves preparing and applying configuration to a router. Requires explicit approval from an authorized maintainer through the trusted approval channel before any configuration is applied or the field steps are executed. Rollback path: remove the node from inventory and reset the router to factory defaults.

**Scope boundary:** This skill covers only the addition of new, previously unconfigured nodes to the mesh. Configuration changes, firmware updates, or reboots on nodes already active in the mesh are the exclusive scope of `mesh-rollout`. Do not use this skill for changes to existing nodes.

---

## Activation Examples

- "Add a new router at the clinic."
- "We're setting up a node at the community center — help us prepare."
- "Generate onboarding steps for a new volunteer installing a node."
- "I have a new TP-Link router — how do I add it to the mesh?"
- "We need a node at site 7 — what do we need to do?"
- "Create a checklist for the new rooftop installation."
- "Prepare the config for the school node."
- "Verify that the new node joined the mesh after installation."
- "Update the inventory — the clinic node was installed yesterday."
- "Generate a field guide for a non-technical volunteer doing an install."

---

## Constraints and Guardrails

1. **Plan and approve before configuring**: a written onboarding plan must be produced and explicitly approved by a maintainer through the trusted approval channel before any configuration is applied to a router. Informal acknowledgment or a reply in a public group is not sufficient for Class C approval.
2. **No duplicate names or IPs**: before assigning a hostname or IP, check the full inventory for conflicts. Refuse to proceed if a conflict is found.
3. **Hardware model check**: if the hardware model is not in `inventories/hardware-models.yaml` or is marked end-of-life, warn the maintainer and require explicit acknowledgment before continuing.
4. **Field guide safety**: the field steps guide must not include commands that could brick the router if entered incorrectly without safeguards. Mark any advanced step clearly as "for maintainer only."
5. **No credentials in field guide**: the field guide is a document that may be shared with installation volunteers. It must not contain SSH keys, router admin passwords, or network credentials.
6. **Post-install verification required**: a node must not be marked as `active` in the inventory without confirmed post-install verification from `mesh-readonly`. Mark it `provisioned` until verified.
7. **LOS and power acknowledgment**: if the site survey raises concerns about line-of-sight or power stability, these must be explicitly acknowledged in the onboarding plan before proceeding.
8. **Configuration source discipline**: all configuration for the new node must come from the community profile and node-override files. Do not manually craft arbitrary UCI settings outside the established desired-state structure.
9. **Onboarding record**: every completed onboarding must be handed off to `knowledge-curator` for filing. Undocumented node additions are not acceptable.
