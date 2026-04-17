# Mesha Guardrails — Pre-Commit and CI Implementation Tracker

**Created:** 2026-04-12
**Revised:** 2026-04-13 (v4 — implemented all phases; Docker images pinned; plan status updated)
**Status:** Implemented
**Source analysis:** Full project scan (196 files, 13 file types)

---

## Objective

Implement automated quality and safety guardrails for the Mesha project covering: secret leak prevention, shell script linting, YAML/JSON/UCI validation, Python and JavaScript code quality, Docker config validation, and targeted test coverage expansion. All guardrails run both as pre-commit hooks (developer-side) and CI checks (PR-side).

---

## Priority Legend

| Priority | Meaning | Effort |
|----------|---------|--------|
| P0 — Critical | Security risk. Must be implemented first. | S/M |
| P1 — High | Quality risk that could cause silent failures in production. | S/M/L |
| P2 — Medium | Improves maintainability and catches bugs early. | S/M |
| P3 — Low | Nice-to-have for consistency and polish. | S |

Effort key: S = under 1 hour, M = 1–4 hours, L = 4+ hours.

---

## Project Context

- **Betterleaks is already installed and configured.** Commit `91cdc39` added `.pre-commit-config.yaml` with betterleaks v1.1.2. The `pre-commit` framework (v4.5.1) and `betterleaks` binary are installed. The git hook is active at `.git/hooks/pre-commit`.
- **No `.betterleaks.toml` config or `.betterleaksignore` baseline exists yet.** The tool runs with default rules only.
- **Baseline scan result:** `betterleaks dir .` found 1 finding — a Telegram bot token in `adapters/channels/telegram/.env:9` (local only, not committed, not in git history). Git history scan (`betterleaks git .`) is clean — no leaks in 24 commits.
- **No CI platform is chosen yet.** The plan provides a CI-agnostic runner script.
- **No `package.json`.** The project intentionally avoids npm dependencies.
- **Must work offline.** Guardrails must not require internet access during execution.
- **Custom test suite.** `tests/run-all.sh` runs 5 categories. New guardrails integrate into this framework.
- **UCI config files.** The project manages OpenWrt UCI configs that get pushed to production routers.

---

## Sprint 1: Security and Foundations (P0–P1)

### Phase 1: Secret Prevention + Pre-Commit Framework (P0) — PARTIALLY DONE

#### 1.1 Betterleaks — DONE (installed, needs config and baseline) — Effort: S

**Already completed:**

- [x] Betterleaks installed (`/home/linuxbrew/.linuxbrew/bin/betterleaks`, v1.1.2)
- [x] `.pre-commit-config.yaml` created with betterleaks hook (commit `91cdc39`)
- [x] `pre-commit` framework installed (v4.5.1)
- [x] Git pre-commit hook active (`.git/hooks/pre-commit`)
- [x] Git history clean — `betterleaks git .` reports no leaks in 24 commits

**Remaining work:**

- [x] Fix `.gitignore` gaps — added missing patterns from `secrets/README.md:94-103`:
  - `secrets/*.token`
  - `secrets/*.password`
  - `secrets/credentials`
  - `*.private`
- [x] Create `.betterleaks.toml` config at project root:
  - Extended default rules (`useDefault = true`)
  - Added global allowlist for `.env.example` files
  - Added global allowlist for `secrets/README.md`
  - Added global allowlist for `.betterleaks.toml` itself
  - Added global allowlist for test fixture files in `docker/`
- [x] Create `.betterleaksignore` baseline file (empty — git history is clean)
- [x] Verified the local `.env` file with the Telegram token is NOT staged — confirmed local-only
- [x] Added CI job: `betterleaks git -v --baseline-path .betterleaksignore` in `scripts/ci-run.sh`

**Verification:**

- [x] `betterleaks git .` returns exit code 0 (git history clean)
- [x] `betterleaks dir .` returns 1 finding (the local `.env`) — expected and acceptable (file is gitignored)
- [x] Intentionally stage a fake API key and verify the pre-commit hook blocks it
- [x] `.env.example` files do not trigger false positives

#### 1.2 Pre-Commit Framework — DONE (installed, needs additional hooks) — Effort: S

