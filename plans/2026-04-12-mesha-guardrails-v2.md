# Mesha Guardrails — Pre-Commit and CI Implementation Tracker

**Created:** 2026-04-12
**Revised:** 2026-04-12 (v2 — incorporated review findings)
**Status:** Planning
**Source analysis:** Full project scan (196 files, 13 file types)

---

## Objective

Implement automated quality and safety guardrails for the Mesha project covering: secret leak prevention, shell script linting, YAML/JSON/UCI validation, Python and JavaScript code quality, Docker config validation, and targeted test coverage expansion. All guardrails run both as pre-commit hooks (developer-side) and CI checks (PR-side).

---

## Priority Legend

| Priority | Meaning |
|----------|---------|
| P0 — Critical | Security risk. Must be implemented first. |
| P1 — High | Quality risk that could cause silent failures in production. |
| P2 — Medium | Improves maintainability and catches bugs early. |
| P3 — Low | Nice-to-have for consistency and polish. |

---

## Project Context

- **No CI platform is chosen yet.** The project has no `.github/`, `.gitlab-ci.yml`, or any CI config. The plan provides a CI-agnostic runner script; a platform-specific workflow file can be generated once the platform is chosen.
- **No `package.json`.** The project intentionally avoids npm dependencies. JavaScript tooling should use `npx` (no config file) or `deno` where possible.
- **Must work offline.** Guardrails must not require internet access during execution.
- **Custom test suite.** `tests/run-all.sh` runs 5 categories. New guardrails should integrate into this existing framework, not duplicate it.
- **UCI config files.** The project manages OpenWrt UCI configs (`lime-community`, `*.uci` overrides) that get pushed to production routers. These are not standard file formats and need custom validation.

---

## Phase 1: Secret Prevention + Pre-Commit Framework (P0)

### 1.1 Betterleaks Setup

**Rationale:** The project manages SSH keys to routers/servers, Telegram bot tokens, Tailscale auth keys, and database credentials. A leaked secret gives direct access to community infrastructure. The existing `.gitignore` covers the most common patterns but is missing some entries documented as required in `secrets/README.md:94-103`. The test suite (`tests/01-file-inventory.sh:156-179`) checks that `secrets/` has no credential files, but secrets could leak into scripts or YAML elsewhere.

- [ ] Fix `.gitignore` gaps — add missing patterns from `secrets/README.md:94-103`:
  - `secrets/*.token`
  - `secrets/*.password`
  - `secrets/credentials`
  - `*.private`
- [ ] Create `.betterleaks.toml` config at project root:
  - Extend default rules (`useDefault = true`)
  - Add global allowlist for `.env.example` files (contain empty variable names like `MESHA_TELEGRAM_BOT_TOKEN=`)
  - Add global allowlist for `secrets/README.md` (contains example patterns)
  - Add global allowlist for `.betterleaks.toml` itself
  - Add global allowlist for test fixture files in `docker/` (thisnode HTTP responses)
- [ ] Create `.betterleaksignore` baseline file (empty initially, populated after first scan)
- [ ] Run initial full-repo scan: `betterleaks dir -v .` — capture results into a baseline report
- [ ] Review initial findings — determine which are real secrets vs false positives
- [ ] Rotate any real secrets found in the initial scan immediately
- [ ] Add pre-commit hook for betterleaks (via `.pre-commit-config.yaml`)
- [ ] Add CI job: `betterleaks git -v --baseline-path .betterleaksignore` on every PR (requires full git history)

**Verification:**

- [ ] `betterleaks dir .` returns exit code 0 after baseline is established
- [ ] Intentionally stage a fake API key and verify the pre-commit hook blocks it
- [ ] `.env.example` files do not trigger false positives

### 1.2 Pre-Commit Framework Setup

**Rationale:** No `.pre-commit-config.yaml` exists. This is the foundation that all other hooks depend on.

- [ ] Create `.pre-commit-config.yaml` with the initial set of hooks (built up per-phase below)
- [ ] Include `no-commit-to-branch` hook targeting `main` branch (listed in summary but was missing from v1 tasks)
- [ ] Include `detect-private-key` hook from `pre-commit-hooks` (catches SSH keys that betterleaks might miss)
- [ ] Include `check-merge-conflict` hook
- [ ] Include `end-of-file-fixer` and `trailing-whitespace` hooks (low cost, high consistency)
- [ ] Add `pre-commit` install instructions to project setup docs (BOOTSTRAP.md or README.md)
- [ ] Add `pre-commit run --all-files` to CI as a job

