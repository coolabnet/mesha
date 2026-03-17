# server-services/scripts — Install Recipe Reference

This directory contains reviewed, idempotent install recipes for community services.
Each recipe is a self-contained directory that the `server-services` skill uses to
install and manage a single service.

All installations are **Class C operations** (medium-risk infrastructure change) and
require a written plan and explicit maintainer approval before execution.
See `skills/server-services/SKILL.md` for the full operating model.

---

## Directory structure

```
scripts/
  create-network.sh          # Run once before any service install
  README.md                  # This file
  nextcloud/
    docker-compose.yaml      # Production compose file
    install.sh               # Idempotent install script
    .env.example             # Required environment variables with safe defaults
  jellyfin/
    docker-compose.yaml
    install.sh
    .env.example
  kolibri/
    docker-compose.yaml
    install.sh
    .env.example
```

---

## Shared Docker network

All services share a single Docker bridge network called **`community-net`**.
This allows:

- the reverse proxy (Caddy) to reach service containers by name
- service containers to communicate with each other when needed
- clean isolation from the host network

**Before installing any service**, run the network setup script once:

```bash
bash skills/server-services/scripts/create-network.sh
```

This script is idempotent — running it again when the network already exists does nothing.

---

## Order of operations for a new service install

1. **Create the shared network** (once per server, not per service):
   ```bash
   bash skills/server-services/scripts/create-network.sh
   ```

2. **Copy and fill in the `.env` file** for the service:
   ```bash
   cd skills/server-services/scripts/<service-name>/
   cp .env.example .env
   # Edit .env with real credentials — never commit this file
   ```

3. **Run the install script**:
   ```bash
   bash skills/server-services/scripts/<service-name>/install.sh
   ```

4. **Configure the reverse proxy** by updating `desired-state/server/reverse-proxy.yaml`
   and applying the new Caddyfile entry to the running Caddy instance.
   Each recipe's install output prints the required reverse proxy configuration.

5. **Verify the service** is reachable via its local domain (e.g. `http://nuvem.bairro.local`).

6. **Update the service inventory** at `inventories/local-services.yaml` with the
   service status, URL, and steward name.

7. **Confirm backup hooks** are active for services with `backup_required: true` in
   `desired-state/server/service-catalog.yaml`.

---

## Installed services

| Service    | Local domain                    | Port | Backup required |
|------------|----------------------------------|------|-----------------|
| Nextcloud  | nuvem.bairro.local               | 80   | Yes             |
| Jellyfin   | midia.bairro.local               | 8096 | No              |
| Kolibri    | aprendizado.bairro.local         | 8080 | Yes             |

For all approved services, see `desired-state/server/service-catalog.yaml`.
For all domain assignments, see `desired-state/server/domains.yaml`.
For reverse proxy rules, see `desired-state/server/reverse-proxy.yaml`.

---

## Backup requirement

Every recipe that stores persistent user data **must** have a corresponding backup job in
`desired-state/server/backup-policy.yaml` before the install is considered complete.

Current backup jobs:
- `nextcloud-data` — daily rsync of Nextcloud user files
- `nextcloud-db` — daily MariaDB dump (encrypted)
- `kolibri-data` — weekly tar of student progress data

Jellyfin has no backup job by design: media content is replaceable and no personal data
is stored by default. If personal or user-generated content is added, a backup job must
be created and `backup_required` set to `true` in the service catalog.

---

## Adding a new recipe

To add a recipe for a new service:

1. Ensure the service is listed as `approved: true` in `desired-state/server/service-catalog.yaml`.
   If it is not approved, do not create a recipe — add it to the catalog first and get
   community approval.

2. Create a new directory under `scripts/`:
   ```
   scripts/<service-name>/
     docker-compose.yaml
     install.sh
     .env.example
   ```

3. Follow the conventions in existing recipes:
   - `docker-compose.yaml`: versionless compose format, `community-net` external network,
     `restart: unless-stopped`, all secrets via environment variables, named volumes for
     persistence.
   - `install.sh`: `#!/usr/bin/env bash`, `set -euo pipefail`, idempotent steps,
     prerequisites check, `.env` validation, directory creation, pull + start,
     health check loop, access URL output, onboarding note.
   - `.env.example`: all required variables with safe placeholder defaults, clear comments.

4. Add the service's local domain to `desired-state/server/domains.yaml`.

5. Add the reverse proxy route to `desired-state/server/reverse-proxy.yaml`.

6. If the service stores persistent data, add a backup job to
   `desired-state/server/backup-policy.yaml`.

7. Update this README's service table above.

---

## Security notes

- `.env` files contain real credentials — **never commit them to git**.
  The `.gitignore` at the repo root should exclude `*.env` and `.env`.
- Refer to `secrets/README.md` for the approved way to handle credentials.
- All install scripts validate that placeholder passwords (`change-me-*`) are replaced
  before proceeding.
- No service is exposed directly on a public port — all access routes through the
  reverse proxy on `community-net`.