**Already completed:**

- [x] `.pre-commit-config.yaml` created
- [x] `pre-commit` framework installed
- [x] Git hook active

**Remaining work:**

- [x] Add `no-commit-to-branch` hook targeting `main` branch to `.pre-commit-config.yaml`
- [x] Add `detect-private-key` hook from `pre-commit-hooks`
- [x] Add `check-merge-conflict` hook
- [x] Add `check-executables-have-shebangs` hook — catches scripts with shebangs that aren't executable
- [x] Add `check-shebang-scripts-are-executable` hook — catches executable scripts without shebangs
- [x] Add `end-of-file-fixer` and `trailing-whitespace` hooks
- [x] Add `pre-commit` install instructions to `CONTRIBUTING.md`
- [x] Add `pre-commit run --all-files` to CI runner (`scripts/ci-run.sh`)

**Verification:**

- [x] `pre-commit run --all-files` passes on a clean checkout
- [x] Direct commit to `main` is blocked by the hook

#### 1.3 Foundational Config Files — Effort: S

- [x] Create `.editorconfig` at project root

  ```ini
  root = true

  [*]
  charset = utf-8
  end_of_line = lf
  insert_final_newline = true
  trim_trailing_whitespace = true
  indent_style = space
  indent_size = 2

  [*.sh]
  indent_style = space
  indent_size = 2

  [*.py]
  indent_style = space
  indent_size = 4

  [*.yaml]
  indent_style = space
  indent_size = 2
  ```

- [x] Create `.gitattributes` at project root

  ```text
  * text=auto eol=lf
  *.sh text eol=lf
  *.mjs text eol=lf
  *.py text eol=lf
  *.yaml text eol=lf
  *.yml text eol=lf
  *.json text eol=lf
  *.md text eol=lf
  *.toml text eol=lf
  ```

- [x] (Skipped) `editorconfig-checker` hook — not added (optional per plan)

**Verification:**

- [x] `.editorconfig` is present and consistent with formatter configs (shfmt indent 2, ruff indent 4)
- [x] `.gitattributes` ensures LF line endings on checkout regardless of OS

---

### Phase 2: Shell Script Quality (P1) — Effort: M

**Rationale:** 36 shell scripts run critical operations — `sysupgrade` on routers, Docker management on servers, SSH into production devices. The current syntax check in `tests/02-syntax.sh:24-58` uses a hardcoded list of 34 files — at least 6 scripts are missing from the list (`schedule-maintenance.sh`, `docker/phase1/mock-node/entrypoint.sh`, `tests/01-file-inventory.sh`, `tests/03-schema.sh`, `tests/04-dryrun.sh`, `tests/05-healthchecks.sh`). New scripts added to the repo won't be caught.

#### 2.1 Shellcheck Integration — Effort: M

- [x] Add `shellcheck-py` hook to `.pre-commit-config.yaml` targeting all `.sh` files
- [x] Configure `args: ["--severity=warning"]`
- [x] Fix existing shellcheck warnings across all `.sh` files
- [x] Add `# shellcheck disable=SCXXXX` directives where false positives are confirmed
- [x] Add CI step in `scripts/ci-run.sh`
- [x] `scripts/discover-from-thisnode.sh` reviewed — shellcheck clean

**Verification:**

- [x] `shellcheck --severity=error` passes on all `.sh` files
- [x] `shellcheck --severity=warning` passes or has documented suppressions

#### 2.2 Shell Formatting (shfmt) — Effort: S

- [x] Add `shfmt` hook to `.pre-commit-config.yaml`
- [x] Configure: indent 2 spaces (matching `.editorconfig`), simplify (`-s`), binary-next-line (`-bn`)
- [x] Run `shfmt -w` on all existing `.sh` files to normalize formatting
- [x] Add CI check in `scripts/ci-run.sh`

**Verification:**

- [x] `shfmt -d .` returns no output (all files formatted)

#### 2.3 Auto-Discovery and Safety Checks — Effort: S

