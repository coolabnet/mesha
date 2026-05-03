# Local Service Install Playbook

**Purpose:** Step-by-step guide for installing an approved service on the community local server — including prerequisites, installation, local domain setup, validation, and backup hooks.

**Risk class:** Class C — requires explicit approval before applying changes. All steps up to and including Step 7 are read-only and can be done without approval.

---

## Before You Start

### What counts as an "approved service"

Only install services that are listed in `desired-state/server/service-catalog.yaml` with a status of `approved`. If you want to install something that is not on the list, add it to the catalog and get it approved first — do not install unapproved software on community infrastructure.

### What you need

- [ ] The service is listed in `desired-state/server/service-catalog.yaml` as `approved`
- [ ] A maintainer with approval rights is available
- [ ] You have SSH access to the local server
- [ ] The server has enough disk space (check before starting)
- [ ] Docker is installed on the server (most service recipes use containers)
- [ ] The backup policy covers this server (`desired-state/server/backup-policy.yaml`)

### When NOT to proceed

- The service is not in the approved catalog
- The server is currently having issues (disk full, memory pressure, services failing)
- There is an active incident on the network
- You do not have explicit approval from a maintainer

---

## Phase 1 — Verify Prerequisites

### Step 1 — Check the server health

Ask the operator:

> "Check the health of the local server before I install a new service."

Or check manually:

```bash
ssh <user>@<server-ip>

# Disk space — need at least 2GB free, ideally more
df -h

# Memory — check available RAM
free -h

# Running services — make sure the server is stable
docker ps
systemctl --failed

# CPU load
uptime
```

**Stop if:**

- Disk usage is above 80%
- There are failed services
- CPU load is unusually high
- Memory is nearly exhausted

### Step 2 — Check the service catalog entry

```bash
grep -A 20 "<service-name>" desired-state/server/service-catalog.yaml
```

Confirm the entry includes:

- [ ] Service name and description
- [ ] Status is `approved`
- [ ] Port number(s) the service uses
- [ ] Local domain name (e.g., `biblioteca.local`)
- [ ] Storage requirements
- [ ] Backup hook or notes
- [ ] Service owner or steward

If any of these are missing, fill them in before continuing.

### Step 3 — Check for port conflicts

Make sure the port the service needs is not already in use:

```bash
ssh <user>@<server-ip>
ss -tlnp | grep <port-number>
```

If the port is taken, check what is using it. Do not change port assignments without updating `desired-state/server/service-catalog.yaml` and the reverse proxy config.

### Step 4 — Check the domains file for conflicts

```bash
grep "<local-domain>" desired-state/server/domains.yaml
```

If the domain is already used by another service, you need to choose a different domain or resolve the conflict before proceeding.

---

## Phase 2 — Prepare the Installation

### Step 5 — Find or write the service recipe

Service recipes live in `skills/server-services/scripts/`. Each recipe is a script or compose file that installs and configures one service.

> Note: The `skills/server-services/scripts/` directory does not yet exist in this workspace. Create it when adding the first recipe: `mkdir -p skills/server-services/scripts/<service-name>/`

```bash
ls skills/server-services/scripts/
```

If a recipe exists for this service, review it:

```bash
ls skills/server-services/scripts/<service-name>/
```

If no recipe exists, write one. The recipe must:

- Use the official upstream Docker image or a community-vetted image
- Not require internet after first setup (offline-first)
- Include environment variable configuration (no hardcoded passwords)
- Include a health check
- Include a data volume definition for persistent storage
- Be checked into the repo before it is used

### Step 6 — Prepare the configuration

Create or review the service's configuration:

1. Copy the environment template (if your recipe includes one):

   ```bash
   cp skills/server-services/scripts/<service-name>/env.example .env.<service-name>
   ```

2. Edit the `.env` file with the correct values:

   ```bash
   nano .env.<service-name>
   ```

   Common values to set:
   - Admin username and password (use a strong password)
   - Port number (should match the catalog entry)
   - Data directory path on the server
   - Any service-specific settings

