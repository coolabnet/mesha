# Troubleshooting

**Purpose:** This document helps you diagnose and fix common problems with the Mesha operator, the mesh network, the local server, and agent behavior.

Use the section headers to jump to the area where you are seeing issues.

---

## How to Read This Document

Each problem uses this structure:

- **Problem:** What you are observing
- **Symptoms:** Specific signs that match this problem
- **Diagnosis:** How to confirm the cause
- **Fix:** What to do

---

## Section 1 — Mesh Network Problems

### 1.1 A node is offline or unreachable

**Problem:** A node that should be online is not responding.

**Symptoms:**
- The operator says "node not found" or "no response from node"
- `mesh-readonly` shows the node as missing from topology
- Users at that site report no connectivity

**Diagnosis:**
```bash
# From a host on the local network, try to ping the node
ping <node-ip>

# Try SSH
ssh root@<node-ip>

# Check if the node appears in mesh routing tables from a neighbor
ssh root@<neighbor-node-ip>
ubus call network.interface dump
batctl n   # if using batman-adv
```

Check the operator's inventory:
```bash
grep -A5 "<node-name>" inventories/mesh-nodes.yaml
```

**Fix:**

1. If the node does not respond to ping: power issue is most likely. Check the physical power supply and cables at the site.
2. If the node responds to ping but not SSH: check SSH keys or firewall rules.
3. If the node is reachable but not in the mesh routing table: it may have lost its mesh interface. Reboot it (with approval) and check `logread` after.
4. If the node was recently reconfigured: compare its config to `desired-state/mesh/node-overrides/` and check for drift.

---

### 1.2 Weak or flapping link between two nodes

**Problem:** A link exists but is unstable or has high packet loss.

**Symptoms:**
- `mesh-readonly` reports poor link quality scores
- Users experience slow or dropping connections
- The operator flags this as a weak link in summaries

**Diagnosis:**
```bash
# On one of the affected nodes
ssh root@<node-ip>

# Check signal and noise for the wireless interface
iwinfo <interface> info
iwinfo <interface> scan

# Check link quality in batman-adv
batctl o   # originators table
batctl l   # local translation table

# Check if there is packet loss
ping -c 20 <neighbor-ip>
```

**Fix:**

1. **Low signal / high noise:** physical obstruction (new building, vegetation) or antenna misalignment. Walk the line of sight and check physically.
2. **Interference or congestion:** try a different channel. Update `lime-community` channel settings and roll out with `mesh-rollout` skill (requires approval).
3. **Asymmetric link (one side sees the other, the other does not):** may be a power issue on one radio, or one antenna is damaged. Check both nodes.
4. **Flapping (on and off repeatedly):** check power stability at both ends. Voltage fluctuations cause radio resets.

---

### 1.3 Config drift detected

**Problem:** A node's running config does not match the community desired state.

**Symptoms:**
- `mesh-readonly` diff report shows differences
- The operator says "this node differs from the community standard"
- The node was manually configured by someone outside the normal workflow

**Diagnosis:**
```bash
# Review the desired state
cat desired-state/mesh/community-profile/lime-community
cat desired-state/mesh/node-overrides/<node-name>.yaml   # if it exists

# Pull the live config from the node
ssh root@<node-ip> "uci show lime-node"
ssh root@<node-ip> "cat /etc/config/lime-community"
```

Compare the two manually or use the operator's diff skill.

**Fix:**

1. If the drift was intentional (a node-level override): document it in `desired-state/mesh/node-overrides/` so it is no longer flagged.
2. If the drift was unintentional (manual edit): use `mesh-rollout` to restore the node to the desired state. Requires approval.
3. If the cause is unknown: use `knowledge-curator` to write a note in the node's record before making changes.

---

### 1.4 Gateway or backhaul is down

**Problem:** The mesh is up internally but has no internet access or no uplink.

**Symptoms:**
- Nodes can reach each other but not external addresses
- The operator reports gateway as unreachable
- DNS lookups fail

