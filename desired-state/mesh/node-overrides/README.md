# node-overrides/ — Per-Node UCI Configuration Overrides

## What node overrides are

Node overrides are per-node UCI configuration files that extend or override the community-wide `lime-community` settings for a specific router. They are placed in this directory and applied to individual nodes by the `mesh-onboarding` skill during provisioning or by the `mesh-executor` skill during an approved configuration change.

On the node itself, the equivalent file is `/etc/config/lime-node`. The files in this directory are the **desired-state representation** of what should be in `lime-node` on each node — managed through this repository and applied via the operator, not edited directly on the device.

## When to use a node override vs changing community settings

Use a **node override** when:

- A specific node requires a different radio channel (e.g., a directional gateway aimed at a fixed point)
- A node has unusual hardware that needs a specific interface assignment
- A node needs a non-default transmit power level
- A node requires a custom hostname that deviates from the standard prefix
- A node has a known hardware limitation requiring a workaround
- A gateway node needs specific BMX7 or Babel tuning for its uplink

Change **`lime-community`** when:

- The setting should apply to every node in the mesh (e.g., community SSID, IP range)
- A protocol-level change is needed network-wide (e.g., enabling a new routing feature)
- The community has decided to adopt a new standard

**Rule of thumb:** If only one or two nodes would ever need it, it's a node override. If the whole community needs it, it's a community setting.

## File naming convention

Override files are named after the node's hostname:

```text
<hostname>.uci
```

Examples:

- `lm-escola-telhado.uci` — override for the rooftop gateway at the school
- `lm-clinica-antena.uci` — override for the clinic's outdoor antenna node
- `lm-ponto-morro.uci` — override for the hilltop relay node

The hostname must match the `hostname` field in `inventories/mesh-nodes.yaml`.

## How overrides are applied by the mesh-onboarding skill

1. The `mesh-onboarding` skill reads the inventory entry for the target node.
2. It looks for a file named `<hostname>.uci` in this directory.
3. If found, it transfers the file to the node at `/etc/config/lime-node`.
4. It runs `lime-config` on the node to regenerate the merged configuration.
5. It validates the resulting configuration and checks for errors.
6. It logs the applied override to `logs/` with a timestamp and operator signature.

Applying a node override is a **Class C** operation (medium-risk infrastructure change) and requires explicit maintainer approval before the `mesh-executor` can push it to the node. See `TOOLS.md` for the full approval requirements.

## Example: overriding radio channel on a specific gateway node

**Scenario:** The rooftop gateway at the school (`lm-escola-telhado`) uses a directional CPE510 antenna aimed at the hilltop relay. The default channel 48 (5 GHz) causes interference with a neighboring network. The maintainer wants to move this link to channel 149.

**The override file** would be `lm-escola-telhado.uci`:

```uci
# Per-node override for lm-escola-telhado
# Reason: directional 5 GHz link to lm-ponto-morro requires channel 149
# to avoid interference with neighboring WISP on channel 48.
# Approved: [maintenance-log-2026-03-10]

config lime 'wifi'
    option channel_5ghz '149'
```

This file is applied on top of `lime-community`, so only the 5 GHz channel changes. All other community settings remain in effect.

## Override file format

Override files use the same UCI format as `lime-community`. Only include the settings you want to override — there is no need to repeat settings that should keep the community default.

```uci
# Per-node override for <hostname>
# Reason: <brief explanation of why this override exists>
# Approved: <link to maintenance log or approval record>

config lime '<section>'
    option <key> '<value>'
```

Always include a comment explaining why the override exists and referencing the approval record. This makes the override self-documenting and auditable.

## Notes on drift detection

The `mesh-collector` adapter compares the live `/etc/config/lime-node` on each node against the file in this directory. If they differ, the node is flagged as having a configuration drift. This means:

- If you make a manual change directly on a node without updating this directory, drift will be detected on the next collection run.
- If a file exists here but has never been applied to the node, the node will also show drift.

Keep these files up to date to maintain an accurate desired-state picture of the mesh.
