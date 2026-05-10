# LibreMesh Lab

LibreMesh/QEMU simulation now lives in the standalone sibling repository
`../libremesh-lab`.

Mesha keeps adapter code and compatibility wrappers only. The lab owns firmware
image builds, QEMU/vwifi lifecycle, topology fixtures, simulator tests, and
WiFi simulation research.

## Setup

Place the lab next to this checkout:

```bash
../libremesh-lab/bin/libremesh-lab status
```

If it lives somewhere else:

```bash
export LIBREMESH_LAB_ROOT=/path/to/libremesh-lab
```

## Mesha Adapter Tests

Run Mesha’s compatibility wrapper:

```bash
bash tests/qemu/run-all.sh
```

Or run one adapter against a running lab:

```bash
bash scripts/libremesh-lab.sh run-adapter \
  "$PWD/adapters/mesh/collect-nodes.sh" lm-testbed-node-1
```

The lab wrapper provides lab inventories, desired state, SSH config, SSH key,
and `HOSTALIASES` through a temporary workspace. It does not replace Mesha’s
tracked `inventories/` or `desired-state/` directories.