**Diagnosis:**
```bash
# On the gateway node
ssh root@<gateway-ip>
ping 8.8.8.8           # test internet
ping <ISP-gateway-ip>  # test ISP uplink
ip route               # check default route
logread | tail -50     # check recent logs
```

**Fix:**

1. **ISP uplink is down:** contact ISP or check physical connection to the ISP equipment (modem, fiber ONT). This is outside the mesh — the mesh itself is fine.
2. **Gateway node is up but route is missing:** reboot the gateway (with approval) or restore the WAN interface config.
3. **Wrong gateway in routing:** check that the correct node is configured as gateway in `desired-state/mesh/community-profile/` and that other nodes have not elected a different gateway.

---

## Section 2 — Local Server Problems

### 2.1 A local service is not reachable

**Problem:** A service that should be running is not accessible on its local domain.

**Symptoms:**
- Browser shows "connection refused" or "site not found" on the local domain
- The operator's `server-readonly` health check fails for this service
- Users report the service is down

**Diagnosis:**
```bash
# Check if the container or service process is running
docker ps | grep <service-name>
systemctl status <service-name>

# Check if the port is listening
ss -tlnp | grep <port>

# Test the service directly (bypass reverse proxy)
curl http://localhost:<port>/

# Check the reverse proxy
nginx -t                         # if using Nginx
systemctl status nginx

# Check local DNS
grep <local-domain> /etc/hosts
nslookup <local-domain> localhost
```

**Fix:**

1. **Service is not running:** start it with `docker start <name>` or `systemctl start <name>`. Check logs first: `docker logs <name>` or `journalctl -u <name>`.
2. **Service is running but port is wrong:** check the service's port mapping in its compose file or unit file. Update `desired-state/server/service-catalog.yaml` if the port changed.
3. **Reverse proxy is not routing correctly:** check the proxy config in `desired-state/server/reverse-proxy.yaml` and compare to the actual Nginx/Caddy config. Use `server-services` skill to sync it (requires approval).
4. **Local domain not resolving:** check `/etc/hosts` or local DNS. The entry may be missing. Add it via the `server-services` skill.

---

### 2.2 Disk space is running low

**Problem:** The local server is running out of disk space.

**Symptoms:**
- `server-readonly` reports disk usage above 80% or 90%
- Services start failing with "no space left on device" errors
- Logs stop writing

**Diagnosis:**
```bash
# Check disk usage by filesystem
df -h

# Find what is using space
du -sh /var/lib/docker/*    # Docker images and volumes
du -sh /var/log/*           # Logs
du -sh /home/*              # User data
du -sh /opt/*               # Installed services
```

**Fix:**

1. **Docker taking up space:** run `docker system prune` to remove unused images and stopped containers. Check with the operator before doing this — some containers may be intentionally stopped but needed.
2. **Logs growing too large:** check log rotation settings in `/etc/logrotate.d/`. Rotate manually: `logrotate -f /etc/logrotate.conf`.
3. **Service data growing:** check backup policy in `desired-state/server/backup-policy.yaml`. Data may need to be archived or pruned. Do not delete data without understanding what it is.
4. **Run disk cleanup through the operator:** ask the operator "the server disk is almost full, what should I do?" to get a guided, safe cleanup plan.

---

### 2.3 A service is working but the local domain is not

**Problem:** The service is running and reachable by IP, but the local domain does not work.

**Symptoms:**
- `http://localhost:<port>` works
- `http://<service>.local` or `http://<service>.community` does not work

**Diagnosis:**
```bash
# Test DNS resolution
nslookup <local-domain>
ping <local-domain>

# Check /etc/hosts
grep <local-domain> /etc/hosts

# Check reverse proxy config
cat /etc/nginx/sites-enabled/<service>
```

**Fix:**

