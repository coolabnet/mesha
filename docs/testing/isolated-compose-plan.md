# Mesha Isolated Compose Test Plan

This document describes the implemented Phase 1 path to make Mesha onboarding testable in an isolated Docker/Compose environment without touching real routers.

The harness uses `docker compose`, not the legacy standalone `docker-compose` binary.

Phase 1 is now implemented in:

- `docker-compose.onboarding-test.yml`
- `docker/onboarding-test/`
- `scripts/test-compose-phase1.sh`

The main command is:

```bash
bash scripts/test-compose-phase1.sh
```

## Goal

Make the easy setup path testable end-to-end:

1. start a disposable environment
2. run `doctor.sh`
3. run `activate-workspace.sh`
4. bootstrap from `thisnode.info`
5. run the live mesh-readonly path
6. run heartbeat
7. verify that cached exports are created correctly

The goal is not perfect LibreMesh emulation. The goal is repeatable onboarding validation.

## What The Compose Stack Should Simulate

### Service 1: `mesha-ops`

A workspace container with the Mesha repo mounted in, plus the tools needed to run the scripts:

- bash
- git
- curl
- ssh client
- python3
- jq
- node 22+

This is the container where another agent or maintainer runs the onboarding commands.

### Service 2: `fake-thisnode`

A lightweight SSH-enabled fixture container that pretends to be a LibreMesh node.

It should provide:

- an SSH server accepting a test key
- simple fixture implementations for:
  - `uci show network`
  - `uci get system.@system[0].hostname`
  - `ubus call network.interface dump`
  - `ubus call network.wireless status`

This is enough to exercise `scripts/discover-from-thisnode.sh`.

### Service 3: `fake-gateway`

A second SSH-enabled fixture container representing a gateway or topology target.

It should provide:

- all the same read-only fixture commands as `fake-thisnode`
- optional fake outputs for topology-related reads used by `collect-topology.sh`

This lets `run-mesh-readonly.sh` and `mesh-heartbeat.sh` operate on known-good fixture outputs.

### Service 4: `thisnode-http`

A tiny HTTP container or alias that serves a simple page on `http://thisnode.info/`.

This can be the same container as `fake-thisnode` if it serves both HTTP and SSH cleanly.

### Optional Service 5: `operator-stub`

A trivial HTTP echo server that receives envelopes from the Telegram adapter.

This is useful only if you want to test Telegram adapter startup or webhook forwarding in isolation.

## Network Design

Use a dedicated Compose network with stable service names and aliases:

- `fake-thisnode` should have the alias `thisnode.info`
- `fake-gateway` should have a stable hostname that matches the test inventory
- `mesha-ops` should see all services on the same private Compose network

This avoids patching Mesha scripts just for tests.

## Seed Data Strategy

Use test-only fixture inventories, not the main real inventories.

Recommended approach:

- copy the repo into a disposable test workspace
- provide fixture versions of:
  - `inventories/mesh-nodes.yaml`
  - `inventories/gateways.yaml`
  - `inventories/sites.yaml`
- generate a throwaway SSH key pair for the fixture containers

The fixture inventories should reference Compose hostnames, not real router names.

## Phased Implementation

### Phase 1: Script-level integration sandbox

Build the easiest useful version first:

- fixture SSH containers
- fixture HTTP endpoint for `thisnode.info`
- fixture inventories
- one command that runs:
  - `bash scripts/discover-from-thisnode.sh`
  - `bash skills/mesh-readonly/scripts/run-mesh-readonly.sh`
  - `bash scripts/mesh-heartbeat.sh`

This validates the onboarding path without real mesh routing.

### Phase 2: Adapter contract coverage

Expand the fixture commands so `collect-topology.sh` and other read adapters see more realistic output shapes.

The purpose here is schema fidelity, not network realism.

### Phase 3: Higher-fidelity emulation

Only if needed, evaluate one of:

- OpenWrt or LibreMesh images under QEMU
- Linux network namespaces with mocked command outputs
- a richer fake-node image that mimics the command surface more closely

Do this only after Phase 1 proves valuable.

## What This Will Not Test Well

The Compose sandbox will not credibly test:

- real radio behavior
- link quality changes
- actual LibreMesh routing daemon behavior
- hardware-specific OpenWrt quirks
- timing issues caused by unstable wireless links

That is acceptable. The sandbox is for onboarding, contracts, and regressions.

## Implemented Repo Shape

```text
docker-compose.onboarding-test.yml
docker/onboarding-test/
  fake-node/
  fixtures/
    gateway/
    inventories/
    thisnode/
scripts/
  run-compose-phase1-test.sh
  test-compose-phase1.sh
```

## Suggested Acceptance Criteria

The isolated test stack is useful when a fresh contributor can run one command such as:

```bash
bash scripts/test-compose-phase1.sh
```

And get proof that:

- discovery works against `thisnode.info`
- live mesh-readonly works against fixture inventory targets
- heartbeat writes `exports/mesh/latest.json`
- dry-run checks stay green

## Recommendation

Implement Phase 1 only at first. It is the highest-value, lowest-cost version and directly tests the onboarding path that is currently most important.