- [x] Replace hardcoded file list in `tests/02-syntax.sh` with auto-discovery using `find`
- [x] Add shebang/executable consistency check (excluding `docker/**/bin/*` fake binaries and `.claude/`)
- [x] Add shebang-aware `set -e` check for `.sh` files outside `tests/`:
  - Bash scripts: must have `set -euo pipefail`
  - POSIX sh scripts: must have `set -e` (pipefail is a bashism)
  - Files with `set -uo pipefail` or `set -e` only have `# reason:` comments
  - `tests/` files excluded from this check
  - Known POSIX sh scripts annotated with `# reason:` comments

**Verification:**

- [x] Adding a new `.sh` file anywhere in the tree is caught by the syntax test without manual list updates
- [x] POSIX sh scripts are not flagged for missing `pipefail`

---

### Phase 3: Configuration Validation (P1) — Effort: M

**Rationale:** 29+ YAML files, 2+ UCI files, and 13 JSON files form the foundation of the safety model. Cross-references between `mesh-nodes.yaml`, `sites.yaml`, and `gateways.yaml` could break silently. The existing `tests/03-schema.sh` (629 lines) already provides thorough inline Python validation — this phase adds tool-based linting and fills gaps, rather than replacing what works.

#### 3.1 Yamllint — Effort: S

- [x] Create `.yamllint` configuration file
- [x] Add `yamllint` hook to `.pre-commit-config.yaml`
- [x] Fix existing yamllint warnings across all YAML files
- [x] Add CI step in `scripts/ci-run.sh`

**Verification:**

- [x] `yamllint .` returns exit code 0

#### 3.2 UCI Config Validation — Effort: S

**Rationale:** The project manages OpenWrt UCI configuration files (`desired-state/mesh/community-profile/lime-community` and `desired-state/mesh/node-overrides/*.uci`) that get pushed to production routers. These use the UCI format (`config <type> '<name>'` / `option <key> '<value>'` / `list <key> '<value>'`). A malformed UCI file pushed to a router could break its network configuration.

**Pre-existing inventory gap (must resolve before verification passes):** The only `.uci` file in the repo — `desired-state/mesh/node-overrides/lm-escola-telhado.uci` — sets `option hostname 'lm-escola-telhado'`. Per `desired-state/mesh/node-overrides/README.md:41`, the hostname must match a node in `inventories/mesh-nodes.yaml`. However, `mesh-nodes.yaml` currently has only 4 nodes (`porao`, `yuri`, `marie`, `carlinhos`) — `lm-escola-telhado` is not among them. This is a pre-existing inventory gap: the node override was created but the inventory was never updated. The UCI cross-reference check will correctly catch this failure.

- [x] **Prerequisite resolved:** `lm-escola-telhado` added to `inventories/mesh-nodes.yaml`, `gateways.yaml`, and `sites.yaml` with correct cross-references
- [x] Create `tests/06-uci-validate.sh` that validates UCI files:
  - Checks `lime-community` syntax
  - Checks each `*.uci` file syntax
  - Cross-references hostnames against `mesh-nodes.yaml`
  - Checks no UCI file contains secrets
- [x] Register test 06 in `tests/run-all.sh` category registry

**Verification:**

- [x] All UCI files pass syntax validation
- [x] A `.uci` file referencing a nonexistent node is caught by the cross-reference check

#### 3.3 `.env.example` Consistency Check — Effort: S

**Rationale:** The schema test (`tests/03-schema.sh:567-620`) verifies that `.env.example` files exist alongside `docker-compose.yaml` files, but does not check that the variables listed in `.env.example` match what `docker-compose.yaml` and `install.sh` actually reference.

- [x] Add `.env.example` consistency check to `tests/03-schema.sh` (Section I)
- [x] Verified homer service has no `.env.example` — confirmed intentional (no env vars)

**Verification:**

- [x] A new `${SOME_VAR}` added to a `docker-compose.yaml` without a corresponding `.env.example` entry is caught

#### 3.4 Docker Compose Validation + Image Pinning — Effort: S

- [x] Add Docker compose validation step in `scripts/ci-run.sh` (soft-fail if Docker unavailable)
- [x] Add image pinning check (Section J in `tests/03-schema.sh`)
- [x] All Docker images pinned to specific versions (was `:latest`, now pinned)

**Verification:**

