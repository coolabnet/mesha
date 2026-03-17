/**
 * adapters/channels/telegram/adapter.mjs
 *
 * Telegram channel adapter for the Mesha Community Infrastructure Operator.
 *
 * Bridges the Telegram Bot API to the community-ops-frontdesk agent.
 * Uses only Node.js built-in modules — no npm dependencies.
 *
 * Modes:
 *   - Long-polling (default): calls getUpdates with timeout=30
 *   - Webhook: registers a webhook URL and listens for POST requests
 *
 * Usage: node adapters/channels/telegram/adapter.mjs
 */

import https from 'https';
import http from 'http';
import { URL } from 'url';

// ── Configuration ──────────────────────────────────────────────────────────────

const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || '';
const MAINTAINER_IDS = parseIdList(process.env.TELEGRAM_MAINTAINER_IDS || '');
const LEAD_MAINTAINER_IDS = parseIdList(process.env.TELEGRAM_LEAD_MAINTAINER_IDS || '');
const WEBHOOK_URL = (process.env.TELEGRAM_WEBHOOK_URL || '').trim();
const POLL_INTERVAL_MS = Math.max(
  500,
  parseInt(process.env.TELEGRAM_POLL_INTERVAL_MS || '1000', 10) || 1000
);
const OPERATOR_ENDPOINT = (process.env.OPERATOR_ENDPOINT || 'http://localhost:3000').trim();

// Telegram long-poll timeout in seconds (must be < 60 to stay within Bot API limits)
const TELEGRAM_POLL_TIMEOUT_SECONDS = 30;

// Retry delay for operator delivery failures
const OPERATOR_RETRY_DELAY_MS = 4000;

// Maximum exponential backoff delay for Telegram rate limits (ms)
const MAX_BACKOFF_MS = 60_000;

// ── State ──────────────────────────────────────────────────────────────────────

let offset = 0;
let running = true;
let stats = { processed: 0, errors: 0, started: new Date().toISOString() };

// ── Helpers ────────────────────────────────────────────────────────────────────

function parseIdList(raw) {
  if (!raw || !raw.trim()) return new Set();
  return new Set(
    raw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
  );
}

function determineTrustLevel(userId, chatType) {
  // Group chats are always public regardless of sender identity
  if (chatType === 'group' || chatType === 'supergroup' || chatType === 'channel') {
    return 'public';
  }
  const id = String(userId);
  if (LEAD_MAINTAINER_IDS.has(id)) return 'lead_maintainer';
  if (MAINTAINER_IDS.has(id)) return 'maintainer';
  return 'public';
}

function determineChatType(chat) {
  if (!chat) return 'direct';
  const t = chat.type;
  if (t === 'private') return 'direct';
  if (t === 'group' || t === 'supergroup') return 'group';
  if (t === 'channel') return 'group';
  return 'direct';
}

function determineMessageType(msg) {
  if (msg.voice) return 'voice';
  if (msg.audio) return 'voice';
  if (msg.photo) return 'photo';
  if (msg.document) return 'document';
  if (msg.video) return 'document';
  if (msg.text) return 'text';
  return 'text';
}

function getSenderName(from) {
  if (!from) return 'unknown';
  const parts = [from.first_name, from.last_name].filter(Boolean);
  const fullName = parts.join(' ').trim();
  return from.username ? `@${from.username}` : fullName || String(from.id);
}

function log(level, message, extra) {
  const ts = new Date().toISOString();
  const line = `[${ts}] [${level}] ${message}`;
  const out = level === 'ERROR' ? console.error : console.log;
  if (extra !== undefined) {
    out(line, typeof extra === 'object' ? JSON.stringify(extra) : extra);
  } else {
    out(line);
  }
}

// Mask the bot token in any string to prevent accidental logging
function maskToken(str) {
  if (!BOT_TOKEN) return str;
  return str.split(BOT_TOKEN).join('[TOKEN]');
}

// ── HTTP helpers (no external deps) ───────────────────────────────────────────

/**
 * Make an HTTPS GET or POST request.
 * Returns a Promise that resolves to { statusCode, body (parsed JSON or string) }.
 */
