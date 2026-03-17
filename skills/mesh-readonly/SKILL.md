# SKILL: mesh-readonly

## Purpose

The `mesh-readonly` skill safely inspects the LibreMesh / OpenWrt community mesh network. It collects information about nodes, links, topology, configuration state, and health indicators — and returns both a normalized structured snapshot and a plain-language human summary.

This skill never writes to routers. It is the primary visibility tool for the community network.

---

## Responsibilities

### Must do

- Read the node inventory from `inventories/mesh-nodes.yaml` and related inventory files.
- Query live router state through available adapters: UCI configuration reads, `ubus` data, routing and neighbor tables, interface and radio status, hostname resolution.
- Inspect mesh topology: which nodes are present, how they are connected, what paths exist.
- Collect link health indicators: signal quality, link speed estimates, estimated loss, asymmetric link warnings.
- Identify likely weak links and surface them with a plain-language explanation of why they are weak (e.g. "probably line-of-sight obstruction," "overloaded hop," "asymmetric signal").
- Read firmware version and compare against the firmware policy in `desired-state/mesh/firmware-policy.yaml`.
- Read configuration state and compare against the community profile in `desired-state/mesh/community-profile/`.
- Detect configuration drift: differences between actual node config and the expected community-level or node-level desired state.
- Collect relevant log excerpts where available (connectivity events, reboot history, errors).
- Check gateway and backhaul status.
- Summarize findings in plain, non-technical language suitable for field maintainers.
- Produce a normalized JSON or YAML snapshot of the collected state for use by the planning layer.
- Include recommended next steps in the human summary when issues are detected.

### Must not do

- Write any configuration to any router.
- Reboot, restart, or reconfigure any node.
- Modify any file in `desired-state/` or `inventories/`.
- Execute commands on routers that have side effects (writes, reloads, flushes).
- Cache stale data as if it were current — always mark data with the collection timestamp.

---

## Inputs

- Node inventory: `inventories/mesh-nodes.yaml`, `inventories/sites.yaml`, `inventories/gateways.yaml`
- Desired-state references: `desired-state/mesh/community-profile/`, `desired-state/mesh/firmware-policy.yaml`, `desired-state/mesh/node-overrides/`
- Adapter outputs from `adapters/mesh/` (UCI reads, ubus queries, routing tables, radio state)
- Optional: specific node hostname or site name to scope the inspection
- Optional: focus area (topology, link health, config drift, firmware versions, gateway status)

---

## Outputs

- **Normalized snapshot** (JSON or YAML): structured representation of current node inventory, link state, topology, firmware versions, and config drift indicators. Includes a timestamp.
- **Human summary**: plain-language description of what was found. Sections: overall status, issues detected, weak points, recommended next steps.
- **Drift report** (when applicable): list of nodes or settings that differ from desired state, with description of each difference.
- **Recommended next steps**: if issues found, list the smallest safe actions to investigate or resolve (may include routing to `incident-triage` or flagging for `mesh-rollout` approval).

## Execution Workflow

1. For any request about current mesh status, current topology, live node reachability, weak links, or gateway health, run `bash skills/mesh-readonly/scripts/run-mesh-readonly.sh` before answering.
2. For a request scoped to one inventoried node, run `bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --hostname <inventory-hostname>`.
3. If the operator host is already on a LibreMesh node that exposes `thisnode.info`, run `bash scripts/discover-from-thisnode.sh` locally to generate draft bootstrap artifacts under `exports/discovery/`.
4. Use `--plan` only to verify which inventory targets would be queried. Never present `--plan` output as live state.
5. Treat `inventories/mesh-nodes.yaml` and `inventories/gateways.yaml` as reference inputs only. They are not current status by themselves.
6. If the live runner returns no reachable nodes, say that clearly. Do not fall back to inventory example data as if it were a fresh mesh snapshot.
7. If live collection is unavailable and `exports/mesh/latest.json` exists, you may use it as a cached snapshot only if you label it clearly as cached and mention its collection timestamp.
8. For unattended recurring collection, use `bash scripts/mesh-heartbeat.sh` on the ops host and read `exports/mesh/latest.json` as the cached last-known snapshot.

---

## Risk Class

**Class A — Read-only**

No approval required. This skill may be triggered directly by the frontdesk or by a maintainer without an approval gate.

---

## Activation Examples

- "Show me the weak links in the mesh."
- "Is the mesh healthy?"
- "Why is node at the school not responding?"
- "What routers are outdated?"
- "Show topology."
- "Compare the clinic router config to the community standard."
- "Which nodes have drifted from the community profile?"
- "What is the gateway status?"
- "List all nodes and their link quality."
- "Show me what changed since last week." (uses snapshot comparison)
- "Which rooftop nodes are running the old firmware?"
- "Check if the mesh is behaving normally."

---

## Constraints and Guardrails

1. **Read-only guarantee**: no adapter call used by this skill may trigger a write, reload, or configuration change on any router. Adapter scripts must be reviewed to ensure this.
2. **Structured output required**: all data returned to the planning layer must be in normalized JSON or YAML. No raw shell output passed upstream.
3. **Timestamp all snapshots**: every snapshot must include a `collected_at` field. Stale data must not be presented as current.
4. **Physical-world inference**: when link quality is poor, include a plain-language hypothesis about the physical cause (obstruction, distance, interference, power instability). Mark it as a hypothesis, not a confirmed fact.
5. **Graceful degradation**: if a node is unreachable, mark it as unreachable in the snapshot and proceed with the rest. Do not abort the entire inspection because one node is down.
6. **Offline operation**: the skill should prefer `exports/mesh/latest.json` as the cached last-known snapshot when live router access is unavailable. Only fall back to inventory files when no cached snapshot exists, and label the result clearly as stale reference data.
7. **Scope limiting**: if given a specific node or site, scope the inspection to that target. Do not unnecessarily query the entire network for a single-node request.
8. **No speculation in the human summary**: separate "confirmed findings" from "possible causes" clearly in output.
9. **No inventory-as-status**: inventory `status` fields are not authoritative live health. They may be stale or example data. Use the live runner first whenever the user asks for current status.