- [x] `docker compose config` passes for all compose files (when Docker available)
- [x] No Docker image uses `latest` or unpinned tag

---

### Phase 4: CI Pipeline (P1) — Effort: M

#### 4.1 CI-Agnostic Runner Script — Effort: M

- [x] Create `scripts/ci-run.sh` that runs all 8 quality checks in sequence
- [x] Script exits on first failure with clear error message
- [x] Script detects which tools are available and skips missing ones with a warning
- [x] Required tools documented in script header

**Verification:**

- [x] `bash scripts/ci-run.sh` passes on a clean checkout with all tools installed
- [x] `bash scripts/ci-run.sh` degrades gracefully when optional tools are missing

#### 4.2 Platform-Specific Workflow (when platform is chosen) — Effort: S

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

#### 4.3 Developer Onboarding — Effort: S

- [x] Create `CONTRIBUTING.md` explaining the guardrail system (all 5 sections)

**Verification:**

- [x] A new contributor can set up the development environment using only `CONTRIBUTING.md`

---

## Sprint 2: Code Quality (P2)

### Phase 5: Python Code Quality (P2) — Effort: M

**Rationale:** 7 Python files. `adapters/mesh/normalize.py` (353 lines) is the most complex module with zero dedicated tests. The 6 helper scripts in `skills/mesh-rollout/scripts/helpers/` are not in the syntax check list. The current check in `tests/02-syntax.sh:87-89` only covers `normalize.py`.

#### 5.1 Ruff Linting and Formatting — Effort: S

- [x] Add `ruff-pre-commit` hook to `.pre-commit-config.yaml` with `ruff check` and `ruff format --check`
- [x] Create `pyproject.toml` with ruff config
- [x] Run `ruff check --fix` on all `.py` files
- [x] Run `ruff format` on all `.py` files
- [x] Add CI step in `scripts/ci-run.sh`

**Verification:**

- [x] `ruff check .` returns no findings
- [x] `ruff format --check .` passes

#### 5.2 Expand Syntax Check Coverage — Effort: S

- [x] Replace hardcoded `PY_FILES` list in `tests/02-syntax.sh` with auto-discovery
- [x] Create `tests/07-inline-python.sh` that extracts and validates inline Python in shell heredocs
- [x] Register test 07 in `tests/run-all.sh` category registry

**Verification:**

- [x] All `.py` files pass `py_compile` (auto-discovered)
- [x] Inline Python in heredocs is extracted and syntax-validated

#### 5.3 Unit Tests for normalize.py — Effort: M

- [x] Create `tests/unit/test_normalize.py` using `unittest` (23 tests, all passing)
- [x] Test public functions: `normalize_node`, `compute_drift`, `_clean_mac`, `find_inventory_node`
- [x] Add CI step in `scripts/ci-run.sh`

**Verification:**

- [x] All unit tests pass (23/23)
- [x] Every public function in `normalize.py` has at least one test case

---

### Phase 6: JavaScript Code Quality (P2) — Effort: S

**Rationale:** 3 `.mjs` files totaling ~1,136 lines. No linting, no formatting enforcement. The project has no `package.json` (intentional) — tooling must work without one. Note: `scripts/bootstrap.mjs` is missing from the MJS syntax check list in `tests/02-syntax.sh:118-121` — only `adapter.mjs` and `health.mjs` are checked.

#### 6.1 Linting and Formatting (no package.json) — Effort: S

- [x] (Skipped — deno not installed) JS linting via `deno lint` / `deno fmt`
- [x] `scripts/bootstrap.mjs` added to MJS syntax check list in `tests/02-syntax.sh`
- [x] CI runner (`scripts/ci-run.sh`) handles deno gracefully when not installed

**Verification:**

- [x] (Deno not installed — deferred) Linting passes on all `.mjs` files
- [x] (Deno not installed — deferred) Formatting is consistent
- [x] `bootstrap.mjs` is included in ESM syntax checks

#### 6.2 Unit Tests for Telegram Adapter — DEFERRED

**Note:** Unit testing the Telegram adapter (`adapter.mjs`, 624 lines) is deferred because it reads from env vars and makes HTTP calls. Testing requires mocking infrastructure the project doesn't have.