**Verification:**

- [ ] `pre-commit run --all-files` passes on a clean checkout
- [ ] Direct commit to `main` is blocked by the hook

---

## Phase 2: Shell Script Quality (P1)

**Rationale:** 36 shell scripts run critical operations — `sysupgrade` on routers, Docker management on servers, SSH into production devices. The current syntax check in `tests/02-syntax.sh:24-58` uses a hardcoded list of 33 files — new scripts won't be caught.

### 2.1 Shellcheck Integration

- [ ] Add `shellcheck-py` hook to `.pre-commit-config.yaml` targeting all `.sh` files
- [ ] Configure `args: ["--severity=warning"]`
- [ ] Fix existing shellcheck warnings across all `.sh` files
- [ ] Add `# shellcheck disable=SCXXXX` directives where false positives are confirmed
- [ ] Add CI step: `find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck --severity=warning`

**Verification:**

- [ ] `shellcheck --severity=error` passes on all `.sh` files
- [ ] `shellcheck --severity=warning` passes or has documented suppressions

### 2.2 Shell Formatting (shfmt)

- [ ] Add `shfmt` hook to `.pre-commit-config.yaml`
- [ ] Configure: indent 2 spaces, simplify (`-s`), binary-next-line (`-bn`)
- [ ] Run `shfmt -w` on all existing `.sh` files to normalize formatting
- [ ] Add CI check: `shfmt -d .` (diff mode)

**Verification:**

- [ ] `shfmt -d .` returns no output (all files formatted)

### 2.3 Auto-Discovery and Safety Checks

- [ ] Replace hardcoded file list in `tests/02-syntax.sh:24-58` with `find . -name '*.sh' -not -path './.git/*'`
- [ ] Add a test case: detect `.sh` files with a shebang (`#!/bin/bash` or `#!/bin/sh`) that are not marked executable
- [ ] Add a test case: detect `.sh` files outside `tests/` that are missing `set -euo pipefail` (or `set -uo pipefail` with a `# reason:` comment justifying the omission). Note: `tests/` files use `set -uo pipefail` intentionally and should be excluded from this check.

**Verification:**

- [ ] Adding a new `.sh` file anywhere in the tree is caught by the syntax test without manual list updates

---

## Phase 3: Configuration Validation (P1)

**Rationale:** 29+ YAML files, 2+ UCI files, and 13 JSON files form the foundation of the safety model. Cross-references between `mesh-nodes.yaml`, `sites.yaml`, and `gateways.yaml` could break silently. The existing `tests/03-schema.sh` (629 lines) already provides thorough inline Python validation — this phase adds tool-based linting and fills gaps, rather than replacing what works.

### 3.1 Yamllint

- [ ] Create `.yamllint` configuration file:

  ```yaml
  extends: relaxed
  rules:
    line-length:
      max: 120
    document-start: disable
    truthy: disable
  ignore: |
    .git/
    node_modules/
  ```

- [ ] Add `yamllint` hook to `.pre-commit-config.yaml`
- [ ] Fix existing yamllint warnings across all YAML files
- [ ] Add CI step: `yamllint .`

**Verification:**

- [ ] `yamllint .` returns exit code 0

### 3.2 UCI Config Validation

**Rationale:** The project manages OpenWrt UCI configuration files (`desired-state/mesh/community-profile/lime-community` and `desired-state/mesh/node-overrides/*.uci`) that get pushed to production routers. These are not YAML or standard config files — they use the UCI format (`config <type> '<name>'` / `option <key> '<value>'` / `list <key> '<value>'`). A malformed UCI file pushed to a router could break its network configuration.

