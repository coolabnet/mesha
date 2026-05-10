# Mesha Guardrails — Pre-Commit and CI Implementation Tracker

**Created:** 2026-04-12
**Status:** Planning
**Source analysis:** Full project scan (196 files, 13 file types)

---

## Objective

Implement automated quality and safety guardrails for the Mesha project covering: secret leak prevention, shell script linting, YAML/JSON validation, Python and JavaScript code quality, Docker config validation, markdown consistency, and test coverage expansion. All guardrails run both as pre-commit hooks (developer-side) and CI checks (PR-side).

---

## Priority Legend

| Priority | Meaning |
|----------|---------|
| P0 — Critical | Security or safety risk. Must be implemented first. |
| P1 — High | Quality risk that could cause silent failures in production. |
| P2 — Medium | Improves maintainability and catches bugs early. |
| P3 — Low | Nice-to-have for consistency and polish. |

---

## Phase 1: Foundation (P0 — Critical)

### 1.1 Secret Leak Prevention with Betterleaks

**Rationale:** The project manages SSH keys to routers/servers, Telegram bot tokens, database credentials, and Tailscale auth keys. A leaked secret gives direct access to community infrastructure. The `.gitignore` is incomplete — it covers `secrets/*.key`, `secrets/*.pem`, `secrets/*.env` but misses `secrets/*.token`, `secrets/*.password`, `secrets/credentials`, and `*.private` which are all documented as required in `secrets/README.md:94-103`.

- [ ] Fix `.gitignore` gaps — add missing patterns from `secrets/README.md:94-103`:
  - `secrets/*.token`
  - `secrets/*.password`
  - `secrets/credentials`
  - `*.private`
- [ ] Create `.betterleaks.toml` config at project root extending default rules with project-specific allowlists:
  - Allow known test/placeholder values (e.g., `cafebabe`, `changeme` in test fixtures)
  - Allow `secrets/README.md` (contains example patterns)
  - Allow `.betterleaks.toml` itself
- [ ] Create `.betterleaksignore` baseline file (empty initially, populated after first scan)
- [ ] Run initial full-repo scan: `betterleaks dir -v .` — capture results into a baseline report
- [ ] Review initial findings — determine which are real secrets vs false positives
- [ ] Rotate any real secrets found in the initial scan immediately
- [ ] Add pre-commit hook for betterleaks (via `.pre-commit-config.yaml`)
- [ ] Add CI job: `betterleaks git -v --baseline-path .betterleaksignore` on every PR (requires `fetch-depth: 0`)

**Verification:**

- [ ] `betterleaks dir .` returns exit code 0 after baseline is established
- [ ] Intentionally stage a fake API key and verify the pre-commit hook blocks it
- [ ] Verify `.gitignore` rejects `secrets/*.token`, `secrets/*.password`, `*.private` files

---

### 1.2 Pre-Commit Framework Setup

**Rationale:** No `.pre-commit-config.yaml` exists. This is the foundation that all other hooks depend on.

- [ ] Create `.pre-commit-config.yaml` with the initial set of hooks (detailed per-section below)
- [ ] Add `pre-commit` to project setup instructions (README or BOOTSTRAP)
- [ ] Document how to install: `pip install pre-commit && pre-commit install`
- [ ] Add `pre-commit run --all-files` to CI as a job

**Verification:**

- [ ] `pre-commit run --all-files` passes on a clean checkout
- [ ] `.pre-commit-config.yaml` is valid YAML

---

## Phase 2: Shell Script Quality (P1 — High)

**Rationale:** 36 shell scripts run critical operations — `sysupgrade` on routers, Docker management on servers, SSH into production devices. A bug in `skills/mesh-rollout/scripts/run-rollout.sh` could brick community routers. The current syntax check in `tests/02-syntax.sh:22-75` uses a hardcoded file list — new scripts won't be caught.

### 2.1 Shellcheck Integration

