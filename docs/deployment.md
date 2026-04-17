# Deployment

**Purpose:** This document walks you through installing and activating the Mesha Community Infrastructure Operator on a new host. It covers Linux, macOS, and Windows with WSL2.

By the end of this guide, the system will be running and you will be able to inspect your mesh and local server safely.

For the exact configuration and secret inputs a maintainer must provide, read `docs/configuration.md` alongside this guide.

The shortest successful onboarding path is:

1. Install the workspace and confirm OpenClaw runs.
2. Seed the inventories once with real node targets and site context.
3. Verify SSH access manually to one router.
4. Run one heartbeat now, then schedule it so fresh snapshots keep appearing under `exports/`.
5. Let chat queries use live reads first and heartbeat snapshots as cached fallback.

---

## Before You Start

### What you need

- A computer you will use as the **Primary Community Ops Host** or a **Field Maintainer Laptop** (see `docs/architecture.md` for role descriptions)
- Internet access during installation (the system runs offline after setup)
- SSH access to at least one mesh node or local server (for testing the connection)
- About 30–60 minutes

### What you will install

| Tool | Why |
|---|---|
| Git | Clone and manage the workspace repo |
| Node.js 22+ | Required by OpenClaw CLI |
| OpenClaw CLI | The agent runtime that runs the workspace |
| SSH client | Connect to mesh nodes and servers |
| Docker (recommended) | Run local services and containers |
| Tailscale (recommended) | Remote access without opening firewall ports |
| Python 3 (recommended) | Helper scripts |
| `jq`, `curl` (recommended) | Data processing and HTTP testing |

---

## Linux Installation

Tested on Ubuntu 22.04 and Debian 12. Steps are similar for other distributions.

### Step 1 — Update your system

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 2 — Install base tools

```bash
sudo apt install -y git curl jq python3 python3-pip openssh-client
```

### Step 3 — Install Node.js 22

Do not use the default `apt` Node.js package — it is usually too old. Use the NodeSource repository or `nvm`.

**Option A — NodeSource:**

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
node --version   # should print v22.x.x
```

**Option B — nvm (recommended for flexibility):**

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22
node --version
```

### Step 4 — Install OpenClaw CLI

```bash
npm install -g @openclaw/cli
openclaw --version
```

If the install fails, try:

```bash
npm install -g @openclaw/cli --unsafe-perm
```

### Step 5 — Install Docker (recommended)

```bash
sudo apt install -y docker.io
sudo usermod -aG docker $USER
# Log out and back in, then verify:
docker run hello-world
```

### Step 6 — Install Tailscale (recommended)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Step 7 — Clone the workspace repo

```bash
mkdir -p ~/community-ops
cd ~/community-ops
git clone <your-repo-url> mesha
cd mesha
```

### Step 8 — Run OpenClaw onboarding

```bash
openclaw onboard --workspace .
```

Follow the prompts. The `--workspace .` flag points OpenClaw at the `mesha` directory you just cloned.

### Step 9 — Confirm the workspace path

```bash
cd ~/community-ops/mesha
openclaw config set agents.defaults.workspace "$(pwd)"
openclaw config get agents.defaults.workspace
```

If you prefer the repo helper, you can also run:

```bash
bash scripts/activate-workspace.sh
```

This helper creates the local runtime directories under `logs/` and `exports/`, then prints the activation prompt from `BOOTSTRAP.md`.

### Step 10 — Run the health check

```bash
bash scripts/doctor.sh
```

The doctor script checks that all prerequisites are installed and that the workspace structure looks correct. Fix any items it flags before continuing. If it warns that `logs/` or `exports/` are missing, run `bash scripts/activate-workspace.sh` once and then re-run the doctor.

### Step 11 — Seed the mesh inventory once

Before the operator can read your real mesh, replace the example entries in:

- `inventories/mesh-nodes.yaml`
- `inventories/gateways.yaml`
- `inventories/sites.yaml`

Minimum required seed data:

- `mesh-nodes.yaml`: stable node name, SSH target in `hostname`, site, hardware model, role
- `gateways.yaml`: which node is a gateway and which SSH target should be used for topology reads
- `sites.yaml`: human site names, access notes, local contacts

Important: in this workspace, the `hostname` field is the actual connection target used by live mesh reads. If your DNS is not set up, use the management IP instead of a hostname.

### Step 12 — Verify SSH outside the operator

Test at least one real node manually before relying on chat:

```bash
ssh root@<real-node-target>
```

If SSH does not work here, the operator will not be able to collect live state either.

