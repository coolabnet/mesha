# Mesha — Community Infrastructure Operator

> A local-first, offline-capable AI assistant for community-owned mesh networks and servers. Built with OpenClaw for LibreMesh/OpenWrt networks and local community services.

[![Status](https://img.shields.io/badge/status-production--ready-success)]()
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macos%20%7C%20wsl2-lightgrey)]()

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

Get Mesha running in under 5 minutes on Linux, macOS, or Windows (WSL2).

### Prerequisites

```bash
# Required
git
nodejs 22+
ssh client

# Recommended
docker
tailscale
python3
jq
curl
```

### Install (one command)

```bash
# 1. Install OpenClaw CLI
npm install -g @openclaw/cli

# 2. Clone Mesha workspace
git clone https://github.com/ruvnet/mesha.git ~/community-ops/mesha
cd ~/community-ops/mesha

# 3. Run OpenClaw onboarding for this workspace
openclaw onboard --workspace .
```

### Verify Installation

```bash
# Run QA suite
bash tests/run-all.sh

# Run workspace health check
bash scripts/doctor.sh

# Confirm OpenClaw CLI is installed
openclaw --version
```

**Expected output:** You should see test results similar to:
```
PASS: 218   FAIL: 0   SKIP: 14
```

If tests fail, see [docs/troubleshooting.md](docs/troubleshooting.md) for help.

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
sudo apt install -y git curl jq python3 openssh-client

# Install Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# Install OpenClaw
npm install -g @openclaw/cli

# Clone and onboard
git clone https://github.com/ruvnet/mesha.git ~/community-ops/mesha
cd ~/community-ops/mesha
openclaw onboard --workspace .
```

### macOS

```bash
# Install Homebrew (if needed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install git curl jq python3 node@22
npm install -g @openclaw/cli

# Clone and onboard
git clone https://github.com/ruvnet/mesha.git ~/community-ops/mesha
cd ~/community-ops/mesha
openclaw onboard --workspace .
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
sudo apt install -y git curl jq python3 openssh-client

# Install Node.js 22
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22

# Install OpenClaw
npm install -g @openclaw/cli

# Clone and onboard (store in WSL2 filesystem, not /mnt/c/)
git clone https://github.com/ruvnet/mesha.git ~/community-ops/mesha
cd ~/community-ops/mesha
openclaw onboard --workspace .
```

### Common Installation Problems

| Problem | Solution |
|---------|----------|
| `npm install` fails with `EACCES` | Use `sudo npm install -g @openclaw/cli` or [configure npm prefix](https://docs.npmjs.com/resolving-eacces-permissions-errors) |
| Node.js version too old | Install Node.js 22+ using [nvm](https://github.com/nvm-sh/nvm) or package manager |
| WSL2 networking issues | See [docs/troubleshooting.md](docs/troubleshooting.md#wsl2-networking) |
| Permission denied on scripts | Run `chmod +x tests/*.sh scripts/*.sh` |

---

## Usage

### Start the Operator

```bash
# Start the OpenClaw gateway for Mesha
openclaw gateway

# Connect to chat interface
# See docs/deployment.md for channel setup
```

### Example Conversations

```
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
| [docs/deployment.md](docs/deployment.md) | Full deployment guide |
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

### Test Coverage

- ✅ Workspace file structure
- ✅ YAML syntax validation
- ✅ Schema compliance
- ✅ Configuration integrity
- ✅ Inventory completeness
- ✅ Desired-state consistency

---

## Project Structure

```
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

```
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

Built with OpenClaw — the local-first AI agent platform used by this workspace.

Inspired by community networks around the world who maintain their own infrastructure.

---

**Status:** All three phases complete ✅

See [PROGRESS.md](PROGRESS.md) for detailed status and [TASKS.md](TASKS.md) for any open work.