- [ ] (Deferred) Create `tests/unit/test_adapter.mjs` using Node's built-in `node:test` runner
- [ ] (Deferred) Test `determineTrustLevel()`, `normalizeMessage()`, `maskToken()`
- [ ] (Deferred) Add CI step: `node --test tests/unit/test_adapter.mjs`

**When to un-defer:** When the adapter API stabilizes or when a bug is found that tests would have caught.

---

### Phase 7: JSON Validation (P2) — Effort: S

**Rationale:** 13 JSON files including `adapters/mesh/field_map.json` which maps raw node data to canonical fields. Invalid mappings silently fail at runtime.

#### 7.1 JSON Syntax Validation — Effort: S

- [x] Add `check-json` hook from `pre-commit-hooks` to `.pre-commit-config.yaml`
- [x] Add CI step in `scripts/ci-run.sh`

**Verification:**

- [x] All `.json` files parse without error

#### 7.2 field_map.json Cross-Reference — Effort: S

- [x] Add `field_map.json` cross-reference check to `tests/03-schema.sh` (Section K)

**Verification:**

- [x] An invalid field mapping in `field_map.json` is caught

---

## Sprint 3: Polish (P3)

### Phase 8: Markdown Quality (P3) — Effort: S

**Rationale:** 46 `.md` files. No validation. Cross-references between documents could break silently.

#### 8.1 Markdownlint — Effort: S

- [x] Add `markdownlint-cli` hook to `.pre-commit-config.yaml`
- [x] Create `.markdownlint.json` config
- [x] Run `markdownlint --fix` on all `.md` files
- [x] Add CI step in `scripts/ci-run.sh`

**Verification:**

- [x] `markdownlint .` returns no errors

#### 8.2 Internal Link Validation — DEFERRED

**Note:** Deferred. A bash-based link checker sounds simple but markdown link syntax is complex (nested brackets, escaped characters, reference-style links, image links). The existing stale-branding check in `tests/01-file-inventory.sh:183-230` provides some coverage. Revisit when link breakage becomes an actual problem.

---

### Phase 9: Test Coverage Expansion (P1, depends on Phases 3 and 5) — Effort: S

**Note:** Test files for categories 06 and 07 are created and registered as part of Phase 3.2 and Phase 5.2 respectively. This phase covers only the one remaining gap: PowerShell syntax validation.

#### 9.1 PowerShell Coverage — Effort: S

`scripts/bootstrap.ps1` is an actively maintained 197-line Windows onboarding tool (`#Requires -Version 5.0`, structured functions). It has no syntax validation anywhere in the test suite.

- [x] Add PowerShell syntax check to `tests/02-syntax.sh` using `pwsh -Command` parser
- [x] Skip with `qa_skip` if `pwsh` is not available

**Verification:**

- [x] `bootstrap.ps1` syntax is validated when `pwsh` is available
- [x] Test is gracefully skipped when `pwsh` is not installed

---

## Summary: Pre-Commit Hook Checklist

| Hook | What it catches | Priority | Status |
|------|----------------|----------|--------|
| `betterleaks` | Accidentally staged secrets | P0 | **DONE** |
| `detect-private-key` | Accidentally staged SSH keys | P0 | **DONE** |
| `no-commit-to-branch` (main) | Direct commits to main | P1 | **DONE** |
| `shellcheck` | Shell script bugs | P1 | **DONE** |
| `shfmt` | Shell formatting | P1 | **DONE** |
| `yamllint` | YAML style issues | P1 | **DONE** |
| `check-executables-have-shebangs` | Executables without shebangs | P1 | **DONE** |
| `check-shebang-scripts-are-executable` | Shebang scripts not executable | P1 | **DONE** |
| `ruff` (check + format) | Python lint/format | P2 | **DONE** |
| `check-json` | Malformed JSON | P2 | **DONE** |
| `check-merge-conflict` | Unresolved conflicts | P2 | **DONE** |
| `eslint` or `deno lint` | JS quality | P2 | **Skipped** (deno not installed) |
| `prettier` or `deno fmt` | JS formatting | P2 | **Skipped** (deno not installed) |
| `end-of-file-fixer` | Missing newlines at EOF | P3 | **DONE** |
| `trailing-whitespace` | Trailing whitespace | P3 | **DONE** |
| `markdownlint` | Markdown formatting | P3 | **DONE** |

