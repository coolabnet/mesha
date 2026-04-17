# Mesha — Community Infrastructure Operator

> A local-first, offline-capable AI assistant for managing LibreMesh/OpenWrt community networks and offline-first local servers. Read-only by default, with safety-gated write operations.

[![Status](https://img.shields.io/badge/status-production--ready-success)](#status)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macos%20%7C%20wsl2-lightgrey)](#platform)

---

## Table of Contents

- [What is Mesha?](#what-is-mesha)
- [Quick Start](#quick-start)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Documentation](#documentation)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

---

## What is Mesha?

Mesha is a **Community Infrastructure Operator** that helps non-experts manage:

- **LibreMesh/OpenWrt community mesh networks** — topology, health, firmware rollouts
- **Local community servers** — offline-capable services, backups, monitoring
- **Human support workflows** — chat interfaces, voice summaries, bilingual support

It runs on community-controlled hardware, works offline when needed, and keeps risky operations behind explicit approval gates.

**Core Promise:** People manage their own communication and information infrastructure through familiar chat interfaces, while Mesha turns expert operations into safe, repeatable workflows.

---

## Quick Start

Mesha runs on top of **OpenClaw (Claude Code)**, an AI CLI agent. Follow these steps to get Mesha installed quickly on Linux, macOS, or Windows (WSL2).

### 1. Install OpenClaw (Claude Code)

Before using Mesha, you need to install the Claude Code CLI globally via npm and authenticate:

```bash
# Install Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Authenticate with your Anthropic account
claude setup-token
```

### 2. Install Mesha Workspace

```bash
# Clone Mesha workspace
git clone https://github.com/ruvnet/mesha.git ~/community-ops/mesha
cd ~/community-ops/mesha

# Run one-time setup and verify environment
bash scripts/bootstrap.sh --check-only

# Activate the workspace
bash scripts/activate-workspace.sh
```

### 3. Run Mesha

Start the interactive AI agent inside the workspace:

```bash
claude
```

*The agent will automatically read the workspace instructions and assume its role as the Mesha operator.*

---

### First Real Mesh Status

If you are a new maintainer and want the shortest path to the first real mesh status result, use this checklist:

```bash
# 0. Safest first proof: validate the onboarding flow in isolation
bash scripts/test-compose-phase1.sh

# 1. Validate and activate the workspace
bash scripts/doctor.sh
bash scripts/activate-workspace.sh

# 2. If connected to LibreMesh, bootstrap from thisnode.info
bash scripts/discover-from-thisnode.sh --plan
bash scripts/discover-from-thisnode.sh

# 3. Review and merge the candidate files into inventories/
#    exports/discovery/latest-candidate-node.yaml
#    exports/discovery/latest-candidate-gateway.yaml

# 4. Verify the normal live mesh reader
bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --plan
bash skills/mesh-readonly/scripts/run-mesh-readonly.sh

# 5. Write one cached heartbeat snapshot now
bash scripts/mesh-heartbeat.sh
```

If you are not connected to LibreMesh yet, skip step 2 and seed `inventories/` manually from your real node targets.
After step 5, schedule `bash scripts/mesh-heartbeat.sh` with cron or systemd so cached status stays fresh.

### Prerequisites

```bash
# Required
git
bash
curl
ssh client

# Recommended
docker with `docker compose`
python3
node.js 22+
jq
```

The isolated onboarding stack uses `docker compose`, not the legacy standalone `docker-compose` binary.

### Verify Installation

```bash
# Run workspace health check
bash scripts/doctor.sh

# Run QA suite
bash tests/run-all.sh

# Check that logs/ and exports/ directories are created
ls -la logs/ exports/
```

**Expected output:** You should see test results similar to:

```text
PASS: 219   FAIL: 0   SKIP: 14
```

If tests fail, see [docs/troubleshooting.md](docs/troubleshooting.md#section-5--installation-and-environment-setup) for help.

---

## Features

### Mesh Network Management

- **Node Inventory** — Track all mesh nodes, sites, and gateways
- **Topology Discovery** — Visualize network connections and paths
- **Health Monitoring** — Signal strength, link quality, gateway status
- **Configuration Drift Detection** — Compare live state to desired standards
- **Staged Rollouts** — Canary-first firmware upgrades with rollback
- **Physical Inference** — Detect obstructions, power issues, antenna problems

### Local Server Management

- **Service Catalog** — Approved services with install recipes
- **Local Domains** — Offline-first service access
- **Health Checks** — Disk, memory, service status
- **Backup & Restore** — Safe data management
- **Offline Validation** — Test services without internet

### Human-Centric Interface

- **Chat Channels** — WhatsApp, Telegram, or web interface
- **Voice Summaries** — Field-friendly audio explanations
- **Bilingual Support** — Community's preferred language
- **Simple Language** — No jargon without explanation

### Safety First

- **Risk Classes** — A/B/C/D classification for all operations
- **Approval Gates** — Explicit confirmation for risky changes
- **Rollback Plans** — Always know how to undo
- **Audit Logs** — Every approved action is recorded
- **Sandboxed Sessions** — Public channels never get write access

---

## Installation

### Linux (Ubuntu/Debian)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install base tools
sudo apt install -y git curl jq python3 openssh-client docker.io docker-compose-plugin

# Clone and activate
git clone https://github.com/ruvnet/mesha.git ~/community-ops/mesha
cd ~/community-ops/mesha
bash scripts/bootstrap.sh --check-only
bash scripts/activate-workspace.sh
```

### macOS

```bash
# Install Homebrew (if needed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install git curl jq python3 docker

# Clone and activate
git clone https://github.com/ruvnet/mesha.git ~/community-ops/mesha
cd ~/community-ops/mesha
bash scripts/bootstrap.sh --check-only
bash scripts/activate-workspace.sh
```

### Windows (WSL2)

```powershell
# Enable WSL2 (PowerShell as Administrator)
wsl --install
```

Then inside WSL2:

```bash
# Update and install tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl jq python3 openssh-client docker.io docker-compose-plugin

# Clone and activate (store in WSL2 filesystem, not /mnt/c/)
git clone https://github.com/ruvnet/mesha.git ~/community-ops/mesha
cd ~/community-ops/mesha
bash scripts/bootstrap.sh --check-only
bash scripts/activate-workspace.sh
```

### Common Installation Problems

| Problem | Solution |
|---------|----------|
| `bash scripts/bootstrap.sh` fails with "permission denied" | Run `chmod +x scripts/*.sh tests/*.sh` |
| Docker socket permission error | Add your user to the docker group: `sudo usermod -aG docker $USER` |
| WSL2 networking issues | See [docs/troubleshooting.md](docs/troubleshooting.md#53-wsl2-networking-issues) |
| Tests FAIL on fresh install | This is normal — most failures are "service not running". See docs/troubleshooting.md |

---

## Usage

### Start Using Mesha

```bash
# Workspace is now active. Paste the activation prompt printed by:
bash scripts/activate-workspace.sh

# Optional LibreMesh bootstrap if the current node answers to thisnode.info:
bash scripts/discover-from-thisnode.sh --plan
bash scripts/discover-from-thisnode.sh

# Review and merge candidate inventory data, then test live reads:
bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --plan
bash skills/mesh-readonly/scripts/run-mesh-readonly.sh

# Write one cached snapshot now:
bash scripts/mesh-heartbeat.sh
```

`inventories/` is the human-maintained source for identity and site context. `exports/mesh/latest.json` is the machine-managed cached status written by heartbeat runs. To keep that cache fresh, schedule `bash scripts/mesh-heartbeat.sh` with cron or systemd on the ops host.

### Example Conversations

```text
# Check mesh status
You: "Why is the school offline?"
Mesha: "Node at the school (node-escuela) has not responded since 11pm last night.
       The most likely cause is a power cut — that router loses connection every
       time the building power goes out. Check if the building has power before
       assuming a hardware fault."

# Install a service
You: "Install a local media archive on the server"
Mesha: [creates plan, requests approval, executes, validates]

# Get voice summary
You: "Give me a voice-friendly summary of the mesh health"
Mesha: [produces short, simple explanation suitable for audio playback]
```

### Risk Classes

| Class | Description | Approval Required |
|-------|-------------|-------------------|
| **A** | Read-only inspections | No |
| **B** | Low-risk writes (restarts, docs) | Sometimes |
| **C** | Medium-risk changes | Yes |
| **D** | High-risk or multi-host | Yes + change window |

---

## Documentation

| Document | Description |
|----------|-------------|
| [BOOTSTRAP.md](BOOTSTRAP.md) | Architecture, setup, and activation |
| [AGENTS.md](AGENTS.md) | Agent roles and orchestration |
| [SOUL.md](SOUL.md) | Tone, communication style, and values |
| [TOOLS.md](TOOLS.md) | Tool permissions and risk classes |
| [docs/configuration.md](docs/configuration.md) | Required inventories, secrets, maintainer identities, and adapter config |
| [docs/deployment.md](docs/deployment.md) | Full deployment guide |
| [docs/testing/isolated-compose-plan.md](docs/testing/isolated-compose-plan.md) | Plan for an isolated Compose-based onboarding test stack |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common problems and fixes |
| [docs/playbooks/](docs/playbooks/) | Operational procedures |

---

## Testing

Mesha includes a comprehensive test suite.

### Run All Tests

```bash
# Run entire test suite
bash tests/run-all.sh
```

### Individual Test Categories

```bash
# File inventory tests
bash tests/01-file-inventory.sh

# Syntax validation
bash tests/02-syntax.sh

# Schema validation
bash tests/03-schema.sh

# Dry-run checks
bash tests/04-dryrun.sh

# Health checks
bash tests/05-healthchecks.sh
```

### Isolated Onboarding Stack

If Docker is available and you want an end-to-end onboarding proof without touching real routers:

```bash
bash scripts/test-compose-phase1.sh
```

This is the recommended first validation for a brand-new maintainer. It builds the fake LibreMesh fixtures, runs discovery, runs the live mesh reader, and verifies heartbeat output in a disposable workspace copy.

### Test Coverage

- ✅ Workspace file structure
- ✅ YAML syntax validation
- ✅ Schema compliance
- ✅ Configuration integrity
- ✅ Inventory completeness
- ✅ Desired-state consistency

---

## Project Structure

```text
mesha/
├── README.md              # This file
├── BOOTSTRAP.md           # Architecture & activation
├── AGENTS.md              # Agent roles
├── SOUL.md                # Communication style
├── TOOLS.md               # Permissions & risk
├── MEMORY.md              # Project memory
├── WORKING.md             # Status & gaps
├── TASKS.md               # Task log
├── PROGRESS.md            # Progress tracking
│
├── scripts/               # Bootstrap & utility scripts
├── skills/                # Agent capabilities
│   ├── community-ops-frontdesk/
│   ├── mesh-readonly/
│   ├── mesh-rollout/
│   ├── mesh-onboarding/
│   ├── server-readonly/
│   ├── server-services/
│   ├── incident-triage/
│   ├── knowledge-curator/
│   └── voice-friendly-response/
│
├── adapters/              # Hardware/system interfaces
│   ├── mesh/
│   ├── server/
│   └── channels/
│
├── inventories/           # Actual state (nodes, sites, services)
├── desired-state/         # Desired configuration
│   ├── mesh/
│   └── server/
│
├── docs/                  # Documentation
│   ├── playbooks/
│   ├── onboarding/
│   └── known-issues/
│
├── tests/                 # Test suite
├── logs/                  # Operation logs
├── exports/               # Data exports
└── secrets/               # Local-only credentials (not committed)
```

---

## Contributing

We welcome contributions! Please open an issue first to discuss large changes.

### Ways to Contribute

- **Bug Reports** — Open an issue with details
- **Feature Requests** — Describe the use case
- **Documentation** — Improve guides and playbooks
- **Code** — Submit pull requests
- **Testing** — Run test suite on new environments

### Development Workflow

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/mesha.git
cd mesha

# Create branch
git checkout -b feature/your-feature-name

# Make changes and test
bash tests/run-all.sh

# Commit and push
git commit -m "feat: add your feature"
git push origin feature/your-feature-name

# Open pull request
```

---

## Architecture

Mesha uses a **three-layer model**:

```text
┌─────────────────────────────────────┐
│     Conversation Layer              │
│  community-ops-frontdesk             │
└──────────────┬──────────────────────┘
                 │
  ┌──────────────┴──────────────────────┐
  │         Planning Layer               │
  │  mesh-planner  |  server-planner     │
  │  mesh-collector                      │
  └──────────────┬──────────────────────┘
                 │
  ┌──────────────┴──────────────────────┐
  │        Execution Layer               │
  │  mesh-executor | server-executor     │
  └─────────────────────────────────────┘
```

1. **Conversation Layer** — `community-ops-frontdesk` receives and routes requests
2. **Planning Layer** — `mesh-planner` and `server-planner` create safe execution plans
3. **Execution Layer** — `mesh-executor` and `server-executor` perform approved actions

### Key Principles

- **Local First** — Runs on community hardware
- **Offline First** — Works without internet
- **Read Before Write** — Inspect before changing
- **Declarative State** — Compare real to desired
- **Small Trust Surface** — Narrow execution agents
- **Human Auditable** — Explain before, log after

For full architecture details, see [BOOTSTRAP.md](BOOTSTRAP.md).

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Support

- **Documentation:** [docs/](docs/)
- **Troubleshooting:** [docs/troubleshooting.md](docs/troubleshooting.md)
- **Issues:** [GitHub Issues](https://github.com/ruvnet/mesha/issues)

---

## Acknowledgments

Designed for community networks around the world who maintain their own infrastructure.

Built on proven patterns from LibreMesh deployments across Africa, Latin America, and Asia.

---

**Status:** All three phases complete ✅

See [PROGRESS.md](PROGRESS.md) for detailed status and [TASKS.md](TASKS.md) for any open work.
