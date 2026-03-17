# Telegram Channel Adapter

## What this adapter does

This adapter bridges the Telegram Bot API to the Mesha Community Infrastructure Operator. It receives messages sent to your Telegram bot, normalizes them into the standard channel envelope format, forwards them to the `community-ops-frontdesk` agent via HTTP, and delivers the agent's response back to the sender in Telegram.

```
User → Telegram → adapter.mjs → community-ops-frontdesk → adapter.mjs → Telegram → User
```

The adapter handles:
- Message reception via long-polling (default) or webhook
- Sender identity and trust level assignment
- Message normalization into the standard envelope format
- Delivery of operator responses back to Telegram chats
- Rate-limit and error handling

The adapter has no knowledge of mesh networks, server operations, or operator logic. It only handles the Telegram API layer.

---

## Prerequisites

- Node.js 22 or later
- A Telegram bot token (obtained from [@BotFather](https://t.me/BotFather))
- The Telegram user IDs of your maintainers (see "Finding user IDs" below)
- The Mesha operator endpoint running and reachable (default: `http://localhost:3000`)

---

## Step-by-step setup

### 1. Create a Telegram bot

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts
3. Choose a name (e.g. "Mesha Ops") and a username (e.g. `meshaops_bot`)
4. BotFather will give you a token in the format `123456789:ABCdef...`
5. Copy that token — you will need it for the next step

### 2. Find maintainer Telegram user IDs

User IDs are stable numeric identifiers (not usernames). To find yours:

1. Message [@userinfobot](https://t.me/userinfobot) on Telegram
2. It will reply with your numeric user ID
3. Repeat for each maintainer who needs elevated trust

### 3. Configure the environment

Copy the example environment file:

```bash
cp adapters/channels/telegram/.env.example adapters/channels/telegram/.env
```

Edit `.env` and fill in the required values (see `.env.example` for descriptions).

The `.env` file must never be committed to the repository. It is listed in `.gitignore` by convention.

### 4. Run the adapter

```bash
node adapters/channels/telegram/adapter.mjs
```

On startup the adapter prints its operating mode (polling or webhook), configured trust groups, and the operator endpoint it will forward messages to.

### 5. Verify the adapter is working

```bash
node adapters/channels/telegram/health.mjs
```

This checks that the bot token is valid and the operator endpoint is reachable.

### 6. Register this adapter as a channel in the workspace

Add the Telegram channel to your operator workspace configuration so that `community-ops-frontdesk` knows to expect messages with `"channel": "telegram"`. The adapter identifies itself in every forwarded envelope using that field.

---

## Trust model

The adapter assigns a trust level to every incoming message based on the sender's Telegram user ID.

| Sender | Trust level assigned |
|--------|---------------------|
| User ID in `TELEGRAM_LEAD_MAINTAINER_IDS` | `lead_maintainer` |
| User ID in `TELEGRAM_MAINTAINER_IDS` | `maintainer` |
| Message from a group chat (any) | `public` |
| Any other DM sender | `public` |

**Rules:**
- Group chat messages are always assigned `public` trust regardless of sender, because group membership cannot be verified in real time.
- Trust is determined entirely by numeric user ID. Display names and usernames are not trusted for access control.
- `lead_maintainer` trust grants approval rights for Class C and Class D operations (see `TOOLS.md`).
- `maintainer` trust grants rights for Class A, B, and C operations.
- `public` trust permits Class A read-only queries only.

To configure the maintainer list, set `TELEGRAM_MAINTAINER_IDS` and `TELEGRAM_LEAD_MAINTAINER_IDS` in `.env` as comma-separated lists of numeric Telegram user IDs.

Example:
```
TELEGRAM_MAINTAINER_IDS=123456789,987654321
TELEGRAM_LEAD_MAINTAINER_IDS=123456789
```

---

## How messages flow

```
1. User sends a message to the bot in Telegram.

2. Adapter receives the update via long-polling (getUpdates) or webhook push.

3. Adapter extracts:
   - chat_id (where to send the reply)
   - user_id (for trust level lookup)
   - username / first name (display name)
   - message text
   - message type (text, voice, photo, document)

4. Adapter determines the trust level by checking user_id against
   TELEGRAM_LEAD_MAINTAINER_IDS and TELEGRAM_MAINTAINER_IDS.
   Group chats always receive 'public'.

5. Adapter normalizes the message into the standard channel envelope:
   {
     "channel": "telegram",
     "channel_message_id": "...",
     "sender_id": "...",
     "sender_display_name": "...",
     "trust_level": "public|maintainer|lead_maintainer",
     "chat_id": "...",
     "chat_type": "direct|group",
     "text": "...",
     "media": null,
     "received_at": "2026-03-17T12:00:00.000Z"
   }

6. Adapter POSTs the envelope to OPERATOR_ENDPOINT.

7. Operator processes the request and returns a response JSON:
   { "text": "...", "parse_mode": "plain|markdown" }

8. Adapter sends the response back via Telegram sendMessage.
```

---

## Polling vs. webhook mode

### Long-polling (default)

The adapter calls Telegram's `getUpdates` endpoint repeatedly with a 30-second timeout. This works without any public URL and is the easiest way to get started.

Set `TELEGRAM_WEBHOOK_URL` to empty (or omit it) to use polling mode.

### Webhook mode

If you have a publicly reachable HTTPS URL, set `TELEGRAM_WEBHOOK_URL` to that URL. The adapter will register the webhook with Telegram on startup. Telegram will push updates to your URL instead of the adapter polling.

Webhook mode is more efficient for production deployments. It requires:
- A valid HTTPS URL (self-signed certificates are not accepted by Telegram)
- The adapter to be running and reachable at that URL

---

## Running as a Docker service

A `docker-compose.yaml` is provided for managed deployments.

```bash
cd adapters/channels/telegram
docker compose up -d
```

The service uses the `community-net` Docker network, which should be created externally:

```bash
docker network create community-net
```

---

## Security notes

- **Never commit the bot token.** The `.env` file must be excluded from version control. Anyone with the token can impersonate your bot.
- **Never log the bot token.** The adapter is written to avoid logging the token.
- **Group chats are untrusted by default.** A message in a group — even from a known maintainer — receives `public` trust because group membership is not verified in real time.
- **Trust is based on numeric user ID only.** Display names and usernames can be changed by users and must not be used for access control.
- **Secure your operator endpoint.** The adapter forwards all messages to `OPERATOR_ENDPOINT`. Ensure this endpoint is not publicly accessible without authentication.

---

## Troubleshooting

**Adapter starts but receives no messages:**
- Confirm the bot token is correct by running `node health.mjs`
- Ensure no other process is polling the same bot token (only one polling client allowed per token)
- If using webhook mode, verify the webhook URL is reachable from the internet via HTTPS

**Operator endpoint returns errors:**
- Check that the operator is running at the configured `OPERATOR_ENDPOINT`
- The adapter sends a "having trouble connecting" message to the user when the endpoint is unreachable

**Voice messages:**
- Voice notes receive a "Voice processing is not yet configured" reply. This is intentional — voice transcription requires a separate pipeline.

**Rate limit errors (HTTP 429):**
- The adapter implements exponential backoff when Telegram returns 429. This is handled automatically.