Optional shortcut on LibreMesh:

If you are already connected to the mesh LAN or Wi-Fi and the local node responds to `thisnode.info`, you can bootstrap discovery before finishing the full inventory:

```bash
bash scripts/discover-from-thisnode.sh --plan
bash scripts/discover-from-thisnode.sh
```

This writes machine-observed draft data under `exports/discovery/`. Review that output and use it to fill `inventories/mesh-nodes.yaml` and `inventories/gateways.yaml`. Do not treat discovery output as a replacement for site names, contacts, or physical notes.

The discovery script writes both:

- `exports/discovery/latest-candidate-node.yaml`
- `exports/discovery/latest-candidate-gateway.yaml`

Only merge the gateway candidate if the discovered node is truly a gateway.

### Step 13 — Run heartbeat now, then schedule it

Run the mesh heartbeat script once on the primary ops host:

```bash
bash scripts/mesh-heartbeat.sh
```

This writes machine-managed cached state under:

- `exports/mesh/latest.json`
- `exports/mesh/snapshots/*.json`

Recommended cadence:

- Small mesh: every 10 minutes
- Larger or unstable mesh: every 5 minutes
- Battery-sensitive or bandwidth-limited mesh: every 15 minutes

Example cron entry:

```cron
*/10 * * * * cd /path/to/mesha && bash scripts/mesh-heartbeat.sh >> /tmp/mesha-heartbeat.log 2>&1
```

This single run writes a fresh cache snapshot. To keep live status fresh, schedule the same command with cron or systemd. The inventories remain the human-curated source for identity, site context, and topology intent.

---

## macOS Installation

Tested on macOS 13 (Ventura) and 14 (Sonoma) with Apple Silicon and Intel.

### Step 1 — Install Homebrew

If you do not have Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After install, follow the instructions to add Homebrew to your PATH (especially on Apple Silicon).

### Step 2 — Install base tools (macOS)

```bash
brew install git curl jq python3
```

SSH client is already included with macOS.

### Step 3 — Install Node.js 22 (macOS)

```bash
brew install node@22
echo 'export PATH="/opt/homebrew/opt/node@22/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
node --version   # should print v22.x.x
```

Or use `nvm` (same commands as Linux above).

### Step 4 — Install OpenClaw CLI (macOS)

```bash
npm install -g @openclaw/cli
openclaw --version
```

### Step 5 — Install Docker (recommended, macOS)

Download Docker Desktop from <https://www.docker.com/products/docker-desktop/> and install it. Start Docker Desktop before running any container commands.

### Step 6 — Install Tailscale (recommended, macOS)

Download from <https://tailscale.com/download/mac> or:

```bash
brew install --cask tailscale
```

Open Tailscale from the menu bar and log in.

### Step 7 — Clone the workspace repo (macOS)

```bash
mkdir -p ~/community-ops
cd ~/community-ops
git clone <your-repo-url> mesha
cd mesha
```

### Step 8 — Run OpenClaw onboarding (macOS)

```bash
openclaw onboard --workspace .
```

The `--workspace .` flag points OpenClaw at the `mesha` directory or merge target described in the Linux steps.

### Step 9 — Confirm the workspace path (macOS)

```bash
cd ~/community-ops/mesha
openclaw config set agents.defaults.workspace "$(pwd)"
openclaw config get agents.defaults.workspace
```

If you prefer the repo helper, you can also run:

```bash
bash scripts/activate-workspace.sh
```

This helper creates the local runtime directories under `logs/` and `exports/`, then prints the activation prompt from `BOOTSTRAP.md`.

### Step 10 — Run the health check (macOS)

```bash
bash scripts/doctor.sh
```

If the doctor warns that `logs/` or `exports/` are missing, run `bash scripts/activate-workspace.sh` once and then re-run the doctor.

---

## Windows + WSL2 Installation

WSL2 (Windows Subsystem for Linux 2) is the standard path for Windows. Do not try to run this system in a native PowerShell-only environment — the SSH, router, and scripting tooling works much better in a Linux shell.

### Step 1 — Enable WSL2

Open PowerShell as Administrator and run:

```powershell
wsl --install
```

This installs WSL2 and Ubuntu. Restart your computer when prompted.

If you already have WSL1:

```powershell
wsl --set-default-version 2
```

### Step 2 — Open Ubuntu in WSL2 (Windows)

Launch "Ubuntu" from the Start menu or run:

```powershell
wsl
```

You are now inside a Linux shell. All following steps run inside this Linux shell.

