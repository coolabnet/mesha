# Mesha Configuration And Secrets

This is the shortest reference for what a maintainer actually needs to set before Mesha is useful on a real deployment.

The current repo already documents most of this, but the details were previously spread across `secrets/README.md`, `docs/deployment.md`, adapter docs, and inventory comments. This file centralizes the required surface.

## Required Today For Real Mesh Reads

| Item | Where it is set | Why it matters |
| --- | --- | --- |
| Real mesh node targets | `inventories/mesh-nodes.yaml` | `mesh-readonly` uses each node `hostname` as the actual SSH target. Use a resolvable hostname or management IP. |
| Real gateway target | `inventories/gateways.yaml` | Topology collection uses the gateway hostname from this file. |
| Real site context | `inventories/sites.yaml` | Human-readable site names, contacts, and notes live here. |
| SSH access from the ops host | Host SSH config, agent, or local private key | The live mesh scripts call `ssh root@<hostname>` and assume the host running Mesha can already authenticate. |
| At least one authorized maintainer source | `desired-state/server/hosts.yaml` `maintainers:` or local-only `secrets/maintainers.yaml` | The approval model needs a real maintainer identity source for trusted operations. |

Important: Mesha does not currently require a repo-local secret file for router reads. The practical requirement today is simpler: `ssh root@<inventory-target>` must work from the machine running the workspace.

## Required Today For `thisnode.info` Bootstrap

These are only needed if you want the easier LibreMesh-first bootstrap flow:

| Item | Where it is set | Why it matters |
| --- | --- | --- |
| Connected to a LibreMesh LAN or Wi-Fi | Host network | `scripts/discover-from-thisnode.sh` is bounded to `thisnode.info`. |
| Root SSH access to the currently connected node | Host SSH config, agent, or local private key | Discovery runs read-only SSH commands against `root@thisnode.info`. |

## Required Today For Telegram

Telegram is optional. If you do use it, these are the actual required values:

| Item | Where it is set | Why it matters |
| --- | --- | --- |
| `TELEGRAM_BOT_TOKEN` | `adapters/channels/telegram/.env` | Authenticates the bot with Telegram. |
| `TELEGRAM_MAINTAINER_IDS` | `adapters/channels/telegram/.env` | Marks which Telegram users are trusted maintainers. |
| `TELEGRAM_LEAD_MAINTAINER_IDS` | `adapters/channels/telegram/.env` | Marks which Telegram users can approve higher-risk actions. |
| `OPERATOR_ENDPOINT` | `adapters/channels/telegram/.env` | Where the adapter forwards normalized message envelopes. |

Optional Telegram settings:

| Item | Where it is set | When you need it |
| --- | --- | --- |
| `TELEGRAM_WEBHOOK_URL` | `adapters/channels/telegram/.env` | Needed only for webhook mode. |
| `WEBHOOK_PORT` | `adapters/channels/telegram/.env` | Needed only for webhook mode. |
| `TELEGRAM_POLL_INTERVAL_MS` | `adapters/channels/telegram/.env` | Useful when tuning long-polling behavior. |

## Optional But Expected Later

These are not required for the first mesh-status success path, but they become relevant as you expand real operations:

| Item | Typical location | Used for |
| --- | --- | --- |
| Router SSH key path variable such as `MESHA_ROUTER_SSH_KEY` | Local shell env or host secret manager | Future script standardization and explicit key selection. |
| Server SSH key path variable such as `MESHA_SERVER_SSH_KEY` | Local shell env or host secret manager | Server-side read and write operations. |
| Tailscale auth key | Local secret manager or env | Joining the private management network when used. |
| Service-specific `.env` files | `secrets/` or service-specific local-only files | Nextcloud, Grafana, Kolibri, and similar services. |

## Recommended Local Secret Layout

The repo-level guidance in [secrets/README.md](../secrets/README.md) is still correct. A practical local layout is:

```text
~/.config/mesha/
  router-ssh-key
  server-ssh-key
  telegram-bot-token
  tailscale-auth-key
```

Or use environment variables instead of files if your host already has a secret manager.

## Approval Identity Source

The trust model in [AGENTS.md](../AGENTS.md) expects one of these to exist:

1. Committed desired-state maintainers in [desired-state/server/hosts.yaml](../desired-state/server/hosts.yaml)
2. A local-only `secrets/maintainers.yaml` file that is not committed

If you do not want to commit maintainer identities, use the local-only file. If you do want them in repo, keep them in `desired-state/server/hosts.yaml` and review them like any other desired-state change.

Suggested local-only format:

```yaml
maintainers:
  - name: "REQUIRED"
    role: lead_maintainer
    channels:
      telegram_user_id: 123456789
      telegram_username: "replace_me"
```

## What Is Well Documented Now

- Secret handling rules: [secrets/README.md](../secrets/README.md)
- First live deployment path: [docs/deployment.md](./deployment.md)
- Telegram-specific environment variables: [adapters/channels/telegram/.env.example](../adapters/channels/telegram/.env.example)
- Real mesh bootstrap flow: [README.md](../README.md) and [RUN.md](../RUN.md)

## Remaining Reality Check

What is now well documented:
- the inventory files you must seed
- the Telegram env surface
- the approval identity source
- the difference between curated inventory and machine-generated snapshots

What is still operator-host dependent:
- your actual SSH agent, SSH config, and private key material
- whether `thisnode.info` resolves from the current network
- whether `ssh root@<inventory-target>` works from your laptop or ops host

That host-specific part cannot be fully committed into this repo, and should stay outside version control.