function makeRequest(urlStr, options = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(urlStr);
    const isHttps = parsed.protocol === 'https:';
    const lib = isHttps ? https : http;

    const reqOptions = {
      hostname: parsed.hostname,
      port: parsed.port || (isHttps ? 443 : 80),
      path: parsed.pathname + (parsed.search || ''),
      method: options.method || 'GET',
      headers: options.headers || {},
      timeout: options.timeoutMs || 45_000,
    };

    const req = lib.request(reqOptions, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        let body;
        try {
          body = JSON.parse(data);
        } catch {
          body = data;
        }
        resolve({ statusCode: res.statusCode, body });
      });
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error(`Request timed out: ${maskToken(urlStr)}`));
    });

    req.on('error', (err) => {
      reject(new Error(`Request error for ${maskToken(urlStr)}: ${err.message}`));
    });

    if (options.body) {
      req.write(options.body);
    }
    req.end();
  });
}

/**
 * POST JSON data to a URL.
 */
function postJson(urlStr, data, timeoutMs) {
  const body = JSON.stringify(data);
  return makeRequest(urlStr, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
    },
    body,
    timeoutMs: timeoutMs || 15_000,
  });
}

// ── Telegram API calls ────────────────────────────────────────────────────────

function telegramUrl(method) {
  return `https://api.telegram.org/bot${BOT_TOKEN}/${method}`;
}

/**
 * Call a Telegram Bot API method.
 * Handles 429 rate-limit responses with exponential backoff.
 */
async function callTelegram(method, data, attempt = 0) {
  const url = telegramUrl(method);
  let result;
  try {
    result = await postJson(url, data, method === 'getUpdates' ? 40_000 : 15_000);
  } catch (err) {
    log('WARN', `Telegram ${method} network error (attempt ${attempt}): ${err.message}`);
    return null;
  }

  if (result.statusCode === 429) {
    const retryAfter = result.body?.parameters?.retry_after || Math.pow(2, attempt + 1);
    const delay = Math.min(retryAfter * 1000, MAX_BACKOFF_MS);
    log('WARN', `Telegram rate limited on ${method}. Backing off ${delay}ms.`);
    await sleep(delay);
    return callTelegram(method, data, attempt + 1);
  }

  if (result.statusCode !== 200 || !result.body?.ok) {
    const desc = result.body?.description || `HTTP ${result.statusCode}`;
    log('WARN', `Telegram ${method} failed: ${desc}`);
    return null;
  }

  return result.body.result;
}

async function sendMessage(chatId, text, parseMode) {
  const payload = {
    chat_id: chatId,
    text,
  };
  if (parseMode && parseMode !== 'plain') {
    payload.parse_mode = parseMode === 'markdown' ? 'Markdown' : parseMode;
  }
  return callTelegram('sendMessage', payload);
}

async function getUpdates(timeoutSeconds) {
  return callTelegram('getUpdates', {
    offset,
    timeout: timeoutSeconds,
    allowed_updates: ['message'],
  });
}

async function setWebhook(webhookUrl) {
  return callTelegram('setWebhook', { url: webhookUrl });
}

async function deleteWebhook() {
  return callTelegram('deleteWebhook', { drop_pending_updates: false });
}

async function getMe() {
  return callTelegram('getMe', {});
}

// ── Operator communication ─────────────────────────────────────────────────────

/**
 * Forward a normalized message envelope to the community-ops-frontdesk endpoint.
 * Returns the operator's response object, or null on failure.
 */
async function forwardToOperator(envelope) {
  let result;
  try {
    result = await postJson(OPERATOR_ENDPOINT, envelope, 30_000);
  } catch (err) {
    log('ERROR', `Operator endpoint unreachable (attempt 1): ${err.message}`);
    // Retry once after delay
    await sleep(OPERATOR_RETRY_DELAY_MS);
    try {
      result = await postJson(OPERATOR_ENDPOINT, envelope, 30_000);
    } catch (retryErr) {
      log('ERROR', `Operator endpoint unreachable (attempt 2): ${retryErr.message}`);
      return null;
    }
  }

  if (result.statusCode < 200 || result.statusCode >= 300) {
    log('ERROR', `Operator returned HTTP ${result.statusCode}`);
    return null;
  }

  return result.body;
}

// ── Message normalization ──────────────────────────────────────────────────────