---

## Summary: CI Checks

| Check | What it validates | Blocking? |
|--------|-------------------|-----------|
| Betterleaks | Full repo history scan | Yes |
| Shellcheck | All `.sh` files | Yes |
| shfmt | Shell formatting | Yes |
| Yamllint | All YAML files | Yes |
| Ruff | Python lint + format | Yes |
| JSON syntax | All `.json` files | Yes |
| Test suite | `tests/run-all.sh` (7 categories) | Yes |
| Docker compose | `docker compose config` + image pinning | Soft-fail |

---

## Potential Risks and Mitigations

1. **Pre-commit hooks slow down developer workflow**
   Mitigation: Pre-commit runs only on staged files by default. Betterleaks and shellcheck are fast (<2s on changed files).

2. **False positives from betterleaks block legitimate commits**
   Mitigation: Use `.betterleaksignore` for known false positives. Use `# betterleaks:allow` inline comments for test fixtures. Explicitly allowlist `.env.example` files in `.betterleaks.toml` — specifically the `change-me-*` placeholder patterns in `prometheus/.env.example:24,28`.

3. **Inline Python in shell heredocs is hard to validate**
   Mitigation: Extract between heredoc markers and pipe to `py_compile`. Catches syntax errors but not runtime errors — still better than zero validation.

4. **Adding `package.json` conflicts with the project's zero-dependency philosophy**
   Mitigation: Prefer `deno lint`/`deno fmt` or bare `npx` calls. Only add `package.json` if deno is not acceptable.

5. **UCI validation is custom and not tool-supported**
   Mitigation: Write a focused ~50-line bash script that checks UCI syntax patterns and cross-references hostnames. Sufficient for catching common errors.

6. **CI platform is unknown**
   Mitigation: `scripts/ci-run.sh` is platform-agnostic. Platform-specific workflow is a thin wrapper.

7. **UCI cross-reference check will correctly fail until the inventory gap is resolved**
   Mitigation: The check is correct by design — it exposed a real gap (`lm-escola-telhado` override exists without a matching inventory entry). Resolve the prerequisite in Phase 3.2 before running the cross-reference check.

---

## Implementation Order

Phases are numbered in implementation order within each sprint. Sprint 2 phases can be done in any order. Sprint 3 is lowest priority.

```text
Sprint 1 (P0–P1):
  Phase 1  (P0): Secret prevention + pre-commit framework + foundational configs  ← mostly done
  Phase 2  (P1): Shell script quality (shellcheck + shfmt + auto-discovery)
  Phase 3  (P1): Configuration validation (yamllint + UCI + env consistency + Docker)
  Phase 4  (P1): CI runner script + developer onboarding

Sprint 2 (P2):
  Phase 5  (P2): Python quality (ruff + unit tests for normalize.py)
  Phase 6  (P2): JavaScript quality (lint + format; unit tests deferred)
  Phase 7  (P2): JSON validation

Sprint 3 (P3):
  Phase 8  (P3): Markdown quality
  Phase 9  (P1, depends on Sprint 1): PowerShell syntax coverage
```

---

## Changes from v3 to v4