- [ ] Create `tests/06-uci-validate.sh` that validates UCI files:
  - Check that `lime-community` parses correctly (basic syntax: `config`/`option`/`list` lines, comment lines, blank lines)
  - Check that each `*.uci` file in `node-overrides/` parses correctly
  - Check that each `*.uci` file's hostname matches a node in `inventories/mesh-nodes.yaml` (cross-reference)
  - Check that no UCI file contains secrets (grep for `password`, `secret`, `key` in option values — `mesh_bssid` and `anygw_mac` are not secrets, they're public identifiers)
- [ ] Register test 06 in `tests/run-all.sh` category registry

**Verification:**

- [ ] All UCI files pass syntax validation
- [ ] A `.uci` file referencing a nonexistent node is caught

### 3.3 `.env.example` Consistency Check

**Rationale:** The schema test (`tests/03-schema.sh:567-620`) verifies that `.env.example` files exist alongside `docker-compose.yaml` files, but does not check that the variables listed in `.env.example` match what `docker-compose.yaml` and `install.sh` actually reference. A variable could be added to the compose file without updating the example.

- [ ] Add a check to `tests/03-schema.sh` (section H) that extracts `${VARIABLE}` references from each `docker-compose.yaml` and verifies each appears in the corresponding `.env.example`
- [ ] Verify homer service: `skills/server-services/scripts/homer/docker-compose.yaml` has no `.env.example` — confirm this is intentional (homer compose has no env vars) or create one if needed

**Verification:**

- [ ] A new `${SOME_VAR}` added to a `docker-compose.yaml` without a corresponding `.env.example` entry is caught

### 3.4 Docker Compose Validation

- [ ] Add CI step: validate all `docker-compose*.y*ml` files with `docker compose -f <file> config --quiet`
- [ ] Mark as allowed-failure if Docker daemon is unavailable
- [ ] Add a 1-liner grep check for unpinned Docker image tags:

  ```bash
  grep -rn 'image:.*:latest\|image:[^:]*$' --include='*.yaml' --include='*.yml' . | grep -v '.git/'
  ```

  Note: `homer/docker-compose.yaml:3` currently uses `b4bz/homer:latest` — this should be pinned

**Verification:**

- [ ] `docker compose config` passes for all compose files (when Docker available)
- [ ] No Docker image uses `latest` or unpinned tag

---

## Phase 4: Python Code Quality (P2)

**Rationale:** 7 Python files. `adapters/mesh/normalize.py` (353 lines) is the most complex module with zero dedicated tests. The 6 helper scripts in `skills/mesh-rollout/scripts/helpers/` are not in the syntax check list. The current check in `tests/02-syntax.sh:87-89` only covers `normalize.py`.

### 4.1 Ruff Linting and Formatting

- [ ] Add `ruff-pre-commit` hook to `.pre-commit-config.yaml` with `ruff check` and `ruff format --check`
- [ ] Create `pyproject.toml` with minimal config:

  ```toml
  [tool.ruff]
  target-version = "py311"
  line-length = 120

  [tool.ruff.lint]
  select = ["E", "F", "W", "I", "UP", "B", "SIM"]
  ```

- [ ] Run `ruff check --fix` on all `.py` files
- [ ] Run `ruff format` on all `.py` files
- [ ] Add CI step: `ruff check . && ruff format --check .`

**Verification:**

- [ ] `ruff check .` returns no findings
- [ ] `ruff format --check .` passes

### 4.2 Expand Syntax Check Coverage

- [ ] Replace hardcoded `PY_FILES` list in `tests/02-syntax.sh:87-89` with auto-discovery:
  `find . -name '*.py' -not -path './.git/*' -not -path './.venv/*' -not -path './node_modules/*'`
- [ ] Add `scripts/bootstrap.mjs` to the MJS syntax check list in `tests/02-syntax.sh:118-121` (currently missing — only `adapter.mjs` and `health.mjs` are checked)
- [ ] Add a test to extract and validate inline Python in shell heredocs:
  - `adapters/mesh/collect-nodes.sh` (embedded Python)
  - `skills/mesh-rollout/scripts/run-rollout.sh` (inline Python via heredoc)
  - Extract between heredoc markers, pipe to `python3 -c "import py_compile; py_compile.compile('/dev/stdin')"`

**Verification:**

- [ ] All `.py` files pass `py_compile` (auto-discovered)
- [ ] `scripts/bootstrap.mjs` is included in ESM syntax checks
- [ ] Inline Python in heredocs is extracted and syntax-validated

### 4.3 Unit Tests for normalize.py

- [ ] Create `tests/unit/test_normalize.py` using `unittest` (no external deps — consistent with project's zero-dependency philosophy)
- [ ] Test `normalize_node()` with:
  - Valid node data from `mesh-nodes.yaml`
  - Missing optional fields
  - Malformed MAC addresses
  - Unknown radio bands
- [ ] Test `compute_drift()` with:
  - Identical configs (zero drift)
  - Known drift scenarios (firmware version mismatch, channel change)
  - Empty desired state
- [ ] Test `_clean_mac()` with:
  - Standard colon-separated MACs
  - Hyphen-separated MACs
  - No-separator MACs
  - Mixed case
  - Empty/None input
- [ ] Test `find_inventory_node()` with matching and non-matching lookups
- [ ] Add CI step: `python3 -m pytest tests/unit/ -v` or `python3 -m unittest discover tests/unit/`

**Verification:**

- [ ] All unit tests pass
- [ ] Every public function in `normalize.py` has at least one test case

### 4.4 Unit Tests for Rollout Helpers

- [ ] Create `tests/unit/test_parse_rings.py` — test ring parsing with fixture YAML data
- [ ] Create `tests/unit/test_check_change_window.py` — test time window validation logic
- [ ] Add fixture data files in `tests/fixtures/` with sample YAML configs

**Verification:**

- [ ] All helper unit tests pass

---

## Phase 5: JavaScript Code Quality (P2)

**Rationale:** 3 `.mjs` files totaling ~1,136 lines. No linting, no formatting enforcement, no unit tests. The project has no `package.json` (intentional) — tooling must work without one.

### 5.1 Linting and Formatting (npx, no package.json)

- [ ] Add pre-commit hook for eslint using `npx eslint --no-install` or `deno lint`:
  - **Preferred:** Use `deno lint` and `deno fmt` — zero config files needed, no `package.json`, works offline if deno is installed
  - **Fallback:** Use `npx eslint` with a minimal `eslint.config.mjs` — requires a `package.json` with devDependencies
  - Decision point: if deno is acceptable as a dev tool, it avoids adding npm infrastructure entirely
- [ ] Run linting tool on all `.mjs` files and fix findings
- [ ] Run formatting tool on all `.mjs` files
- [ ] Add CI step for lint and format check

**Verification:**

- [ ] Linting passes on all `.mjs` files
- [ ] Formatting is consistent

### 5.2 Unit Tests for Telegram Adapter (deferred)

**Note:** Unit testing the Telegram adapter (`adapter.mjs`, 624 lines) is valuable but deferred because:

- It reads from env vars (`TELEGRAM_BOT_TOKEN`) and makes HTTP calls to the Telegram API
- Proper testing requires mocking HTTP and env, which means either a test framework or significant test infrastructure
- The adapter is likely to change as the project evolves

- [ ] (Deferred) Create `tests/unit/test_adapter.mjs` using Node's built-in `node:test` runner
- [ ] (Deferred) Test `determineTrustLevel()`, `normalizeMessage()`, `maskToken()`
- [ ] (Deferred) Add CI step: `node --test tests/unit/test_adapter.mjs`

**When to un-defer:** When the adapter API stabilizes or when a bug is found that tests would have caught.

---

## Phase 6: JSON Validation (P2)

**Rationale:** 13 JSON files including `adapters/mesh/field_map.json` which maps raw node data to canonical fields. Invalid mappings silently fail at runtime.

### 6.1 JSON Syntax Validation

- [ ] Add `check-json` hook from `pre-commit-hooks` to `.pre-commit-config.yaml`
- [ ] Add CI step: `find . -name '*.json' -not -path './.git/*' -not -path './node_modules/*' -print0 | xargs -0 python3 -m json.tool --no-ensure-ascii > /dev/null`

**Verification:**

- [ ] All `.json` files parse without error

### 6.2 field_map.json Cross-Reference

- [ ] Add a check to `tests/03-schema.sh` that verifies every canonical field name in `field_map.json` corresponds to a field that `normalize.py` actually uses or that appears in `mesh-nodes.yaml` schema checks
- [ ] This is a lightweight cross-reference check, not a full JSON Schema — consistent with the project's existing approach

**Verification:**

- [ ] An invalid field mapping in `field_map.json` is caught

---

## Phase 7: Docker Quality (P2)

**Rationale:** 2 Dockerfiles in `docker/onboarding-test/` and 7+ docker-compose files. No linting for Dockerfile best practices.

### 7.1 Dockerfile Linting (hadolint)

- [ ] Add hadolint as a CI-only check (not pre-commit — hadolint is not trivial to install locally on all platforms)
- [ ] Run hadolint on all Dockerfiles
- [ ] Fix or suppress findings

**Verification:**

- [ ] `hadolint` passes for all Dockerfiles in CI

---

## Phase 8: Markdown Quality (P3)

**Rationale:** 46 `.md` files. No validation. Cross-references between documents could break silently.

### 8.1 Markdownlint

- [ ] Add `markdownlint-cli` hook to `.pre-commit-config.yaml`
- [ ] Create `.markdownlint.json` config:

  ```json
  {
    "MD013": false,
    "MD033": false,
    "MD041": false,
    "MD036": false
  }
  ```

- [ ] Run `markdownlint --fix` on all `.md` files
- [ ] Add CI step: `markdownlint .`

**Verification:**

- [ ] `markdownlint .` returns no errors

### 8.2 Internal Link Validation

- [ ] Create a simple bash-based internal link checker (no external tool like lychee needed):
  - Extract `[text](relative/path)` patterns from all `.md` files
  - Check that the target file exists
  - Ignore external URLs (http/https) and anchor-only links (#section)
  - This is ~20 lines of bash, not a separate tool
- [ ] Add as a step in CI or as a test in the existing test suite

**Verification:**

- [ ] Broken internal links are caught

---

## Phase 9: Test Coverage Expansion (P1)

**Rationale:** Fill gaps in the existing test suite. New test categories should integrate into `tests/run-all.sh`.

### 9.1 New Test Categories

- [ ] Create `tests/06-uci-validate.sh` — UCI syntax + cross-reference (see Phase 3.2)
- [ ] Create `tests/07-inline-python.sh` — extract and validate Python in shell heredocs (see Phase 4.2)
- [ ] Update `tests/run-all.sh` to register categories 06-07
- [ ] Note: shellcheck, yamllint, ruff, eslint, and betterleaks are already covered by pre-commit + CI. They do NOT need separate test files — running the same check 3 times (pre-commit, test suite, CI) is wasteful. The test suite should only contain checks that are NOT duplicated by pre-commit hooks.

**Verification:**

- [ ] `bash tests/run-all.sh` runs all 7 categories and passes

### 9.2 PowerShell Coverage

**Rationale:** `scripts/bootstrap.ps1` is listed in `tests/01-file-inventory.sh:94` as a file that must exist, but has no syntax validation. If it's actively maintained, it needs a check. If not, it should be flagged.

- [ ] Determine if `scripts/bootstrap.ps1` is actively maintained or a legacy artifact
- [ ] If maintained: add a basic syntax check using `pwsh -NoExecute -File scripts/bootstrap.ps1` (if PowerShell is available) or skip with a clear message
- [ ] If not maintained: add a comment in the file header marking it as unmaintained, and note in `tests/01-file-inventory.sh` that it's a reference-only file

**Verification:**

- [ ] `bootstrap.ps1` status is documented and intentional

### 9.3 HTML Fixture Files

**Rationale:** 3 `.html` files exist as test fixtures in `docker/onboarding-test/fixtures/` and `docker/phase1/fixtures/`. These simulate `thisnode.info` HTTP responses. Malformed HTML could cause the onboarding test to fail in confusing ways.

- [ ] Add a basic check: verify HTML fixture files contain expected elements (e.g., `<html>`, `<body>` tags)
- [ ] This can be a few lines in the existing `tests/04-dryrun.sh` or `tests/01-file-inventory.sh`

**Verification:**

- [ ] Truncated or empty HTML fixtures are caught

---

## Phase 10: CI Pipeline (P1)

**Rationale:** No CI pipeline exists. All quality checks are manual. PRs can merge without any automated validation.

### 10.1 CI-Agnostic Runner Script

**Rationale:** The project has no indication of which CI platform it will use (GitHub Actions, GitLab CI, Gitea, self-hosted). Rather than committing to a platform now, create a single script that can be called from any CI.

- [ ] Create `scripts/ci-run.sh` that runs all quality checks in sequence:
  1. `betterleaks dir .` (secret scan)
  2. `find . -name '*.sh' ... | xargs shellcheck --severity=warning` (shell lint)
  3. `shfmt -d .` (shell format)
  4. `yamllint .` (YAML lint)
  5. `ruff check . && ruff format --check .` (Python lint + format)
  6. `find . -name '*.json' ... | xargs python3 -m json.tool > /dev/null` (JSON syntax)
  7. `bash tests/run-all.sh` (full test suite including UCI, inline Python, etc.)
  8. Docker compose validation + image pinning check (if Docker available)
  9. `hadolint` on Dockerfiles (if available)
- [ ] Script should exit on first failure with a clear error message
- [ ] Script should detect which tools are available and skip missing ones with a warning (not a failure)
- [ ] Document required tools in a comment at the top of the script

**Verification:**

- [ ] `bash scripts/ci-run.sh` passes on a clean checkout with all tools installed
- [ ] `bash scripts/ci-run.sh` degrades gracefully when optional tools are missing

### 10.2 Platform-Specific Workflow (when platform is chosen)

- [ ] Once a CI platform is chosen, create the appropriate workflow file:
  - GitHub Actions: `.github/workflows/qa.yml`
  - GitLab CI: `.gitlab-ci.yml`
  - Gitea Actions: `.gitea/workflows/qa.yml`
- [ ] The workflow should call `scripts/ci-run.sh` as its main step
- [ ] Configure branch protection: require CI to pass before merge
- [ ] Configure the workflow to run on `push` to `main` and on all `pull_request` events

**Verification:**

- [ ] CI pipeline runs on every PR
- [ ] All jobs pass on a clean branch

---

## Summary: Pre-Commit Hook Checklist

| Hook | What it catches | Priority |
|------|----------------|----------|
| `betterleaks` | Accidentally staged secrets, API keys, tokens | P0 |
| `detect-private-key` | Accidentally staged SSH private keys | P0 |
| `no-commit-to-branch` (main) | Direct commits to main branch | P1 |
| `shellcheck` | Shell script bugs, unsafe patterns | P1 |
| `shfmt` | Inconsistent shell formatting | P1 |
| `yamllint` | YAML syntax and style issues | P1 |
| `ruff` (check + format) | Python lint and formatting issues | P2 |
| `check-json` | Malformed JSON files | P2 |
| `check-merge-conflict` | Unresolved merge conflict markers | P2 |
| `end-of-file-fixer` | Missing newlines at EOF | P3 |
| `trailing-whitespace` | Trailing whitespace | P3 |
| `eslint` or `deno lint` | JavaScript code quality issues | P2 |
| `prettier` or `deno fmt` | JavaScript formatting issues | P2 |
| `markdownlint` | Markdown formatting issues | P3 |

---

## Summary: CI Checks

| Check | What it validates | Blocking? |
|--------|-------------------|-----------|
| Betterleaks | Full repo history scan for secrets | Yes |
| Shellcheck | All `.sh` files | Yes |
| shfmt | Shell formatting | Yes |
| Yamllint | All YAML files | Yes |
| Ruff | Python lint + format | Yes |
| JSON syntax | All `.json` files | Yes |
| Test suite | `tests/run-all.sh` (7 categories) | Yes |
| Docker compose | `docker compose config` + image pinning | Soft-fail |
| Hadolint | Dockerfile linting | Soft-fail |

---

## Potential Risks and Mitigations

1. **Pre-commit hooks slow down developer workflow**
   Mitigation: Pre-commit runs only on staged files by default. Betterleaks and shellcheck are fast (<2s on changed files). The full CI script runs only in CI, not locally.

2. **False positives from betterleaks block legitimate commits**
   Mitigation: Use `.betterleaksignore` for known false positives. Use `# betterleaks:allow` inline comments for test fixtures. Establish a clean baseline first. Explicitly allowlist `.env.example` files.

3. **Inline Python in shell heredocs is hard to validate**
   Mitigation: Extract between heredoc markers and pipe to `py_compile`. Accept that this catches syntax errors but not runtime errors. This is still better than the current state (zero validation).

4. **Adding `package.json` conflicts with the project's zero-dependency philosophy**
   Mitigation: Prefer `deno lint`/`deno fmt` or bare `npx` calls. Only add `package.json` if deno is not acceptable. The plan defaults to deno.

5. **UCI validation is custom and not tool-supported**
   Mitigation: Write a focused ~50-line bash script that checks UCI syntax patterns (`config`/`option`/`list` lines) and cross-references hostnames. This is sufficient for catching the most common errors (typos, missing sections, wrong node references).

6. **CI platform is unknown**
   Mitigation: Create `scripts/ci-run.sh` as a platform-agnostic entry point. The platform-specific workflow file is a thin wrapper that calls this script. This avoids locking into a platform prematurely.

---

## Alternative Approaches

1. **Replace inline Python schema checks with JSON Schema**: Would be more formal and tool-supported, but would duplicate the existing 629 lines of thorough checks in `tests/03-schema.sh`. **Deferred** — revisit if inline checks become unmaintainable.

2. **Skip pre-commit, rely only on CI**: Lower friction for contributors. Trade-off: secrets can be pushed to remote before CI catches them. **Not recommended** given the security sensitivity of this project.

3. **Use `pre-commit run --all-files` as the only CI step**: Simpler CI config but less granular failure reporting. **Acceptable for early stages** — can split into separate jobs later.

4. **Use `deno lint`/`deno fmt` instead of eslint/prettier**: Avoids `package.json` entirely. Trade-off: deno must be installed. **Recommended** for this project.

---

## Implementation Order

```text
Phase 1  (P0): Secret prevention + pre-commit framework     ← do this first
Phase 2  (P1): Shell script quality (shellcheck + shfmt)
Phase 3  (P1): Configuration validation (yamllint + UCI + env consistency + Docker)
Phase 10 (P1): CI runner script (can be done in parallel with Phase 2-3)
Phase 9  (P1): Test coverage expansion (UCI, inline Python, PowerShell, HTML)
Phase 4  (P2): Python quality (ruff + unit tests)
Phase 5  (P2): JavaScript quality (lint + format; unit tests deferred)
Phase 6  (P2): JSON validation
Phase 7  (P2): Docker quality (hadolint)
Phase 8  (P3): Markdown quality
```

---

## Changes from v1

| v1 Issue | v2 Change |
|----------|-----------|
| `.gitignore` gaps labeled P0 | Downgraded to P1 — existing `.env.*` catch and test suite already cover most cases |
| JSON Schema files (Phase 3.2) | Removed — existing inline checks in `tests/03-schema.sh` are thorough; deferred to avoid duplication |
| JavaScript `package.json` + eslint + prettier | Replaced with `deno lint`/`deno fmt` preference; `package.json` only as fallback |
| JavaScript unit tests for Telegram adapter | Deferred — adapter reads env vars and makes HTTP calls; test when API stabilizes |
| DRY refactoring of HTTP helpers (Phase 5.4) | Removed — it's a refactor, not a guardrail |
| Link validation with lychee | Replaced with a simple bash-based internal link checker |
| `tests/07-shellcheck.sh` | Removed — duplicates pre-commit + CI; test suite should only contain non-duplicated checks |
| CI assumes GitHub Actions | Replaced with CI-agnostic `scripts/ci-run.sh`; platform workflow is a thin wrapper |
| Docker pinning as a script | Replaced with a 1-liner grep |
| "Coverage > 80%" criterion | Changed to "every public function has at least one test case" |
| Missing `bootstrap.mjs` in syntax list | Added explicitly in Phase 4.2 |
| Missing `bootstrap.ps1` coverage | Added Phase 9.2 |
| Missing UCI config validation | Added Phase 3.2 with custom validation |
| Missing `.env.example` consistency check | Added Phase 3.3 |
| Missing homer `.env.example` check | Added to Phase 3.3 |
| Missing `no-commit-to-branch` task | Added explicitly in Phase 1.2 |
| `set -euo pipefail` check should exclude `tests/` | Noted exclusion in Phase 2.3 |
| Missing HTML fixture validation | Added Phase 9.3 |
