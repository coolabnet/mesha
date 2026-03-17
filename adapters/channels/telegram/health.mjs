/**
 * adapters/channels/telegram/health.mjs
 *
 * Health check script for the Telegram channel adapter.
 *
 * Checks:
 *   1. TELEGRAM_BOT_TOKEN is set
 *   2. Telegram getMe API responds successfully (token is valid)
 *   3. OPERATOR_ENDPOINT is set
 *   4. OPERATOR_ENDPOINT is reachable (HTTP GET with timeout)
 *
 * Exits 0 if all checks pass, 1 if any check fails.
 *
 * Usage: node adapters/channels/telegram/health.mjs
 */

import https from 'https';
import http from 'http';
import { URL } from 'url';

const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || '';
const OPERATOR_ENDPOINT = (process.env.OPERATOR_ENDPOINT || 'http://localhost:3000').trim();

// Check timeout in milliseconds
const CHECK_TIMEOUT_MS = 10_000;

// ── Output helpers ─────────────────────────────────────────────────────────────

const PASS = '\x1b[32mPASS\x1b[0m';
const FAIL = '\x1b[31mFAIL\x1b[0m';
const INFO = '\x1b[36mINFO\x1b[0m';

function printCheck(label, passed, detail) {
  const status = passed ? PASS : FAIL;
  const line = `  [${status}] ${label}`;
  if (detail) {
    console.log(`${line} — ${detail}`);
  } else {
    console.log(line);
  }
}

// ── HTTP helpers ───────────────────────────────────────────────────────────────

function httpGet(urlStr, timeoutMs) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(urlStr);
    const isHttps = parsed.protocol === 'https:';
    const lib = isHttps ? https : http;

    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (isHttps ? 443 : 80),
      path: parsed.pathname + (parsed.search || ''),
      method: 'GET',
      timeout: timeoutMs,
    };

    const req = lib.request(options, (res) => {
      // Consume the body to free the socket
      res.resume();
      resolve({ statusCode: res.statusCode });
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timed out'));
    });

    req.on('error', (err) => {
      reject(err);
    });

    req.end();
  });
}

function httpPostJson(urlStr, data, timeoutMs) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(urlStr);
    const isHttps = parsed.protocol === 'https:';
    const lib = isHttps ? https : http;
    const body = JSON.stringify(data);

    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (isHttps ? 443 : 80),
      path: parsed.pathname + (parsed.search || ''),
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: timeoutMs,
    };

    const req = lib.request(options, (res) => {
      let responseBody = '';
      res.on('data', (chunk) => (responseBody += chunk));
      res.on('end', () => {
        let parsed;
        try {
          parsed = JSON.parse(responseBody);
        } catch {
          parsed = responseBody;
        }
        resolve({ statusCode: res.statusCode, body: parsed });
      });
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timed out'));
    });

    req.on('error', (err) => {
      reject(err);
    });

    req.write(body);
    req.end();
  });
}

// ── Checks ─────────────────────────────────────────────────────────────────────

async function checkBotToken() {
  if (!BOT_TOKEN) {
    return { passed: false, detail: 'TELEGRAM_BOT_TOKEN is not set' };
  }
  // Avoid logging the token itself; just confirm it is non-empty
  return { passed: true, detail: 'TELEGRAM_BOT_TOKEN is set' };
}

async function checkTelegramApi() {
  if (!BOT_TOKEN) {
    return { passed: false, detail: 'Skipped — no token available' };
  }

  const url = `https://api.telegram.org/bot${BOT_TOKEN}/getMe`;
  let result;
  try {
    result = await httpPostJson(url, {}, CHECK_TIMEOUT_MS);
  } catch (err) {
    return { passed: false, detail: `Network error: ${err.message}` };
  }

  if (result.statusCode === 401) {
    return { passed: false, detail: 'Token rejected by Telegram (HTTP 401 Unauthorized)' };
  }

  if (result.statusCode !== 200 || !result.body?.ok) {
    const desc = result.body?.description || `HTTP ${result.statusCode}`;
    return { passed: false, detail: `Telegram API error: ${desc}` };
  }

  const bot = result.body.result;
  return {
    passed: true,
    detail: `Bot verified: @${bot.username} (id: ${bot.id})`,
  };
}

async function checkOperatorEndpointSet() {
  if (!OPERATOR_ENDPOINT) {
    return { passed: false, detail: 'OPERATOR_ENDPOINT is not set' };
  }
  return { passed: true, detail: `OPERATOR_ENDPOINT is set: ${OPERATOR_ENDPOINT}` };
}

async function checkOperatorEndpointReachable() {
  if (!OPERATOR_ENDPOINT) {
    return { passed: false, detail: 'Skipped — OPERATOR_ENDPOINT not set' };
  }

  let result;
  try {
    result = await httpGet(OPERATOR_ENDPOINT, CHECK_TIMEOUT_MS);
  } catch (err) {
    return {
      passed: false,
      detail: `Cannot reach ${OPERATOR_ENDPOINT}: ${err.message}`,
    };
  }

  // Any HTTP response (even 404 or 405) means the server is up
  return {
    passed: true,
    detail: `${OPERATOR_ENDPOINT} responded with HTTP ${result.statusCode}`,
  };
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  console.log('');
  console.log('  Mesha Telegram Adapter — Health Check');
  console.log('  ──────────────────────────────────────');
  console.log('');

  const checks = [
    { label: 'TELEGRAM_BOT_TOKEN is configured', fn: checkBotToken },
    { label: 'Telegram Bot API responds (getMe)', fn: checkTelegramApi },
    { label: 'OPERATOR_ENDPOINT is configured', fn: checkOperatorEndpointSet },
    { label: 'Operator endpoint is reachable', fn: checkOperatorEndpointReachable },
  ];

  let allPassed = true;

  for (const check of checks) {
    let result;
    try {
      result = await check.fn();
    } catch (err) {
      result = { passed: false, detail: `Unexpected error: ${err.message}` };
    }
    if (!result.passed) allPassed = false;
    printCheck(check.label, result.passed, result.detail);
  }

  console.log('');

  if (allPassed) {
    console.log(`  [${INFO}] All checks passed. The adapter is ready to start.`);
    console.log('');
    process.exit(0);
  } else {
    console.log(`  [${FAIL}] One or more checks failed. Fix the issues above before starting the adapter.`);
    console.log('');
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(`  [FATAL] Health check script error: ${err.message}`);
  process.exit(1);
});