- [ ] Add `shellcheck-py` hook to `.pre-commit-config.yaml` targeting all `.sh` files
- [ ] Configure `args: ["--severity=warning"]` — warnings are non-blocking in pre-commit, errors block
- [ ] Fix existing shellcheck warnings across all 36 `.sh` files (expected: SC2086, SC2155, SC2034, SC1090, SC1091 are common)
- [ ] Add `# shellcheck disable=SCXXXX` directives where false positives are confirmed
- [ ] Add CI job: `find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck --severity=warning --format=json` with SARIF or JUnit output for PR annotations

**Verification:**

- [ ] `shellcheck --severity=error` passes on all `.sh` files
- [ ] `shellcheck --severity=warning` passes or has documented suppressions
- [ ] New `.sh` files are automatically caught (no hardcoded list)

### 2.2 Shell Formatting (shfmt)

- [ ] Add `shfmt` hook to `.pre-commit-config.yaml`
- [ ] Configure: indent 2 spaces, simplify, binary-next-line
- [ ] Run `shfmt -w` on all existing `.sh` files to normalize formatting
- [ ] Add CI check: `shfmt -d .` (diff mode, fails if formatting differs)

**Verification:**

- [ ] `shfmt -d .` returns no output (all files formatted)

### 2.3 Auto-Discovery of Shell Scripts

- [ ] Replace hardcoded file list in `tests/02-syntax.sh:24-58` with `find . -name '*.sh' -not -path './.git/*'`
- [ ] Add a new test case: detect `.sh` files not marked executable that should be (heuristic: files with `#!/bin/bash` or `#!/bin/sh` shebang)
- [ ] Add a new test case: detect `.sh` files missing `set -euo pipefail` (or `set -uo pipefail` with justification comment)

**Verification:**

- [ ] Adding a new `.sh` file anywhere in the tree is caught by the syntax test without manual list updates

---

## Phase 3: YAML and Configuration Validation (P1 — High)

**Rationale:** 29+ YAML files form the foundation of the safety model. `mesh-nodes.yaml` cross-references `sites.yaml` and `gateways.yaml`. If these break, the planner agent makes incorrect decisions about node upgrades. The current schema checks in `tests/03-schema.sh` use inline Python assertions that are fragile and tightly coupled to specific files.

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
- [ ] Add CI job: `yamllint -f parsable .`

**Verification:**

- [ ] `yamllint .` returns exit code 0

### 3.2 JSON Schema Definitions

- [ ] Create `schemas/` directory with formal JSON Schema files for:
  - [ ] `schemas/mesh-nodes.schema.json` — validates `inventories/mesh-nodes.yaml`
  - [ ] `schemas/sites.schema.json` — validates `inventories/sites.yaml`
  - [ ] `schemas/gateways.schema.json` — validates `inventories/gateways.yaml`
  - [ ] `schemas/service-catalog.schema.json` — validates `desired-state/server/service-catalog.yaml`
  - [ ] `schemas/firmware-policy.schema.json` — validates `desired-state/mesh/firmware-policy.yaml`
  - [ ] `schemas/domains.schema.json` — validates `desired-state/server/domains.yaml`
- [ ] Add schema validation to `tests/03-schema.sh` using `python3 -c "import jsonschema; ..."` or `check-jsonschema`
- [ ] Add CI job: `check-jsonschema --schemafile schemas/mesh-nodes.schema.json inventories/mesh-nodes.yaml` (repeat for each)
- [ ] Document schema files in BOOTSTRAP.md or TOOLS.md

**Verification:**

- [ ] Each inventory/desired-state YAML file validates against its schema
- [ ] Intentionally breaking a schema (e.g., removing a required field) causes test failure

### 3.3 Docker Compose Validation

- [ ] Add CI job: validate all `docker-compose*.y*ml` files with `docker compose -f <file> config --quiet`
- [ ] Mark as allowed-failure in CI if Docker daemon is unavailable (use conditional)
- [ ] Check that all Docker images use pinned tags (not `latest`) — add a script or CI step