| v3 Item | v4 Change | Reason |
|---------|-----------|--------|
| Phase 1.1 described `.env.example` false positives as "empty variable names like `MESHA_TELEGRAM_BOT_TOKEN=`" | Fixed to identify actual patterns: `GF_ADMIN_PASSWORD=change-me-grafana-admin-password` and `TELEGRAM_BOT_TOKEN=` (not `MESHA_*`) | Incorrect variable names |
| Phase 1.2 had no `check-executables-have-shebangs` or `check-shebang-scripts-are-executable` hooks | Added both from `pre-commit-hooks` | Complement Phase 2.3 executable check with pre-built hooks |
| No `.editorconfig` or `.gitattributes` | Added Phase 1.3 with both files — `.editorconfig` has no `[Makefile]` section (no Makefile in the project) | Foundational layer for all formatters; prevents line-ending issues across OS |
| Phase 2.3 `set -euo pipefail` check didn't distinguish bash vs POSIX sh | Added shebang-aware check: bash → `set -euo pipefail`, sh → `set -e` only. Listed 5 known POSIX sh scripts using `set -e` | `pipefail` is a bashism; 5 scripts correctly use `#!/usr/bin/env sh` with `set -e` |
| Phase 2.3 didn't exclude `docker/**/bin/*` fake binaries | Added exclusion for fake-bin scripts | `docker/onboarding-test/fake-node/bin/uci` etc. are intentionally not executable outside Docker |
| Phase 2.3 said "hardcoded list of 33 files" | Fixed to "34 files, at least 6 missing" | Accurate count: `schedule-maintenance.sh`, `docker/phase1/mock-node/entrypoint.sh`, and 4 test files are missing |
| Phase 3.2 had no mention of the pre-existing `lm-escola-telhado` inventory gap | Added prerequisite task and Risk #7 | UCI cross-reference check would immediately fail on the existing `.uci` file without this context |
| Phase 3.2 and Phase 9.1 both specified creation of `tests/06-uci-validate.sh` | Specification and registration steps consolidated into Phase 3.2; Phase 9.1 removed | Phase 9.1 had nothing left to do after Phase 3.2 completed the test file |
| Phase 5.2 created `tests/07-inline-python.sh` but didn't register it in `run-all.sh` | Added full `run-all.sh` registration steps directly in Phase 5.2 | Implementer should not have to read the runner source to know how to register a category |
| Phase 9.1 duplicated work from Phase 3.2 and 5.2 | Phase 9 now contains only Phase 9.1 (PowerShell), retitled accordingly | Eliminated duplication |
| Phase 9.2 `pwsh -NoExecute` | Fixed to `[System.Management.Automation.Language.Parser]::ParseFile()` | `pwsh -NoExecute` does not exist |
| Phase 9.2 said "determine if maintained or not" for `bootstrap.ps1` | Removed decision point — it is clearly actively maintained (197 lines, `#Requires -Version 5.0`) | Misleading framing |
| Phase 4.2 included `scripts/bootstrap.mjs` task | Moved to Phase 6.1 (JavaScript section) | `bootstrap.mjs` is a JS file, not Python |
| Phase 4.3 had 8+ specific test cases for `normalize.py` | Simplified to "test public functions with a few representative cases each" | Over-specification; dry-run test already exercises it end-to-end |
| Phase 4.4 (rollout helper unit tests) | Dropped entirely | Thin wrappers; effort-to-value ratio is low |
| Phase 7 (hadolint for 2 test Dockerfiles) | Dropped entirely | Test infrastructure, not production; hadolint findings on test images are noise |
| Phase 8.2 (internal link validation) | Deferred | Markdown link syntax is complex; stale-branding check provides some coverage |
| Phase 9.3 (HTML fixture validation) | Dropped | Docker integration tests catch actual breakage |
| Phase numbering didn't match implementation order | Renumbered to match; grouped into 3 sprints | Clearer for implementers |
| No effort estimates | Added S/M/L estimates per phase | Helps with sprint planning |
| No CONTRIBUTING.md | Added Phase 4.3 | New volunteers need guidance on the guardrail system |
| No mention of `scripts/discover-from-thisnode.sh` risk | Added callout in Phase 2.1 | Operationally high-risk (SSHes into live nodes) |
| Phase 3.3 `.env.example` check didn't handle `${VAR:-default}` | Added both `${VARIABLE}` and `${VARIABLE:-default}` patterns, plus `$VARIABLE` in `install.sh` | Under-specified |

---

## Future Work (not in scope)

- **Renovate or Dependabot** — automated notifications for new versions of pre-commit hooks, Docker images, and tools. Add when CI platform is chosen.
- **Formal JSON Schema for YAML inventories** — replace inline Python assertions in `tests/03-schema.sh` with `.schema/` files. Only worth doing when the inline checks become unmaintainable.
- **Telegram adapter unit tests** — deferred until the adapter API stabilizes.
- **Internal link validation** — deferred until link breakage becomes an actual problem.
- **Inline Python extraction to standalone files** — would improve testability but is a refactor, not a guardrail.
