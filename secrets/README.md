# secrets/

## This directory must NEVER contain committed secrets.

This directory is a reference point for how secrets are managed in this workspace. It does not store any actual credentials, keys, or tokens. Every file in this directory that is not this README must be listed in `.gitignore`.

---

## What belongs here (as references, not values)

This directory is for documenting where secrets live and how they are accessed — not for storing the secrets themselves. Examples of what may be documented here:

- Which SSH keys are required and where they are stored on the local host (e.g. `~/.ssh/mesha-router-key`)
- Which environment variables must be set before running the workspace
- Which secret managers or vaults are used
- Which credentials paths are expected by which skills or scripts
- The naming conventions for credential files that are local-only and gitignored

---

## What is never stored here

The following must never appear in any committed file in this directory or anywhere else in this repository:

- SSH private keys (`.pem`, `id_rsa`, `id_ed25519`, or equivalent)
- SSH public keys associated with production access (public keys are lower risk but prefer listing them in docs rather than committing)
- Router admin passwords
- Server root or sudo passwords
- API tokens (cloud providers, Telegram bots, messaging APIs, monitoring services)
- Tailscale auth keys or pre-auth keys
- Database credentials
- Backup encryption keys
- Any token, password, or key that grants access to live infrastructure

---

## How to manage secrets safely

### Option 1: Environment variables (recommended for scripts and automated workflows)

Store secrets as environment variables on the host running the workspace. Reference them by name in scripts and configuration.

Example pattern in a script:
```sh
SSH_KEY_PATH="${MESHA_ROUTER_SSH_KEY:-$HOME/.ssh/mesha-router-key}"
```

Document the required variable names in this README and in `BOOTSTRAP.md`. Do not document the values.

### Option 2: Local-only files (gitignored)

Store credentials in files on the local host that are explicitly listed in `.gitignore`. Use a consistent naming convention so maintainers know where to look.

Recommended local credential paths:
```
~/.config/mesha/
  router-ssh-key          (SSH key for router access)
  server-ssh-key          (SSH key for server access)
  telegram-bot-token      (if using Telegram channel)
  tailscale-auth-key      (for joining the private network)
```

These paths should be documented here, but the files must never be committed.

### Option 3: Secret managers

For production deployments or teams, prefer a secret manager:

- **Local**: [pass](https://www.passwordstore.org/), [gopass](https://www.gopass.pw/), or equivalent GPG-backed store
- **Self-hosted**: Vault (HashiCorp), Infisical, or equivalent
- **Platform**: operating system keychain (macOS Keychain, Linux Secret Service, Windows Credential Manager)

Document which secret manager is in use and how to retrieve each credential in this README.

### Option 4: Separate `.env` file (gitignored)

A `.env` file at the workspace root is acceptable for local development, but must be listed in `.gitignore`. Never commit it.

Template for the `.env` file (document the expected keys here without values):
```
MESHA_ROUTER_SSH_KEY=
MESHA_SERVER_SSH_KEY=
MESHA_TELEGRAM_BOT_TOKEN=
MESHA_TAILSCALE_AUTH_KEY=
MESHA_APPROVAL_CHANNEL_ID=
```

---

## .gitignore requirements

The following patterns must be present in the root `.gitignore` for this workspace:

```
secrets/*.key
secrets/*.pem
secrets/*.token
secrets/*.password
secrets/*.env
secrets/credentials
.env
*.private
```

Review the `.gitignore` before adding any file to this directory.

---

## Responsibility

Every maintainer who clones this repository is responsible for:

1. Not adding secret values to any committed file.
2. Setting up their own local credential files in the documented paths.
3. Verifying that `.gitignore` covers all credential file patterns before running `git add`.
4. Rotating any credential that may have been accidentally committed immediately — assume it is compromised.

If you discover that a secret has been committed to this repository, treat it as compromised immediately, revoke it, generate a new one, and purge it from git history using `git filter-repo` or equivalent. Do not just delete the file in a new commit — the history still contains the value.

---

## Auditing

Periodically run a secret scanner (e.g. `trufflehog`, `gitleaks`, or `git-secrets`) against this repository to catch accidental credential commits before they propagate to remotes.