**Verification:**

- [ ] `docker compose config` passes for all compose files
- [ ] No Docker image uses `latest` tag

---

## Phase 4: Python Code Quality (P2 — Medium)

**Rationale:** 7+ Python files including the critical `adapters/mesh/normalize.py` (353 lines) which normalizes node data and computes configuration drift. Currently only `normalize.py` has a syntax check — the 6 helper scripts in `skills/mesh-rollout/scripts/helpers/` are untested. Inline Python in shell heredocs is completely untested.

### 4.1 Ruff Linting and Formatting

- [ ] Add `ruff-pre-commit` hook to `.pre-commit-config.yaml` with `ruff check` and `ruff format --check`
- [ ] Create `pyproject.toml` (or `ruff.toml`) with minimal config:

  ```toml
  [tool.ruff]
  target-version = "py311"
  line-length = 120

  [tool.ruff.lint]
  select = ["E", "F", "W", "I", "UP", "B", "SIM"]
  ```

- [ ] Run `ruff check --fix` on all `.py` files
- [ ] Run `ruff format` on all `.py` files
- [ ] Add CI job: `ruff check . && ruff format --check .`

**Verification:**

- [ ] `ruff check .` returns no findings
- [ ] `ruff format --check .` passes

### 4.2 Expand Syntax Check Coverage

- [ ] Add all 6 helper scripts in `skills/mesh-rollout/scripts/helpers/` to the Python syntax check in `tests/02-syntax.sh`
- [ ] Add auto-discovery: `find . -name '*.py' -not -path './.git/*' -not -path './.venv/*'`
- [ ] Add a test to extract and validate inline Python in shell heredocs:
  - `adapters/mesh/collect-nodes.sh:163-277` (embedded Python)
  - `skills/mesh-rollout/scripts/run-rollout.sh:426-433` (inline Python via heredoc)

**Verification:**

- [ ] All `.py` files pass `py_compile` (auto-discovered, not hardcoded)
- [ ] Inline Python in heredocs is extracted and syntax-validated

### 4.3 Unit Tests for normalize.py

- [ ] Create `tests/unit/test_normalize.py` using pytest or unittest (no heavy framework)
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
- [ ] Add CI job: `python3 -m pytest tests/unit/ -v`

**Verification:**

- [ ] All unit tests pass
- [ ] Coverage of core functions > 80%

### 4.4 Unit Tests for Rollout Helpers

- [ ] Create `tests/unit/test_parse_rings.py` — test ring parsing with fixture YAML data
- [ ] Create `tests/unit/test_parse_ring_nodes.py` — test node-to-ring mapping
- [ ] Create `tests/unit/test_check_change_window.py` — test time window validation logic
- [ ] Add fixture data files in `tests/fixtures/` with sample YAML configs

**Verification:**

- [ ] All helper unit tests pass

---

## Phase 5: JavaScript Code Quality (P2 — Medium)

**Rationale:** 3 `.mjs` files totaling ~1,136 lines. `adapter.mjs` (624 lines) handles Telegram bot trust levels, rate limiting, and message routing — zero unit tests. `health.mjs` duplicates HTTP helpers from `adapter.mjs`. No `package.json` exists (intentional), but this limits tooling options.

### 5.1 ESLint Setup

- [ ] Create a minimal `package.json` with only devDependencies:

  ```json
  {
    "private": true,
    "type": "module",
    "devDependencies": {
      "eslint": "^9.x",
      "@eslint/js": "^9.x"
    }
  }
  ```

- [ ] Create `eslint.config.mjs` with minimal rules:
  - No unused variables
  - No console in production paths (warn)
  - Consistent style
  - ES module support
- [ ] Run `npx eslint --fix` on all `.mjs` files
- [ ] Add pre-commit hook for eslint on `.mjs` files
- [ ] Add CI job: `npx eslint .`

**Verification:**

- [ ] `npx eslint .` returns no errors

### 5.2 Prettier Formatting