/**
 * Build the standard channel envelope from a Telegram message object.
 */
function normalizeMessage(msg) {
  const from = msg.from || {};
  const chat = msg.chat || {};
  const userId = from.id;
  const chatType = chat.type;
  const canonicalChatType = determineChatType(chat);
  const trustLevel = determineTrustLevel(userId, chatType);
  const messageType = determineMessageType(msg);
  const text = msg.text || msg.caption || '';

  return {
    channel: 'telegram',
    channel_message_id: String(msg.message_id),
    sender_id: String(userId || ''),
    sender_display_name: getSenderName(from),
    trust_level: trustLevel,
    chat_id: String(chat.id),
    chat_type: canonicalChatType,
    text,
    media: null,
    message_type: messageType,
    received_at: new Date(msg.date * 1000).toISOString(),
  };
}

// ── Message handling ───────────────────────────────────────────────────────────

/**
 * Process a single incoming Telegram message update.
 */
async function handleMessage(msg) {
  if (!msg) return;

  const chatId = String((msg.chat || {}).id || '');
  if (!chatId) return;

  const envelope = normalizeMessage(msg);

  // Voice notes: inform the user, do not forward
  if (envelope.message_type === 'voice') {
    log('INFO', `Voice note from ${envelope.sender_id} in chat ${chatId}`);
    await sendMessage(
      chatId,
      'I received a voice note. Voice processing is not yet configured.'
    );
    stats.processed++;
    return;
  }

  // Empty messages (e.g. photo-only with no caption)
  if (!envelope.text && envelope.message_type !== 'text') {
    log('INFO', `Non-text message type=${envelope.message_type} from ${envelope.sender_id}`);
    await sendMessage(
      chatId,
      `I received a ${envelope.message_type} message. Please send text to interact with the operator.`
    );
    stats.processed++;
    return;
  }

  if (!envelope.text) {
    return;
  }

  log(
    'INFO',
    `Message from ${envelope.sender_display_name} (${envelope.sender_id}) ` +
      `trust=${envelope.trust_level} chat=${chatId} type=${envelope.chat_type}: ` +
      `"${envelope.text.slice(0, 80)}${envelope.text.length > 80 ? '…' : ''}"`
  );

  const response = await forwardToOperator(envelope);

  if (!response) {
    stats.errors++;
    await sendMessage(
      chatId,
      "I'm having trouble connecting to the operator right now. Please try again in a moment, or contact a maintainer directly."
    );
    return;
  }

  const replyText =
    typeof response === 'string'
      ? response
      : response.text || response.message || JSON.stringify(response);
  const parseMode = response.parse_mode || 'plain';

  await sendMessage(chatId, replyText, parseMode);
  stats.processed++;
}

// ── Long-polling loop ──────────────────────────────────────────────────────────

async function pollLoop() {
  log('INFO', 'Starting long-polling loop...');

  while (running) {
    let updates;
    try {
      updates = await getUpdates(TELEGRAM_POLL_TIMEOUT_SECONDS);
    } catch (err) {
      log('WARN', `getUpdates error: ${err.message}`);
      stats.errors++;
      await sleep(POLL_INTERVAL_MS * 2);
      continue;
    }

    if (!updates || !Array.isArray(updates)) {
      // Network error or empty response — wait before retrying
      await sleep(POLL_INTERVAL_MS);
      continue;
    }

    for (const update of updates) {
      if (!running) break;

      // Advance offset to acknowledge this update
      offset = Math.max(offset, update.update_id + 1);

      if (update.message) {
        try {
          await handleMessage(update.message);
        } catch (err) {
          log('ERROR', `Unhandled error processing update ${update.update_id}: ${err.message}`);
          stats.errors++;
        }
      }
    }

    // Brief pause between poll cycles to avoid hammering the API unnecessarily
    if (updates.length === 0) {
      await sleep(POLL_INTERVAL_MS);
    }
  }
}

// ── Webhook server ─────────────────────────────────────────────────────────────

