#!/usr/bin/env node
// =============================================================================
// scripts/bootstrap.mjs
// Mesha Community Infrastructure Operator — Node.js Bootstrap Check
//
// A zero-dependency (built-in modules only) ESM script that checks all
// required tools are present and reports pass/fail/warn for each.
//
// Works on Linux, macOS, and WSL2.
//
// Usage:
//   node scripts/bootstrap.mjs
//
// Exit codes:
//   0 — all required tools present (optional tools may be missing with WARN)
//   1 — one or more required tools are missing
//
// Risk class: Class A (read-only diagnostics — see TOOLS.md).
// =============================================================================

import { execSync, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import process from 'node:process';

// ---------------------------------------------------------------------------
// Resolve repo root (scripts/ is one level below the repo root)
// ---------------------------------------------------------------------------
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(join(__dirname, '..'));

// ---------------------------------------------------------------------------
// ANSI colour helpers
// ---------------------------------------------------------------------------
const C = {
  reset:  '\x1b[0m',
  bold:   '\x1b[1m',
  red:    '\x1b[31m',
  yellow: '\x1b[33m',
  green:  '\x1b[32m',
  cyan:   '\x1b[36m',
};

// Detect if the terminal likely supports colour
const useColour = process.stdout.isTTY !== false;
const col = (code, text) => useColour ? `${code}${text}${C.reset}` : text;

const pass = (msg) => console.log(`  ${col(C.green,  '[PASS]')} ${msg}`);
const warn = (msg) => console.log(`  ${col(C.yellow, '[WARN]')} ${msg}`);
const fail = (msg) => console.log(`  ${col(C.red,    '[FAIL]')} ${msg}`);
const info = (msg) => console.log(`  ${col(C.cyan,   '[INFO]')} ${msg}`);

const header = (title) => {
  console.log(`\n${col(C.bold + C.cyan, `── ${title} ──`)}`);
};

// ---------------------------------------------------------------------------
// Utility: run a command and return trimmed stdout, or null on failure
// ---------------------------------------------------------------------------
function run(cmd, args = []) {
  const result = spawnSync(cmd, args, { encoding: 'utf8' });
  if (result.error || result.status !== 0) return null;
  return (result.stdout || '').trim() || (result.stderr || '').trim() || '(ok)';
}

// ---------------------------------------------------------------------------
// Utility: check if a command exists in PATH
// ---------------------------------------------------------------------------
function commandExists(cmd) {
  const which = spawnSync('which', [cmd], { encoding: 'utf8' });
  return which.status === 0;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
const missingRequired = [];
const missingOptional = [];

// ---------------------------------------------------------------------------
// Check 1: Node.js version (must be v22+)
// ---------------------------------------------------------------------------
header('Node.js version (v22+ required)');

const nodeVer = process.version; // e.g. "v22.3.0"
const nodeMajor = parseInt(nodeVer.replace('v', '').split('.')[0], 10);

if (nodeMajor >= 22) {
  pass(`node ${nodeVer}`);
} else {
  fail(`node ${nodeVer} — v22 or newer is required`);
  missingRequired.push('node@22+');
  info('Install suggestion (Linux/WSL2): curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs');
  info('Install suggestion (macOS):      brew install node@22');
  info('Alternative (any platform):      https://github.com/nvm-sh/nvm  →  nvm install 22');
}

// ---------------------------------------------------------------------------
// Check 2: git
// ---------------------------------------------------------------------------
header('git');

const gitVer = run('git', ['--version']);
if (gitVer) {
  pass(gitVer);
} else {
  fail('git not found');
  missingRequired.push('git');
  info('Install suggestion (Linux/WSL2): sudo apt install -y git');
  info('Install suggestion (macOS):      brew install git');
}

// ---------------------------------------------------------------------------
// Check 3: ssh
// ---------------------------------------------------------------------------
header('SSH client');

// ssh -V writes to stderr on most platforms
const sshResult = spawnSync('ssh', ['-V'], { encoding: 'utf8' });
const sshFound = sshResult.status === 0 || (sshResult.stderr && sshResult.stderr.trim().length > 0);

if (sshFound) {
  const sshVer = (sshResult.stderr || sshResult.stdout || '').trim().split('\n')[0];
  pass(`ssh — ${sshVer}`);
} else {
  fail('ssh not found');
  missingRequired.push('ssh');
  info('Install suggestion (Linux/WSL2): sudo apt install -y openssh-client');
  info('Install suggestion (macOS):      SSH is included with macOS by default.');
}

// ---------------------------------------------------------------------------
// Check 4: curl
// ---------------------------------------------------------------------------
header('curl');

const curlVer = run('curl', ['--version']);
if (curlVer) {
  pass(curlVer.split('\n')[0]);
} else {
  fail('curl not found');
  missingRequired.push('curl');
  info('Install suggestion (Linux/WSL2): sudo apt install -y curl');
  info('Install suggestion (macOS):      brew install curl');
}

// ---------------------------------------------------------------------------
// Check 5: jq
// ---------------------------------------------------------------------------
header('jq');

const jqVer = run('jq', ['--version']);
if (jqVer) {
  pass(jqVer);
} else {
  warn('jq not found (strongly recommended for data processing)');
  missingOptional.push('jq');
  info('Install suggestion (Linux/WSL2): sudo apt install -y jq');
  info('Install suggestion (macOS):      brew install jq');
}

// ---------------------------------------------------------------------------
// Check 6: python3
// ---------------------------------------------------------------------------
header('Python 3');

const py3Ver = run('python3', ['--version']);
if (py3Ver) {
  pass(py3Ver);
} else {
  warn('python3 not found (recommended for helper scripts)');
  missingOptional.push('python3');
  info('Install suggestion (Linux/WSL2): sudo apt install -y python3 python3-pip');
  info('Install suggestion (macOS):      brew install python3');
}

// ---------------------------------------------------------------------------
// Check 7: docker
// ---------------------------------------------------------------------------
header('Docker');

const dockerVer = run('docker', ['--version']);
if (dockerVer) {
  pass(dockerVer);

  // Check if daemon is reachable (non-fatal)
  const dockerInfo = spawnSync('docker', ['info'], { encoding: 'utf8' });
  if (dockerInfo.status !== 0) {
    warn('docker is installed but the daemon is not reachable.');
    warn('Make sure Docker is running and your user is in the docker group.');
    info('  sudo usermod -aG docker $USER   (then log out and back in)');
  }
} else {
  warn('docker not found (strongly recommended for local services)');
  missingOptional.push('docker');
  info('Install suggestion (Linux/WSL2): sudo apt install -y docker.io && sudo usermod -aG docker $USER');
  info('Install suggestion (macOS):      https://www.docker.com/products/docker-desktop/');
}

// ---------------------------------------------------------------------------
// Check 8: OpenClaw CLI
// ---------------------------------------------------------------------------
header('OpenClaw CLI');

let openclawFound = false;
for (const candidate of ['openclaw', 'openclaw-cli']) {
  if (commandExists(candidate)) {
    const ocVer = run(candidate, ['--version']);
    pass(`OpenClaw (${candidate}) — ${ocVer}`);
    openclawFound = true;
    break;
  }
}

if (!openclawFound) {
  fail('OpenClaw CLI not found');
  missingRequired.push('openclaw');
  info('Install (requires Node.js 22+ first):  npm install -g @openclaw/cli');
  info('Then verify with:                       openclaw --version');
  info('Run onboarding with:                    openclaw init');
}

// ---------------------------------------------------------------------------
// Check 9: Workspace root sanity
// ---------------------------------------------------------------------------
header('Workspace repository');

const bootstrapMd = join(REPO_ROOT, 'BOOTSTRAP.md');
if (existsSync(bootstrapMd)) {
  pass(`BOOTSTRAP.md found at ${REPO_ROOT}`);
} else {
  fail(`BOOTSTRAP.md not found — workspace may not be properly set up (looking in ${REPO_ROOT})`);
  missingRequired.push('workspace');
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
header('Summary');

if (missingRequired.length === 0 && missingOptional.length === 0) {
  console.log(`\n  ${col(C.green + C.bold, 'All checks passed. This host is ready.')}\n`);
} else {
  if (missingRequired.length > 0) {
    console.log(`\n  ${col(C.red + C.bold, 'Required items missing:')}`);
    for (const t of missingRequired) {
      console.log(`    ${col(C.red, '✗')} ${t}`);
    }
  }
  if (missingOptional.length > 0) {
    console.log(`\n  ${col(C.yellow + C.bold, 'Recommended items missing:')}`);
    for (const t of missingOptional) {
      console.log(`    ${col(C.yellow, '⚠')} ${t}`);
    }
  }
}

console.log('');
if (missingRequired.length > 0) {
  console.log('  Next steps:');
  console.log('    1. Install the missing required tools listed above.');
  console.log('    2. Re-run this script: node scripts/bootstrap.mjs');
} else {
  console.log('  Next steps:');
  console.log('    1. Run the health check:    bash scripts/doctor.sh');
  console.log('    2. Activate the workspace:  bash scripts/activate-workspace.sh');
}
console.log('');

// ---------------------------------------------------------------------------
// Exit code
// ---------------------------------------------------------------------------
process.exit(missingRequired.length > 0 ? 1 : 0);