- [ ] Add `prettier` to `package.json` devDependencies
- [ ] Create `.prettierrc` with minimal config
- [ ] Run `npx prettier --write` on all `.mjs` files
- [ ] Add pre-commit hook for prettier
- [ ] Add CI check: `npx prettier --check .`

**Verification:**

- [ ] `npx prettier --check .` passes

### 5.3 Unit Tests for Telegram Adapter

- [ ] Create `tests/unit/test_adapter.mjs` using Node's built-in `node:test` runner (no external deps)
- [ ] Test `determineTrustLevel()` — verify each trust tier (DM, group, public)
- [ ] Test `normalizeMessage()` — various message types and edge cases
- [ ] Test `maskToken()` — verify token is properly masked for logging
- [ ] Test rate limit backoff logic
- [ ] Add CI job: `node --test tests/unit/test_adapter.mjs`

**Verification:**

- [ ] All adapter unit tests pass

### 5.4 DRY Refactoring (follow-up)

- [ ] Extract shared HTTP helpers from `adapter.mjs` and `health.mjs` into `adapters/channels/telegram/http-helpers.mjs`
- [ ] Update both files to import from shared module
- [ ] Verify no behavioral change

**Verification:**

- [ ] Existing tests still pass
- [ ] No duplicated HTTP helper code

---

## Phase 6: JSON Validation (P2 — Medium)

**Rationale:** 13 JSON files including `adapters/mesh/field_map.json` which maps raw node data to canonical fields. Invalid mappings silently fail at runtime.

### 6.1 JSON Syntax Validation

- [ ] Add `check-json` hook from `pre-commit-hooks` to `.pre-commit-config.yaml`
- [ ] Add CI job: `find . -name '*.json' -not -path './.git/*' -not -path './node_modules/*' | xargs python3 -m json.tool --no-ensure-ascii > /dev/null`

**Verification:**

- [ ] All `.json` files parse without error

### 6.2 field_map.json Schema Validation

- [ ] Create `schemas/field-map.schema.json` — validate that mapped canonical fields exist in the inventory schema
- [ ] Add cross-reference check: every field in `field_map.json` maps to a field defined in `schemas/mesh-nodes.schema.json`
- [ ] Add to CI as a schema validation step

**Verification:**

- [ ] Invalid field mappings are caught by CI

---

## Phase 7: Docker Quality (P2 — Medium)

**Rationale:** Dockerfiles in `docker/onboarding-test/` and 6+ docker-compose files. No linting for Dockerfile best practices.

### 7.1 Dockerfile Linting (hadolint)

- [ ] Add hadolint pre-commit hook (or CI-only if hadolint is hard to install locally)
- [ ] Run hadolint on all Dockerfiles
- [ ] Fix or suppress findings

**Verification:**

- [ ] `hadolint Dockerfile` passes for all Dockerfiles

### 7.2 Docker Image Pinning Check

- [ ] Create a small script or CI step that greps docker-compose files for `image:.*:latest` or unpinned tags
- [ ] Fail CI if any image uses `latest` or has no tag

**Verification:**

- [ ] No Docker image uses `latest` tag

---

## Phase 8: Markdown Quality (P3 — Low)

**Rationale:** 46 `.md` files form the project's core documentation and agent instructions. Broken cross-references or inconsistent formatting reduces maintainability.

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
- [ ] Add CI job: `markdownlint .`

**Verification:**

- [ ] `markdownlint .` returns no errors

### 8.2 Link Validation

- [ ] Add CI job using `lychee` or `markdown-link-check` for internal link validation
- [ ] Configure to check only relative/internal links (not external URLs — the project must work offline)
- [ ] Add a check that all documents referenced in README.md and BOOTSTRAP.md exist as files

**Verification:**

- [ ] No broken internal links in any `.md` file

---

## Phase 9: Test Coverage Expansion (P1 — High)

**Rationale:** The existing test suite covers file inventory, syntax, schema, dry-run smoke tests, and health checks. Missing: secret scanning, shellcheck, formal schema validation, unit tests for Python/JS modules, Docker validation, and heredoc Python validation.