3. **Do not commit `.env` files to the repo.** They contain secrets. Add them to `.gitignore` and store them in the server's `secrets/` directory.

### Step 7 — Write the approval request

Prepare a summary of what you are about to install:

```text
Service: [name]
Description: [what it does]
Port: [port number]
Local domain: [e.g., biblioteca.local]
Disk requirement: [estimated GB]
Approved in catalog: yes
Recipe file: skills/server-services/scripts/[name]/
Config: .env.[service-name] (stored locally, not committed)
Backup hook: [yes/no, location]
Requesting approval from: [maintainer name]
```

Send this to a maintainer with approval rights. **Do not proceed to Phase 3 until you have explicit written approval.**

---

## Phase 3 — Install the Service

### Step 8 — Copy files to the server

```bash
# Copy the recipe and env file to the server
scp -r skills/server-services/scripts/<service-name>/ <user>@<server-ip>:/opt/services/
scp .env.<service-name> <user>@<server-ip>:/opt/services/<service-name>/.env
```

### Step 9 — Start the service

```bash
ssh <user>@<server-ip>
cd /opt/services/<service-name>

# Start using Docker Compose
docker compose up -d

# Check it started
docker ps | grep <service-name>
docker logs <service-name> --tail 20
```

If the service fails to start, check the logs:

```bash
docker logs <service-name> 2>&1 | tail -50
```

Common problems:

- Port already in use → check Step 3
- Permission denied on volume directory → `mkdir -p /opt/data/<service-name> && chown 1000:1000 /opt/data/<service-name>`
- Wrong environment variable → check your `.env` file

---

## Phase 4 — Configure Local Domain Access

### Step 10 — Add the local domain to the reverse proxy

The reverse proxy routes requests from the local domain name to the service's port.

Review the reverse proxy config:

```bash
cat desired-state/server/reverse-proxy.yaml
```

Add an entry for the new service, or ask the operator to generate one:

> "Add a reverse proxy entry for [service-name] on port [port] with local domain [domain]."

A typical Nginx config block looks like:

```nginx
server {
    listen 80;
    server_name biblioteca.local;

    location / {
        proxy_pass http://localhost:<port>;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Apply the new config:

```bash
ssh <user>@<server-ip>
# Place the config in the correct location for your proxy
sudo nginx -t          # test the config
sudo systemctl reload nginx
```

### Step 11 — Add the local DNS entry

Add the local domain to the server's DNS or `/etc/hosts`:

```bash
# On the server itself
echo "127.0.0.1 biblioteca.local" | sudo tee -a /etc/hosts

# On client machines in the LAN, point to the server's IP
echo "<server-lan-ip> biblioteca.local" >> /etc/hosts
```

If you have a local DNS server (like Pi-hole, dnsmasq, or Bind), add the record there instead so all network clients can resolve it automatically.

Update `desired-state/server/domains.yaml` with the new entry:

```yaml
- domain: biblioteca.local
  service: biblioteca
  server_ip: <server-lan-ip>
  port: <port>
  added: <today's date>
```

---

## Phase 5 — Validate

### Step 12 — Test the service directly

```bash
# Test by port (from the server itself)
curl http://localhost:<port>/

# Test by local domain (from the server)
curl http://biblioteca.local/

