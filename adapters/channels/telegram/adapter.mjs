/**
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Mesha Community Infrastructure Project
 * Licensed under the MIT License; see LICENSE file for details.
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

// ── Helpers (stateless utilities) ──────────────────────────────────────────────

function parseIdList(raw) {
  if (!raw || !raw.trim()) return new Set();
  return new Set(
    raw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
  );
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ── TelegramAdapter class ──────────────────────────────────────────────────────

class TelegramAdapter {
  constructor() {
    // Configuration
    this.botToken = process.env.TELEGRAM_BOT_TOKEN || '';
    this.maintainerIds = parseIdList(process.env.TELEGRAM_MAINTAINER_IDS || '');
    this.leadMaintainerIds = parseIdList(process.env.TELEGRAM_LEAD_MAINTAINER_IDS || '');
    this.webhookUrl = (process.env.TELEGRAM_WEBHOOK_URL || '').trim();
    this.pollIntervalMs = Math.max(
      500,
      parseInt(process.env.TELEGRAM_POLL_INTERVAL_MS || '1000', 10) || 1000
    );
    this.operatorEndpoint = (process.env.OPERATOR_ENDPOINT || 'http://localhost:3000').trim();
    this.webhookSecret = (process.env.TELEGRAM_WEBHOOK_SECRET || '').trim();

    // Telegram long-poll timeout in seconds (must be < 60 to stay within Bot API limits)
    this.pollTimeoutSeconds = 30;

    // Retry delay for operator delivery failures
    this.operatorRetryDelayMs = 4000;

    // Maximum exponential backoff delay for Telegram rate limits (ms)
    this.maxBackoffMs = 60_000;

    // State
    this.offset = 0;
    this.running = true;
    this.stats = { processed: 0, errors: 0, started: new Date().toISOString() };
  }

  // ── Logging ──────────────────────────────────────────────────────────────────

  log(level, message, extra) {
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
  maskToken(str) {
    if (!this.botToken) return str;
    return str.split(this.botToken).join('[TOKEN]');
  }

  // ── Trust & type helpers ─────────────────────────────────────────────────────

  determineTrustLevel(userId, chatType) {
    // Group chats are always public regardless of sender identity
    if (chatType === 'group' || chatType === 'supergroup' || chatType === 'channel') {
      return 'public';
    }
    const id = String(userId);
    if (this.leadMaintainerIds.has(id)) return 'lead_maintainer';
    if (this.maintainerIds.has(id)) return 'maintainer';
    return 'public';
  }

  determineChatType(chat) {
    if (!chat) return 'direct';
    const t = chat.type;
    if (t === 'private') return 'direct';
    if (t === 'group' || t === 'supergroup') return 'group';
    if (t === 'channel') return 'group';
    return 'direct';
  }

  determineMessageType(msg) {
    if (msg.voice) return 'voice';
    if (msg.audio) return 'voice';
    if (msg.photo) return 'photo';
    if (msg.document) return 'document';
    if (msg.video) return 'document';
    if (msg.text) return 'text';
    return 'text';
  }

  getSenderName(from) {
    if (!from) return 'unknown';
    const parts = [from.first_name, from.last_name].filter(Boolean);
    const fullName = parts.join(' ').trim();
    return from.username ? `@${from.username}` : fullName || String(from.id);
  }

  // ── HTTP helpers (no external deps) ─────────────────────────────────────────

  /**
   * Make an HTTPS GET or POST request.
   * Returns a Promise that resolves to { statusCode, body (parsed JSON or string) }.
   */
  makeRequest(urlStr, options = {}) {
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
        reject(new Error(`Request timed out: ${this.maskToken(urlStr)}`));
      });

      req.on('error', (err) => {
        reject(new Error(`Request error for ${this.maskToken(urlStr)}: ${err.message}`));
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
  postJson(urlStr, data, timeoutMs) {
    const body = JSON.stringify(data);
    return this.makeRequest(urlStr, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      body,
      timeoutMs: timeoutMs || 15_000,
    });
  }

  // ── Telegram API calls ──────────────────────────────────────────────────────

  telegramUrl(method) {
    return `https://api.telegram.org/bot${this.botToken}/${method}`;
  }

  /**
   * Call a Telegram Bot API method.
   * Handles 429 rate-limit responses with exponential backoff.
   */
  async callTelegram(method, data, attempt = 0) {
    const url = this.telegramUrl(method);
    let result;
    try {
      result = await this.postJson(url, data, method === 'getUpdates' ? 40_000 : 15_000);
    } catch (err) {
      this.log('WARN', `Telegram ${method} network error (attempt ${attempt}): ${err.message}`);
      return null;
    }

    // Type guard: ensure body is a parsed object before accessing properties
    const isBodyObject = typeof result.body === 'object' && result.body !== null;

    if (result.statusCode === 429) {
      if (isBodyObject) {
        const retryAfter = result.body.parameters?.retry_after || Math.pow(2, attempt + 1);
        const delay = Math.min(retryAfter * 1000, this.maxBackoffMs);
        this.log('WARN', `Telegram rate limited on ${method}. Backing off ${delay}ms.`);
        await sleep(delay);
        return this.callTelegram(method, data, attempt + 1);
      } else {
        // Non-JSON body on 429 — log raw body for debugging and use default backoff
        this.log('WARN', `Telegram rate limited on ${method} with non-JSON response. Raw body: ${String(result.body).slice(0, 200)}`);
        const delay = Math.min(Math.pow(2, attempt + 1) * 1000, this.maxBackoffMs);
        await sleep(delay);
        return this.callTelegram(method, data, attempt + 1);
      }
    }

    if (result.statusCode !== 200 || !(isBodyObject && result.body.ok)) {
      if (!isBodyObject) {
        this.log('WARN', `Telegram ${method} returned non-JSON body (HTTP ${result.statusCode}). Raw body: ${String(result.body).slice(0, 200)}`);
      } else {
        const desc = result.body.description || `HTTP ${result.statusCode}`;
        this.log('WARN', `Telegram ${method} failed: ${desc}`);
      }
      return null;
    }

    return result.body.result;
  }

  async sendMessage(chatId, text, parseMode) {
    const payload = {
      chat_id: chatId,
      text,
    };
    if (parseMode && parseMode !== 'plain') {
      payload.parse_mode = parseMode === 'markdown' ? 'Markdown' : parseMode;
    }
    return this.callTelegram('sendMessage', payload);
  }

  async getUpdates(timeoutSeconds) {
    return this.callTelegram('getUpdates', {
      offset: this.offset,
      timeout: timeoutSeconds,
      allowed_updates: ['message'],
    });
  }

  async setWebhook(webhookUrl) {
    return this.callTelegram('setWebhook', { url: webhookUrl });
  }

  async deleteWebhook() {
    return this.callTelegram('deleteWebhook', { drop_pending_updates: false });
  }

  async getMe() {
    return this.callTelegram('getMe', {});
  }

  // ── Operator communication ──────────────────────────────────────────────────

  /**
   * Forward a normalized message envelope to the community-ops-frontdesk endpoint.
   * Returns the operator's response object, or null on failure.
   */
  async forwardToOperator(envelope) {
    let result;
    try {
      result = await this.postJson(this.operatorEndpoint, envelope, 30_000);
    } catch (err) {
      this.log('ERROR', `Operator endpoint unreachable (attempt 1): ${err.message}`);
      // Retry once after delay
      await sleep(this.operatorRetryDelayMs);
      try {
        result = await this.postJson(this.operatorEndpoint, envelope, 30_000);
      } catch (retryErr) {
        this.log('ERROR', `Operator endpoint unreachable (attempt 2): ${retryErr.message}`);
        return null;
      }
    }

    if (result.statusCode < 200 || result.statusCode >= 300) {
      this.log('ERROR', `Operator returned HTTP ${result.statusCode}`);
      return null;
    }

    return result.body;
  }

  // ── Message normalization ────────────────────────────────────────────────────

  /**
   * Build the standard channel envelope from a Telegram message object.
   */
  normalizeMessage(msg) {
    const from = msg.from || {};
    const chat = msg.chat || {};
    const userId = from.id;
    const chatType = chat.type;
    const canonicalChatType = this.determineChatType(chat);
    const trustLevel = this.determineTrustLevel(userId, chatType);
    const messageType = this.determineMessageType(msg);
    const text = msg.text || msg.caption || '';

    return {
      channel: 'telegram',
      channel_message_id: String(msg.message_id),
      sender_id: String(userId || ''),
      sender_display_name: this.getSenderName(from),
      trust_level: trustLevel,
      chat_id: String(chat.id),
      chat_type: canonicalChatType,
      text,
      media: null,
      message_type: messageType,
      received_at: new Date(msg.date * 1000).toISOString(),
    };
  }

  // ── Message handling ─────────────────────────────────────────────────────────

  /**
   * Process a single incoming Telegram message update.
   */
  async handleMessage(msg) {
    if (!msg) return;

    const chatId = String((msg.chat || {}).id || '');
    if (!chatId) return;

    const envelope = this.normalizeMessage(msg);

    // Voice notes: inform the user, do not forward
    if (envelope.message_type === 'voice') {
      this.log('INFO', `Voice note from ${envelope.sender_id} in chat ${chatId}`);
      await this.sendMessage(
        chatId,
        'I received a voice note. Voice processing is not yet configured.'
      );
      this.stats.processed++;
      return;
    }

    // Empty messages (e.g. photo-only with no caption)
    if (!envelope.text && envelope.message_type !== 'text') {
      this.log('INFO', `Non-text message type=${envelope.message_type} from ${envelope.sender_id}`);
      await this.sendMessage(
        chatId,
        `I received a ${envelope.message_type} message. Please send text to interact with the operator.`
      );
      this.stats.processed++;
      return;
    }

    if (!envelope.text) {
      return;
    }

    this.log(
      'INFO',
      `Message from ${envelope.sender_display_name} (${envelope.sender_id}) ` +
        `trust=${envelope.trust_level} chat=${chatId} type=${envelope.chat_type}: ` +
        `"${envelope.text.slice(0, 80)}${envelope.text.length > 80 ? '...' : ''}"`
    );

    const response = await this.forwardToOperator(envelope);

    if (!response) {
      this.stats.errors++;
      await this.sendMessage(
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

    await this.sendMessage(chatId, replyText, parseMode);
    this.stats.processed++;
  }

  // ── Long-polling loop ───────────────────────────────────────────────────────

  async pollLoop() {
    this.log('INFO', 'Starting long-polling loop...');

    while (this.running) {
      let updates;
      try {
        updates = await this.getUpdates(this.pollTimeoutSeconds);
      } catch (err) {
        this.log('WARN', `getUpdates error: ${err.message}`);
        this.stats.errors++;
        await sleep(this.pollIntervalMs * 2);
        continue;
      }

      if (!updates || !Array.isArray(updates)) {
        // Network error or empty response — wait before retrying
        await sleep(this.pollIntervalMs);
        continue;
      }

      for (const update of updates) {
        if (!this.running) break;

        // Advance offset to acknowledge this update
        this.offset = Math.max(this.offset, update.update_id + 1);

        if (update.message) {
          try {
            await this.handleMessage(update.message);
          } catch (err) {
            this.log('ERROR', `Unhandled error processing update ${update.update_id}: ${err.message}`);
            this.stats.errors++;
          }
        }
      }

      // Brief pause between poll cycles to avoid hammering the API unnecessarily
      if (updates.length === 0) {
        await sleep(this.pollIntervalMs);
      }
    }
  }

  // ── Webhook server ──────────────────────────────────────────────────────────

  startWebhookServer(port) {
    const webhookSecret = this.webhookSecret;

    if (!webhookSecret) {
      this.log('WARN', 'TELEGRAM_WEBHOOK_SECRET is not set — webhook authentication is DISABLED. Set this env var to secure incoming webhook requests.');
    }

    const server = http.createServer(async (req, res) => {
      if (req.method !== 'POST') {
        res.writeHead(405);
        res.end('Method Not Allowed');
        return;
      }

      // Webhook authentication: validate secret token header
      if (webhookSecret) {
        const headerSecret = req.headers['x-telegram-bot-api-secret-token'];
        if (headerSecret !== webhookSecret) {
          this.log('WARN', `Webhook rejected: invalid or missing X-Telegram-Bot-Api-Secret-Token header from ${req.socket.remoteAddress}`);
          res.writeHead(403, { 'Content-Type': 'application/json' });
          res.end('{"ok":false,"error":"forbidden"}');
          return;
        }
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
          this.log('WARN', 'Received non-JSON webhook payload');
          return;
        }

        if (update.message) {
          try {
            await this.handleMessage(update.message);
          } catch (err) {
            this.log('ERROR', `Unhandled error in webhook handler: ${err.message}`);
            this.stats.errors++;
          }
        }
      });

      req.on('error', (err) => {
        this.log('WARN', `Webhook request error: ${err.message}`);
      });
    });

    server.listen(port, () => {
      this.log('INFO', `Webhook HTTP server listening on port ${port}`);
    });

    server.on('error', (err) => {
      this.log('ERROR', `Webhook server error: ${err.message}`);
    });

    return server;
  }

  // ── Utilities ───────────────────────────────────────────────────────────────

  printStats() {
    const uptime = Math.round((Date.now() - new Date(this.stats.started).getTime()) / 1000);
    this.log('INFO', '--- Shutdown stats -----------------------------------------');
    this.log('INFO', `  Started:            ${this.stats.started}`);
    this.log('INFO', `  Uptime:             ${uptime}s`);
    this.log('INFO', `  Messages processed: ${this.stats.processed}`);
    this.log('INFO', `  Errors:             ${this.stats.errors}`);
    this.log('INFO', '-------------------------------------------------------------');
  }

  // ── Startup validation ──────────────────────────────────────────────────────

  validateConfig() {
    const errors = [];
    if (!this.botToken) {
      errors.push('TELEGRAM_BOT_TOKEN is not set');
    }
    if (!this.operatorEndpoint) {
      errors.push('OPERATOR_ENDPOINT is not set');
    }
    return errors;
  }

  // ── Main entry ──────────────────────────────────────────────────────────────

  async run() {
    this.log('INFO', '=============================================================');
    this.log('INFO', '  Mesha Telegram Channel Adapter');
    this.log('INFO', '=============================================================');

    const configErrors = this.validateConfig();
    if (configErrors.length > 0) {
      for (const err of configErrors) {
        this.log('ERROR', `Configuration error: ${err}`);
      }
      process.exit(1);
    }

    const mode = this.webhookUrl ? 'webhook' : 'polling';
    this.log('INFO', `Mode:                ${mode}`);
    this.log('INFO', `Operator endpoint:   ${this.operatorEndpoint}`);
    this.log(
      'INFO',
      `Maintainer IDs:      ${this.maintainerIds.size > 0 ? `${this.maintainerIds.size} configured` : 'none configured (no maintainer-level trust)'}`
    );
    this.log(
      'INFO',
      `Lead maintainer IDs: ${this.leadMaintainerIds.size > 0 ? `${this.leadMaintainerIds.size} configured` : 'none configured (no lead_maintainer-level trust)'}`
    );

    // Verify the bot token is valid
    const botInfo = await this.getMe();
    if (!botInfo) {
      this.log('ERROR', 'Failed to authenticate with Telegram. Check TELEGRAM_BOT_TOKEN.');
      process.exit(1);
    }
    this.log('INFO', `Bot identity:        @${botInfo.username} (id: ${botInfo.id})`);

    // Graceful shutdown
    const shutdown = () => {
      if (!this.running) return;
      this.running = false;
      this.log('INFO', 'Shutting down...');
      this.printStats();
      process.exit(0);
    };
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);

    if (mode === 'webhook') {
      // Register the webhook URL with Telegram
      const webhookResult = await this.setWebhook(this.webhookUrl);
      if (webhookResult === null) {
        this.log('ERROR', `Failed to register webhook at ${this.webhookUrl}. Check the URL and try again.`);
        process.exit(1);
      }
      this.log('INFO', `Webhook registered: ${this.webhookUrl}`);

      // Start the local HTTP server to receive webhook pushes
      const webhookPort = parseInt(process.env.WEBHOOK_PORT || '8080', 10);
      this.startWebhookServer(webhookPort);

      // Keep the process alive
      await new Promise(() => {});
    } else {
      // Remove any existing webhook so polling works correctly
      await this.deleteWebhook();
      this.log('INFO', `Poll interval:       ${this.pollIntervalMs}ms`);
      this.log('INFO', '-------------------------------------------------------------');
      await this.pollLoop();
    }
  }
}

// ── Module entry point ─────────────────────────────────────────────────────────

async function main() {
  const adapter = new TelegramAdapter();
  await adapter.run();
}

main().catch((err) => {
  const ts = new Date().toISOString();
  console.error(`[${ts}] [ERROR] Fatal error: ${err.message}`);
  if (err.stack) console.error(`[${ts}] [ERROR] ${err.stack}`);
  process.exit(1);
});

export default TelegramAdapter;