1. Add the domain to `/etc/hosts` on the affected machine: `127.0.0.1 <local-domain>` (or the server's LAN IP if configuring on a client machine).
2. If you are using a local DNS server, add the record there.
3. Verify the reverse proxy has a server block for the domain.
4. Use the `server-services` skill to set up the local domain properly and record it in `desired-state/server/domains.yaml`.

---

## Section 3 — Connectivity and Access Problems

### 3.1 Cannot SSH into a node or server

**Problem:** SSH connection is refused or times out.

**Symptoms:**
- `ssh: connect to host <ip> port 22: Connection refused`
- `ssh: connect to host <ip> port 22: Connection timed out`
- Password prompt appears but authentication fails

**Diagnosis:**
```bash
# Test if the host is reachable at all
ping <ip>

# Test if the SSH port is open
nc -zv <ip> 22

# Try verbose SSH to see where it fails
ssh -v root@<ip>
```

**Fix:**

1. **Host is not reachable (ping fails):** network connectivity issue. Check that you are on the right network (LAN, mesh, Tailscale). See Section 1.1 if it is a mesh node.
2. **Port 22 is closed:** SSH may be disabled or on a non-standard port. Check the node's firewall config or the server's SSH daemon settings.
3. **Authentication fails with key:** the key is not in `authorized_keys` on the target. You may need physical access to add your key. Check `~/.ssh/authorized_keys` on the target host.
4. **Authentication fails with password:** the password may have changed, or password authentication may be disabled. Use key-based auth.

---

### 3.2 Cannot reach the operator from a chat channel

**Problem:** Messages sent to the bot are not receiving responses.

**Symptoms:**
- Messages to the WhatsApp/Telegram bot go unanswered
- The channel was working before but stopped
- Some channels work but others do not

**Diagnosis:**
```bash
# Check if OpenClaw is running
openclaw status

# Check the channel adapter logs
openclaw logs --channel <channel-name>

# Check network access from the ops host
curl https://api.telegram.org/bot<token>/getMe   # Telegram example
```

**Fix:**

1. **OpenClaw is not running:** restart it: `openclaw gateway --force` or the appropriate service command.
2. **Channel token expired or revoked:** regenerate the bot token in the channel's admin interface and update it in the local secrets store. Never commit tokens to the repo.
3. **The ops host lost internet:** if the channel requires internet (e.g., Telegram), the ops host needs network access. Check the host's network.
4. **The channel is in an untrusted/sandboxed mode:** if the message was sent from a public group, the operator may be intentionally not responding to write requests. This is expected behavior.

---

## Section 4 — Agent Behavior Problems

### 4.1 The operator is not routing requests to the right agent

**Problem:** The frontdesk agent is handling requests itself or sending them to the wrong specialist.

**Symptoms:**
- Mesh questions are answered by the server planner
- The response is generic and not specialized
- The operator says "I can't handle that" for requests it should handle

**Diagnosis:**
Look at the routing logic in `skills/community-ops-frontdesk/SKILL.md`. Check whether the keywords or intent patterns for this type of request are defined.

**Fix:**

1. Review `AGENTS.md` to ensure agent boundaries are described correctly.
2. Update the routing logic in `skills/community-ops-frontdesk/SKILL.md` to add or fix the intent classification for this type of request.
3. If using OpenClaw's multi-agent routing, check that agent names in the skill file match the agent names defined in `AGENTS.md`.

---

### 4.2 The operator is making changes without asking for approval

**Problem:** The operator is performing write operations without requesting explicit approval.

**Symptoms:**
- Infrastructure changes happen without a confirmation step
- The operator says "done" without asking first
- A Class C or D operation ran from an untrusted channel

**Diagnosis:**
Check the relevant skill file (e.g., `skills/mesh-rollout/SKILL.md`) and verify that approval gates are defined. Check `TOOLS.md` for the write permission constraints.

**Fix:**

1. This is a critical safety issue. Stop the operator and review the skill file immediately.
2. Add or restore the approval gate in the skill's execution logic.
3. Review `TOOLS.md` and ensure write tools require the `approval_required: true` constraint.
4. Check `AGENTS.md` to confirm that the executor agents are not reachable directly from public channels.
5. Log the incident in `logs/` and the `knowledge-curator` skill.

---

### 4.3 The operator cannot find inventory data

**Problem:** The operator says it cannot find a node, site, or service that exists.

**Symptoms:**
- "I don't have information about that node"
- Topology maps are empty
- Site names are not recognized

**Diagnosis:**
```bash
# Check that inventory files exist and have content
cat inventories/mesh-nodes.yaml
cat inventories/sites.yaml
cat inventories/local-services.yaml
```

**Fix:**

1. If files are empty or missing, they need to be populated. Use the `knowledge-curator` skill or fill them in manually following the YAML format in each file.
2. If the data is there but not being read, check whether the workspace is activated and pointing at the correct directory.
3. Make sure the workspace path in OpenClaw matches the `mesha` repo path.

---

### 4.4 Responses are in the wrong language or too technical

**Problem:** The operator is responding in a language the user does not understand, or using technical jargon.

**Symptoms:**
- Responses are in English but the community uses Portuguese (or another language)
- Explanations are full of network terminology
- Voice summaries are too long or too complex

**Diagnosis:**
Check `SOUL.md` for the community's preferred language and tone settings. Check the `voice-friendly-response` skill.

**Fix:**

1. Update `SOUL.md` with the correct default language and communication style for the community.
2. The `voice-friendly-response` skill should be called for outputs that go to voice or low-literacy contexts. Check that the frontdesk is invoking it correctly.
3. Ask the operator directly: "explain that in simple Portuguese" — this should trigger the voice-friendly response skill.

---

## Section 5 — Installation and Setup Problems

### 5.1 OpenClaw CLI install fails

**Problem:** `npm install -g @openclaw/cli` fails with an error.

**Common errors and fixes:**

| Error | Fix |
|---|---|
| `EACCES: permission denied` | Use `sudo` or configure npm to use a user-writable prefix: `npm config set prefix ~/.npm-global` |
| `ENOENT: no such file` | Node.js may not be installed. Run `node --version` and reinstall if needed |
| `unsupported engine` | Your Node.js version is too old. Install Node 22+ |
| Network timeout | Check internet connection. Try `npm install -g @openclaw/cli --prefer-offline` if you have a cached version |

---

### 5.2 Doctor script reports missing files

**Problem:** `scripts/doctor.sh` reports that required files or directories are missing.

**Fix:**

1. Check that the workspace repo was cloned correctly: `git status` and `ls` inside the repo.
2. If inventory files are missing, create empty stubs: `touch inventories/mesh-nodes.yaml`.
3. If desired-state files are missing, copy from the template or create them following the format in `BOOTSTRAP.md`.
4. Run the doctor again after each fix.

---

### 5.3 WSL2 networking issues

**Problem:** On Windows with WSL2, the network tools cannot reach the local LAN.

**Symptoms:**
- Can ping internet but not LAN devices from WSL2
- SSH to LAN hosts fails
- `ping 192.168.x.x` times out

**Diagnosis:**
WSL2 uses a virtual network adapter by default. Your LAN devices may not be directly reachable.

**Fix:**

1. Check your WSL2 IP: `ip addr show eth0`
2. Try adding a route to your LAN subnet from WSL2.
3. For full LAN access, use Tailscale — install it on both the WSL2 host and the target machines.
4. Alternatively, configure WSL2 to use a bridged network adapter (this requires editing WSL2 config files — see Microsoft's WSL2 documentation for your Windows version).

---

## Quick Diagnostic Checklist

Use this checklist when something is broken and you are not sure where to start:

- [ ] Is the ops host powered on and connected to the network?
- [ ] Is OpenClaw running? (`openclaw status`)
- [ ] Is the workspace configured? (`openclaw config get agents.defaults.workspace`)
- [ ] Are the inventory files populated? (`ls inventories/`)
- [ ] Can you SSH into the affected node or server? (`ssh root@<ip>`)
- [ ] Is the affected node reachable on the network? (`ping <ip>`)
- [ ] Do the logs show any errors? (`openclaw logs`, `docker logs`, `journalctl`)
- [ ] Has anything changed recently? (check `logs/` for recent approved actions)
- [ ] Is this a known issue? (search `docs/` and `inventories/`)

If you cannot resolve the issue, record it in the knowledge-curator skill so it becomes part of the project's known issues documentation.