# Test from a client on the local network
# Open a browser on another device and go to http://biblioteca.local
```

Expected: the service's web interface or API responds correctly.

### Step 13 — Test offline behavior

Disconnect the server from the internet (or simulate it):

```bash
# Temporarily block internet from the server to test offline behavior
sudo ip route del default
# ... test the service ...
# Restore the route
sudo ip route add default via <gateway-ip>
```

Or simply test from a device that has no internet access.

**Offline checklist:**

- [ ] The service is reachable on the local domain without internet
- [ ] The service's core functionality works without internet
- [ ] No errors appear in logs when internet is unavailable

### Step 14 — Run the full server health check

Ask the operator:

> "Run a server health check and confirm [service-name] is running correctly."

The operator's `server-readonly` skill will check:

- Service container is running
- Port is listening
- Local domain resolves
- Health endpoint returns OK
- No recent errors in logs

---

## Phase 6 — Set Up Backup Hook

### Step 15 — Add a backup hook

Every service that stores persistent data must have a backup hook.

Check if the service recipe includes a backup script:

```bash
ls skills/server-services/scripts/<service-name>/backup.sh 2>/dev/null || echo "No backup script yet — write one below"
```

If not, write one. At minimum, the backup should:

1. Stop or pause the service (if safe to do so)
2. Copy the data volume to the backup location
3. Restart the service
4. Log the backup result

```bash
#!/bin/bash
# backup.sh for <service-name>
SERVICE=<service-name>
DATA_DIR=/opt/data/<service-name>
BACKUP_DIR=/opt/backups/<service-name>
DATE=$(date +%Y%m%d-%H%M)

mkdir -p "$BACKUP_DIR"
docker stop "$SERVICE"
tar czf "$BACKUP_DIR/$SERVICE-$DATE.tar.gz" "$DATA_DIR"
docker start "$SERVICE"
echo "Backup complete: $BACKUP_DIR/$SERVICE-$DATE.tar.gz"
```

Schedule it using cron or systemd timer, following the schedule in `desired-state/server/backup-policy.yaml`.

### Step 16 — Test the backup and restore

Run the backup once manually (from your local workspace on the ops host, or directly on the server if you copied the script there):

```bash
bash skills/server-services/scripts/<service-name>/backup.sh
ls /opt/backups/<service-name>/
```

Test that the restore works:

```bash
# Stop the service
docker stop <service-name>

# Restore from the backup you just created
tar xzf /opt/backups/<service-name>/<backup-file> -C /

# Start the service
docker start <service-name>

# Verify it came back correctly
curl http://localhost:<port>/
```

---

## Phase 7 — Finalize Documentation

### Step 17 — Update the service catalog

Update `desired-state/server/service-catalog.yaml` to reflect the installed state:

```yaml
  status: installed
  installed_date: <today's date>
  server: <server-hostname>
  port: <port>
  local_domain: <domain>
  backup_hook: skills/server-services/scripts/<service-name>/backup.sh
  backup_schedule: daily
```

### Step 18 — Write onboarding notes for users

Ask the `knowledge-curator` skill (or write it yourself) to create a short user guide:

- What the service is and what it does for the community
- How to access it: go to `http://biblioteca.local` on the local network
- How to create an account (if needed)
- Who to contact if it is not working

Store this in `docs/onboarding/<service-name>.md`.

> Note: The `docs/onboarding/` directory does not yet exist in this workspace. Create it when writing the first user onboarding document: `mkdir -p docs/onboarding/`.

### Step 19 — Write a maintenance log entry

Log:

- Service installed: name, version, date
- Who approved and who installed
- Port and local domain
- Any issues encountered during installation
- Any deviations from the standard recipe

---

## Post-Install Checklist

- [ ] Service is running: `docker ps | grep <service-name>`
- [ ] Service responds on its port: `curl http://localhost:<port>/`
- [ ] Local domain resolves and works: `curl http://<local-domain>/`
- [ ] Offline test passed
- [ ] Backup hook is set up and tested
- [ ] Service catalog is updated with `status: installed`
- [ ] Reverse proxy config is updated and committed to repo
- [ ] Domains file is updated
- [ ] User onboarding notes written
- [ ] Maintenance log entry written

---

## Uninstalling a Service

If you need to remove a service:

1. Stop the service: `docker stop <service-name>`
2. Take a final backup before removing data
3. Remove the container: `docker rm <service-name>`
4. Remove the reverse proxy config and reload the proxy
5. Remove the DNS/hosts entry
6. Update `desired-state/server/service-catalog.yaml` to `status: removed`
7. Update `desired-state/server/domains.yaml`
8. Write a maintenance log entry explaining why it was removed
9. Keep the backup for at least 30 days

Do not delete data volumes without a final backup. Do not remove a service that other services depend on without checking dependencies first.