### Step 3 — Install base tools (inside WSL2, Windows)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl jq python3 python3-pip openssh-client
```

### Step 4 — Install Node.js 22 (inside WSL2, Windows)

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22
node --version
```

### Step 5 — Install OpenClaw CLI (inside WSL2, Windows)

```bash
npm install -g @openclaw/cli
openclaw --version
```

### Step 6 — Install Docker (Windows)

**Option A — Docker Desktop with WSL2 integration (easiest):**

1. Download Docker Desktop from <https://www.docker.com/products/docker-desktop/>
2. During setup, enable WSL2 integration.
3. In Docker Desktop settings → Resources → WSL Integration, enable your Ubuntu distro.
4. Test inside WSL2: `docker run hello-world`

**Option B — Docker Engine directly in WSL2:**

```bash
sudo apt install -y docker.io
sudo usermod -aG docker $USER
# Open a new WSL2 terminal, then:
docker run hello-world
```

### Step 7 — Install Tailscale (recommended, Windows)

Inside WSL2:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Step 8 — Clone the workspace repo (inside WSL2, Windows)

Store the repo inside the WSL2 filesystem (not under `/mnt/c/`) for best performance:

```bash
mkdir -p ~/community-ops
cd ~/community-ops
git clone <your-repo-url> mesha
cd mesha
```

### Step 9 — Run OpenClaw onboarding (inside WSL2, Windows)

```bash
openclaw onboard --workspace .
```

### Step 10 — Confirm the workspace path (inside WSL2, Windows)

```bash
cd ~/community-ops/mesha
openclaw config set agents.defaults.workspace "$(pwd)"
openclaw config get agents.defaults.workspace
```

### Step 11 — Run the health check (inside WSL2, Windows)

```bash
bash scripts/doctor.sh
```

If the doctor warns that `logs/` or `exports/` are missing, run `bash scripts/activate-workspace.sh` once and then re-run the doctor.

---

## Workspace Activation

After installation, activate the operator using the activation prompt from BOOTSTRAP.md. In your OpenClaw chat or CLI:

```text
Read BOOTSTRAP.md, AGENTS.md, SOUL.md, TOOLS.md, MEMORY.md, and WORKING.md
from the workspace root and activate this project as a Community Infrastructure
Operator for LibreMesh/OpenWrt networks and local offline-first servers.
```

The system will respond by:

1. Summarizing the mission
2. Listing the available agents and skills
3. Identifying any missing files or inventories
4. Proposing the next steps

---

## Health Check

Use the doctor script first:

```bash
bash scripts/doctor.sh
```

It verifies:

- [ ] Git is installed and functional
- [ ] Node.js 22+ is installed
- [ ] OpenClaw CLI is installed and responds
- [ ] SSH client is available
- [ ] Docker is available (warning only if missing)
- [ ] Workspace directory structure is present
- [ ] Required inventory files exist
- [ ] Required desired-state files exist
- [ ] Secrets directory has a README and no committed secrets

If you need to double-check the environment manually, use:

```bash
git --version
node --version
openclaw --version
ssh -V
docker --version 2>/dev/null || echo "Docker not installed (optional)"
ls inventories/
ls desired-state/
```

---

## Host Roles Reference

| Role | Description | What to run |
|---|---|---|
| Primary Community Ops Host | Always-on host, runs the full workspace | All steps above + scheduler |
| Field Maintainer Laptop | Portable, used for maintenance and emergencies | All steps above, portable mode |
| Optional Remote Relay Host | Only for remote access and notifications | Minimal install, no local tooling required |

The same workspace repo is used on all roles. Host-specific configuration (secrets, SSH keys, machine-specific paths) must not be committed to the repo.

---

## Secrets and Credentials

Never store secrets in committed files. The `secrets/` directory exists as a local-only store.

Read `secrets/README.md` for the approved approach. In brief:

- SSH keys: store in `~/.ssh/` on each host, not in the repo
- API tokens: use environment variables or a local secrets manager
- Passwords: use a local password manager or a separate `.env` file that is listed in `.gitignore`

---

## Next Steps After Deployment

1. Fill in `inventories/mesh-nodes.yaml` with your actual nodes
2. Fill in `inventories/sites.yaml` with your site names and locations
3. Fill in `desired-state/mesh/community-profile/lime-community` with your community settings
4. Test read-only mesh inspection: ask the operator "show me the mesh status"
5. Test read-only server inspection: ask "check the local server health"
6. When comfortable, proceed to the node onboarding and service install playbooks