### 9.1 New Test Categories

- [ ] Create `tests/06-secret-scan.sh` — run `betterleaks dir .` and fail on findings not in baseline
- [ ] Create `tests/07-shellcheck.sh` — run `shellcheck --severity=warning` on all discovered `.sh` files
- [ ] Create `tests/08-unit-tests.sh` — run Python unit tests (`pytest tests/unit/`) and Node unit tests (`node --test tests/unit/`)
- [ ] Create `tests/09-docker-validate.sh` — validate docker-compose files with `docker compose config`
- [ ] Create `tests/10-new-files.sh` — detect new `.sh`, `.py`, `.mjs`, `.yaml` files not covered by existing checks (meta-test)
- [ ] Update `tests/run-all.sh` to include new test categories 06-10

**Verification:**

- [ ] `bash tests/run-all.sh` runs all 10 categories and passes

### 9.2 Inline Python Validation

- [ ] Create a test helper that extracts Python code from shell heredocs and validates syntax
- [ ] Target files: `adapters/mesh/collect-nodes.sh:163-277`, `skills/mesh-rollout/scripts/run-rollout.sh:426-433`
- [ ] Add to `tests/02-syntax.sh` or create `tests/11-inline-python.sh`

**Verification:**

- [ ] Syntax errors in inline Python are caught

---

## Phase 10: CI Pipeline (P1 — High)

**Rationale:** No CI pipeline exists. All quality checks are manual. PRs can merge without any automated validation.

### 10.1 GitHub Actions Workflow

- [ ] Create `.github/workflows/qa.yml` with the following jobs:

  **Job: lint**
  - `shellcheck` on all `.sh` files
  - `yamllint` on all YAML files
  - `ruff check` and `ruff format --check` on all `.py` files
  - `npx eslint .` on all `.mjs` files
  - `npx prettier --check .` on all `.mjs` files
  - JSON validation on all `.json` files

  **Job: test**
  - Run `bash tests/run-all.sh` (all 10 categories)
  - Upload test results as artifacts

  **Job: secrets**
  - Run `betterleaks git --baseline-path .betterleaksignore` with `fetch-depth: 0`
  - Upload SARIF report

  **Job: schema**
  - Run `check-jsonschema` for all inventory and desired-state files against their schemas
  - Validate docker-compose files

  **Job: docker** (optional, requires Docker)
  - `hadolint` on all Dockerfiles
  - `docker compose config` on all compose files
  - Docker image pinning check

- [ ] Configure branch protection: require all jobs to pass before merge
- [ ] Configure the `qa.yml` workflow to run on `push` to `main` and on all `pull_request` events

**Verification:**

- [ ] CI pipeline runs on every PR
- [ ] All jobs pass on a clean branch
- [ ] Intentionally breaking a file causes the correct CI job to fail

### 10.2 CI Dependencies

- [ ] Ensure CI runner has: `shellcheck`, `shfmt`, `yamllint`, `ruff`, `betterleaks`, `node`, `python3`, `docker` (optional)
- [ ] Cache `node_modules` and `pip` packages between runs
- [ ] Document CI requirements in a contributor guide

**Verification:**

- [ ] CI pipeline completes in under 5 minutes on a clean run

---

## Summary: Pre-Commit Hook Checklist

The final `.pre-commit-config.yaml` should include these hooks:

