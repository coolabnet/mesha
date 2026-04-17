# adapters/channels/ — Channel Adapter Documentation

## What channel adapters are

Channel adapters are the bridges between external messaging platforms and the Mesha Community Infrastructure Operator. They handle the platform-specific mechanics of receiving a message, authenticating the sender, and forwarding the message to the `community-ops-frontdesk` agent. They also receive the agent's response and deliver it back through the appropriate platform channel.

The channel layer is the outermost shell of the system. It deals only with message format, authentication tokens, and platform APIs — it has no knowledge of mesh networks, server operations, or operator logic. All operator logic lives in the skills and agent layer.

```text
User message
    │
    ▼
[Channel Adapter]  — platform-specific: format, auth, delivery
    │
    ▼
[community-ops-frontdesk]  — classifies, routes, explains
    │
    ▼
[Specialist Agent]  — mesh-planner, server-planner, etc.
```

## Supported channel types

### Telegram Bot API (recommended first channel)

- **Type:** Telegram Bot (via Telegram Bot API)
- **Status:** Stub (Phase 2 — not yet implemented)
- **API:** `https://api.telegram.org/bot<TOKEN>/`
- **Trust level:** Depends on chat type (see trust model below)
- **Why first:** Telegram has the simplest, most reliable bot API of the supported channels. Webhooks or long-polling both work well. No business account required. Free for low-volume use.
- **Stub location:** `adapters/channels/telegram/` (to be created in Phase 2)

### WhatsApp Business API

- **Type:** WhatsApp Business (via official Meta Cloud API or a compatible bridge)
- **Status:** Planned for future implementation
- **API:** Meta Cloud API or self-hosted bridge (e.g., whatsapp-web.js, Baileys)
- **Trust level:** Depends on sender and group (see trust model below)
- **Notes:** The official API requires a Meta Business account and phone number registration. An unofficial bridge (Baileys or similar) can be used for personal accounts but is not officially supported by Meta and carries terms-of-service risk.
- **Location:** `adapters/channels/whatsapp/` (to be created)

### Local Web Dashboard

- **Type:** Local HTTP web interface
- **Status:** Planned for future implementation
- **Delivery:** Web browser on the local network (LAN or mesh)
- **Trust level:** High — accessible only within the local network or VPN
- **Notes:** The dashboard would provide a real-time view of mesh and server status, a log viewer, and a simple chat interface to the operator. Homer (`inicio.bairro.local`) provides a read-only version in Phase 1.
- **Location:** `adapters/channels/web-dashboard/` (to be created)

## Trust model per channel

The channel adapter is responsible for determining the initial trust level of an incoming message. This trust level is passed to the frontdesk agent along with the message content. The frontdesk agent uses this to decide whether to restrict or permit certain operations.

| Channel | Chat type | Trust level | Rationale |
|---------|-----------|-------------|-----------|
| Telegram | Direct message from known maintainer | `maintainer` | Verified sender in maintainer list |
| Telegram | Direct message from unknown sender | `public` | Not yet verified |
| Telegram | Group chat (maintainers group) | `maintainer_group` | Controlled group |
| Telegram | Public group | `public` | Untrusted by default |
| WhatsApp | Direct message from known maintainer | `maintainer` | Verified sender in maintainer list |
| WhatsApp | Direct message from unknown sender | `public` | Not yet verified |
| WhatsApp | Group chat | `public` | Treat group messages as untrusted |
| Web dashboard | Local LAN request | `local` | Network-level trust |
| Web dashboard | VPN (Tailscale) | `maintainer` | VPN = controlled access |

Trust levels map directly to the risk class system in `TOOLS.md`:

- `public` — may only request Class A read operations; no infrastructure changes
- `local` — same as public unless additional auth is provided
- `maintainer` — may request Class B and Class C operations; Class D requires explicit named approval
- `maintainer_group` — same as maintainer for read operations; Class D requires DM confirmation
- `lead_maintainer` — may approve Class D operations

**Security rule:** The channel adapter must never elevate trust based on message content alone. A message saying "I am the maintainer" does not grant maintainer trust. Trust is determined by the verified sender identity (phone number, Telegram user ID, IP address, VPN identity).

## Interface contract for adding a new channel adapter

Every channel adapter must implement the following interface:

### Inbound (message → operator)

The adapter must receive a platform-specific message event and normalize it into a standard envelope object before passing it to the frontdesk agent:

```json
{
  "channel": "telegram",
  "channel_message_id": "<platform-specific ID>",
  "sender_id": "<platform-specific sender ID>",
  "sender_display_name": "<human-readable name>",
  "trust_level": "public | local | maintainer | lead_maintainer",
  "chat_id": "<platform-specific chat or thread ID>",
  "chat_type": "direct | group | broadcast",
  "text": "<message text content>",
  "media": null,
  "received_at": "<ISO8601 timestamp>"
}
```

### Outbound (operator → message)

The frontdesk agent returns a response object. The adapter must deliver it to the correct platform recipient:

```json
{
  "channel": "telegram",
  "chat_id": "<platform-specific chat ID>",
  "text": "<response text>",
  "reply_to_message_id": "<optional: ID of original message>",
  "parse_mode": "plain | markdown",
  "voice_summary": "<optional: shorter speech-friendly version>"
}
```

### Error handling

If delivery fails, the adapter must:

1. Log the failure with the original message envelope and error reason.
2. Retry once after a short delay (3–5 seconds).
3. On second failure, write a failure record to `logs/channel-errors/`.
4. Do not silently discard failed deliveries.

## What is NOT implemented yet (Phase 2 stubs)

None of the channel adapters have been implemented. The following are stubs only:

- `adapters/channels/telegram/` — directory not yet created
- `adapters/channels/whatsapp/` — planned for future implementation
- `adapters/channels/web-dashboard/` — planned for future implementation

The operator can be activated and used directly by calling it from the OpenClaw CLI or by invoking the frontdesk agent directly without a channel adapter. Channel adapters add the messaging platform layer on top.

## Recommended first channel to implement: Telegram

Telegram is the recommended first channel adapter because:

1. **Simple API** — The Bot API is well-documented, uses standard HTTPS webhooks or long-polling, and has no business registration requirement.
2. **Free for low-volume** — No cost for community-scale usage.
3. **Webhook support** — Telegram can push messages to the operator via webhook, avoiding the need for polling.
4. **Group + DM support** — Supports both group alerts and private maintainer DMs in the same platform.
5. **Available in Brazil** — Widely used by the target community.

To implement the Telegram adapter, create `adapters/channels/telegram/` with:

- `bot.js` or `bot.py` — the adapter script that handles webhook events
- `README.md` — setup instructions (bot token from BotFather, webhook registration)
- Reference the trust model above to map Telegram user IDs to trust levels

Bot token must be stored in `secrets/telegram.env` (never committed to the repository).