function startWebhookServer(port) {
  const server = http.createServer(async (req, res) => {
    if (req.method !== 'POST') {
      res.writeHead(405);
      res.end('Method Not Allowed');
      return;
    }

    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', async () => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('{"ok":true}');

      let update;
      try {
        update = JSON.parse(body);
      } catch {
        log('WARN', 'Received non-JSON webhook payload');
        return;
      }

      if (update.message) {
        try {
          await handleMessage(update.message);
        } catch (err) {
          log('ERROR', `Unhandled error in webhook handler: ${err.message}`);
          stats.errors++;
        }
      }
    });

    req.on('error', (err) => {
      log('WARN', `Webhook request error: ${err.message}`);
    });
  });

  server.listen(port, () => {
    log('INFO', `Webhook HTTP server listening on port ${port}`);
  });

  server.on('error', (err) => {
    log('ERROR', `Webhook server error: ${err.message}`);
  });

  return server;
}

// ── Utilities ──────────────────────────────────────────────────────────────────

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function printStats() {
  const uptime = Math.round((Date.now() - new Date(stats.started).getTime()) / 1000);
  log('INFO', '─── Shutdown stats ───────────────────────────────────');
  log('INFO', `  Started:           ${stats.started}`);
  log('INFO', `  Uptime:            ${uptime}s`);
  log('INFO', `  Messages processed: ${stats.processed}`);
  log('INFO', `  Errors:            ${stats.errors}`);
  log('INFO', '──────────────────────────────────────────────────────');
}

// ── Startup validation ─────────────────────────────────────────────────────────

function validateConfig() {
  const errors = [];
  if (!BOT_TOKEN) {
    errors.push('TELEGRAM_BOT_TOKEN is not set');
  }
  if (!OPERATOR_ENDPOINT) {
    errors.push('OPERATOR_ENDPOINT is not set');
  }
  return errors;
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  log('INFO', '══════════════════════════════════════════════════════');
  log('INFO', '  Mesha Telegram Channel Adapter');
  log('INFO', '══════════════════════════════════════════════════════');

  const configErrors = validateConfig();
  if (configErrors.length > 0) {
    for (const err of configErrors) {
      log('ERROR', `Configuration error: ${err}`);
    }
    process.exit(1);
  }

  const mode = WEBHOOK_URL ? 'webhook' : 'polling';
  log('INFO', `Mode:                ${mode}`);
  log('INFO', `Operator endpoint:   ${OPERATOR_ENDPOINT}`);
  log(
    'INFO',
    `Maintainer IDs:      ${MAINTAINER_IDS.size > 0 ? `${MAINTAINER_IDS.size} configured` : 'none configured (no maintainer-level trust)'}`
  );
  log(
    'INFO',
    `Lead maintainer IDs: ${LEAD_MAINTAINER_IDS.size > 0 ? `${LEAD_MAINTAINER_IDS.size} configured` : 'none configured (no lead_maintainer-level trust)'}`
  );

  // Verify the bot token is valid
  const botInfo = await getMe();
  if (!botInfo) {
    log('ERROR', 'Failed to authenticate with Telegram. Check TELEGRAM_BOT_TOKEN.');
    process.exit(1);
  }
  log('INFO', `Bot identity:        @${botInfo.username} (id: ${botInfo.id})`);

  // Graceful shutdown
  const shutdown = () => {
    if (!running) return;
    running = false;
    log('INFO', 'Shutting down...');
    printStats();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  if (mode === 'webhook') {
    // Register the webhook URL with Telegram
    const webhookResult = await setWebhook(WEBHOOK_URL);
    if (webhookResult === null) {
      log('ERROR', `Failed to register webhook at ${WEBHOOK_URL}. Check the URL and try again.`);
      process.exit(1);
    }
    log('INFO', `Webhook registered: ${WEBHOOK_URL}`);

    // Start the local HTTP server to receive webhook pushes
    const webhookPort = parseInt(process.env.WEBHOOK_PORT || '8080', 10);
    startWebhookServer(webhookPort);

    // Keep the process alive
    await new Promise(() => {});
  } else {
    // Remove any existing webhook so polling works correctly
    await deleteWebhook();
    log('INFO', `Poll interval:       ${POLL_INTERVAL_MS}ms`);
    log('INFO', '──────────────────────────────────────────────────────');
    await pollLoop();
  }
}

main().catch((err) => {
  log('ERROR', `Fatal error: ${err.message}`);
  if (err.stack) log('ERROR', err.stack);
  process.exit(1);
});