| Hook | What it catches | Priority |
|------|----------------|----------|
| `betterleaks` | Accidentally staged secrets, API keys, tokens | P0 |
| `shellcheck` | Shell script bugs, unsafe patterns | P1 |
| `shfmt` | Inconsistent shell formatting | P1 |
| `yamllint` | YAML syntax and style issues | P1 |
| `ruff` (check + format) | Python lint and formatting issues | P2 |
| `check-json` | Malformed JSON files | P2 |
| `check-yaml` | Malformed YAML files (additional layer) | P2 |
| `detect-private-key` | Accidentally staged SSH keys | P0 |
| `check-merge-conflict` | Unresolved merge conflict markers | P2 |
| `no-commit-to-branch` | Direct commits to `main` | P1 |
| `end-of-file-fixer` | Missing newlines at EOF | P3 |
| `trailing-whitespace` | Trailing whitespace | P3 |
| `eslint` | JavaScript code quality issues | P2 |
| `prettier` | JavaScript formatting issues | P2 |
| `markdownlint` | Markdown formatting issues | P3 |

---

## Summary: CI Job Checklist

| CI Job | What it validates | Blocking? |
|--------|-------------------|-----------|
| `lint` | shellcheck, yamllint, ruff, eslint, prettier, JSON | Yes |
| `test` | Full test suite (tests/run-all.sh) | Yes |
| `secrets` | betterleaks full history scan | Yes |
| `schema` | JSON Schema for all inventory/desired-state files | Yes |
| `docker` | hadolint, compose config, image pinning | Soft-fail |

---

## Potential Risks and Mitigations

1. **Pre-commit hooks slow down developer workflow**
   Mitigation: Use `pre-commit` with `--from-ref HEAD --to-ref HEAD` for speed. Configure hooks to run only on changed files. Betterleaks and shellcheck are fast (<2s on changed files).

2. **False positives from betterleaks block legitimate commits**
   Mitigation: Use `.betterleaksignore` for known false positives. Use `# betterleaks:allow` inline comments for test fixtures. Establish a clean baseline first.

3. **CI requires tools not available in standard GitHub Actions runners**
   Mitigation: Use GitHub Actions marketplace actions for shellcheck, hadolint, betterleaks. Install remaining tools via pip/npm in the workflow. Cache aggressively.

4. **Inline Python in shell heredocs is hard to validate**
   Mitigation: Write a small extraction script that pulls Python from between heredoc markers and pipes it to `py_compile`. Accept that this won't catch runtime errors.

5. **No `package.json` philosophy conflicts with adding npm devDependencies**
   Mitigation: The minimal `package.json` is dev-only with `"private": true`. It does not change the project's runtime dependency model. Alternative: use `npx` without a `package.json` (works but slower).

6. **Schema definitions may be too rigid for a project that evolves**
   Mitigation: Use `"additionalProperties": true` in JSON Schema to allow new fields. Version schemas alongside the files they validate. Schema changes should be part of the normal PR review.

---

## Alternative Approaches

1. **Skip pre-commit, rely only on CI**: Lower friction for contributors who don't install hooks. Trade-off: slower feedback loop, secrets can be pushed to remote before CI catches them. **Not recommended** given the security sensitivity.

2. **Use `pre-commit` as the only CI runner**: Run `pre-commit run --all-files` in CI instead of separate jobs. Trade-off: simpler CI config but less granular failure reporting and no SARIF/annotation integration. **Acceptable for early stages**.

3. **Use `ruff` only for Python, skip mypy**: The project uses Python as a helper language, not a primary one. Full type checking may be overkill. **Recommended** — defer mypy until the Python codebase grows.

4. **Use `deno lint` instead of eslint**: Avoids the need for `package.json` entirely. Trade-off: deno's lint rules are less configurable. **Consider if adding `package.json` is undesirable**.

---

## Implementation Order

```text
Phase 1  (P0): Secret prevention + pre-commit framework     ← do this first
Phase 2  (P1): Shell script quality (shellcheck + shfmt)
Phase 3  (P1): YAML validation (yamllint + JSON Schema)
Phase 10 (P1): CI pipeline (can be done in parallel with Phase 2-3)
Phase 9  (P1): Test coverage expansion
Phase 4  (P2): Python quality (ruff + unit tests)
Phase 5  (P2): JavaScript quality (eslint + prettier + unit tests)
Phase 6  (P2): JSON validation
Phase 7  (P2): Docker quality
Phase 8  (P3): Markdown quality
```
