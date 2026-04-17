# Unstaged Changes Review & Commit Plan (v4 — final)

## Objective

Review and commit 85 modified files + 17 new untracked files (102 total) across the Mesha workspace. The changes are overwhelmingly **formatting/linting** (shfmt, shellcheck, markdownlint, ruff) with a few **substantive additions** (new config files, new test files, new CI scripts). This plan groups changes into logical batches that can be reviewed and committed together, ordered from least risky to most impactful.

## Change Landscape Summary

| Category | Files | Nature |
|----------|-------|--------|
| Shell formatting (shfmt) | 34 .sh files | Indentation 4→2 spaces, quote removal in `[[ ]]`, redirect spacing |
| Shell behavioral (mixed in) | 6 .sh files | `cd \|\| exit 1` safety, shellcheck directives, shebang change, new test sections |
| Shared test library formatting | 1 file | `tests/lib.sh` — quote removal in `[[ ]]`, indent, arithmetic spacing |
| Markdown formatting (markdownlint) | 32 .md files | Blank lines before lists, ` ``` ` → ` ```text `, trailing whitespace |
| Python formatting (ruff) | 7 .py files | Import ordering, line wrapping, `Optional[X]` → `X \| None` |
| Lint/format config (new) | 7 files | `.editorconfig`, `.gitattributes`, `.markdownlint.json`, `.yamllint`, `pyproject.toml`, `.betterleaks*` |
| Lint/format config (modified) | 2 files | `.gitignore` (hardened), `.pre-commit-config.yaml` (expanded) |
| New CI/test files | 4 files | `scripts/ci-run.sh`, `tests/06-uci-validate.sh`, `tests/07-inline-python.sh`, `tests/unit/test_normalize.py` |
| Test runner update | 1 file | `tests/run-all.sh` — registers new test categories 06, 07 |
| New test sections in existing files | 2 files | `tests/02-syntax.sh` (3 new sections), `tests/03-schema.sh` (3 new sections) |
| New documentation | 1 file | `CONTRIBUTING.md` |
| Historical plans | 5 files | `plans/2026-04-12-mesha-guardrails-v*.md` (4) + this review plan (1) |

**Key insight:** The vast majority of changes are mechanical formatting fixes applied by automated tools (shfmt, markdownlint, ruff). However, several files mix behavioral changes into the formatting — these are called out per batch. The approach for mixed files is to **accept the mix** (not split them) but review the new logic sections line-by-line within the formatting batch.

---

## Pre-flight: Unstage `.yamllint`

`.yamllint` is currently **already staged** (`A` in git index). It must be unstaged before batching so it lands in the correct commit.

- [ ] Run `git reset HEAD .yamllint` to unstage it
- [ ] Confirm `git status --porcelain -- .yamllint` shows `?? .yamllint`

---

## Implementation Plan

### Batch 1: Lint & Formatting Configuration

**Rationale:** These files define the formatting rules applied to all subsequent batches. Committing them first establishes the baseline. 7 files are new (untracked), 2 are modified tracked files.

- [ ] Review `.editorconfig` — universal editor settings (indent, charset, line endings)
- [ ] Review `.gitattributes` — enforce LF line endings for all text files
- [ ] Review `.markdownlint.json` — disabled rules (MD013, MD033, MD041, MD036, MD051)
- [ ] Review `.yamllint` — relaxed config with 120-char line limit (run `git reset HEAD .yamllint` first per pre-flight)
- [ ] Review `pyproject.toml` — ruff config targeting Python 3.11
- [ ] Review `.betterleaks.toml` and `.betterleaksignore` — secret scanning allowlist
- [ ] Review `.gitignore` additions (modified file) — new secret patterns (`*.token`, `*.password`, `credentials`, `*.private`)
- [ ] Review `.pre-commit-config.yaml` expansion (modified file) — expanded from 1 hook (betterleaks) to 8 hooks (shellcheck, shfmt, ruff, markdownlint, yamllint, pre-commit-hooks). Note: hook versions are pinned; reviewers should use `pre-commit run` rather than local tool installs to avoid version mismatches.
- [ ] Verify the `exclude: ^tests/03-schema\.sh$` directive for both shellcheck and shfmt hooks — this file contains UCI heredocs that these tools cannot parse. If `tests/03-schema.sh` is ever renamed, this exclude must be updated.
- [ ] **Checkpoint:** Run `pre-commit run --all-files` to confirm hooks are configured correctly (expect failures on unformatted code — that's fine, the fixes come in Batches 2-5)
- [ ] **Stage:** `git add .editorconfig .gitattributes .markdownlint.json .yamllint pyproject.toml .betterleaks.toml .betterleaksignore .gitignore .pre-commit-config.yaml`
- [ ] **Commit message:** `chore: add lint/format config files and expand pre-commit hooks`

**Files (9):** `.editorconfig` (new), `.gitattributes` (new), `.markdownlint.json` (new), `.yamllint` (new), `pyproject.toml` (new), `.betterleaks.toml` (new), `.betterleaksignore` (new), `.gitignore` (modified), `.pre-commit-config.yaml` (modified)

---

### Batch 2: Shell Script Formatting + New Test Sections

**Rationale:** The largest batch by file count (34 files). Most changes are mechanical: 4-space → 2-space indentation, removal of unnecessary `$` quotes in `[[ ]]` tests, redirect spacing (`> file` → `>file`), and case/esac indentation. However, several files contain **behavioral changes mixed in with formatting** — these are called out below and need explicit review.

**Strategy for mixed files:** Rather than trying to split formatting from logic in the same file (error-prone and tedious), we accept the mix. The new logic sections are reviewed line-by-line; the formatting changes are confirmed by spot-checking.

#### Shared test library (review carefully)

- [ ] Review `tests/lib.sh` — shared library sourced by **all** test files. Changes: quote removal in `[[ ]]` (`"$path"` → `$path`, `"$reason"` → `$reason`, `"${_MESHA_LIB_LOADED:-}"` → `${_MESHA_LIB_LOADED:-}`), 4→2 space indent, arithmetic spacing (`$(( QA_FAIL + 1 ))` → `$((QA_FAIL + 1))`), array spacing (`QA_ERRORS+=( "..." )` → `QA_ERRORS+=("...")`). The quote removal is safe in bash (word-splitting doesn't occur inside `[[ ]]`) but changes the style convention used across all tests.

#### Behavioral changes (review carefully)

- [ ] Review `adapters/mesh/collect-topology.sh:1` — shebang changed from `#!/usr/bin/env sh` to `#!/usr/bin/env bash`. This is a **runtime dependency change**. Verify the script uses bash-specific features (`local`, `[[ ]]`). The `set -e` comment was also updated to note this was originally POSIX sh.
- [ ] Review `tests/01-file-inventory.sh` — `cd "$WORKSPACE_ROOT"` changed to `cd "$WORKSPACE_ROOT" || exit 1` (safety improvement: exits if cd fails instead of silently continuing in wrong directory)
- [ ] Review `tests/03-schema.sh` — same `cd || exit 1` pattern
- [ ] Review `tests/04-dryrun.sh` — same `cd || exit 1` pattern. Also note: the heartbeat cache preservation test was **restructured** (backup/restore logic moved within the same else block but with different line organization). Logic is equivalent but the diff looks large — don't be alarmed.
- [ ] Review shellcheck directive additions (~20 `# shellcheck disable=SC2034` and `# shellcheck source=...` directives added across files). Each `SC2034` suppress means "this variable appears unused and that's intentional." Verify these are correct suppressions, not hiding real bugs.

#### New test sections in existing files (review line-by-line)

**`tests/02-syntax.sh`** — 3 new test sections added alongside formatting changes:

- [ ] Review "Shebang/executable consistency" section — checks that `.sh` files with shebangs are marked executable; excludes `docker/**/bin/*` (fake binaries). Verify the exclusion list is correct.
- [ ] Review "Shell safety (set -e)" section — checks bash scripts have `set -euo pipefail` and POSIX sh scripts have `set -e`. Verify it doesn't flag scripts that intentionally omit these (test files use `set -uo pipefail`).
- [ ] Review "PowerShell syntax" section — validates `.ps1` files using `pwsh` AST parser. Verify the env-var-based path passing (`PWSH_PATH`) avoids injection.

**`tests/03-schema.sh`** — 3 new test sections added alongside formatting changes:

- [ ] Review "I. .env.example variable consistency" — validates `.env.example` files. Verify the validation logic matches the project's env conventions.
- [ ] Review "J. Docker image pinning (no :latest or unpinned tags)" — ensures docker-compose images use pinned tags. Verify the regex catches `:latest` and unpinned images correctly without false positives on named tags like `alpine`.
- [ ] Review "K. field_map.json cross-reference" — validates that `field_map.json` canonical fields exist in `normalize.py` or `mesh-nodes.yaml`, and that `severity_map` keys match canonical fields. Verify the Python inline script handles edge cases (missing `INVENTORY_FIELDS`, unknown fields used in source code).

#### Other files with formatting notes

- [ ] `tests/05-healthchecks.sh` — pure formatting (confirmed no new sections). Note: `status=$(curl ... ; true)` was restructured to multi-line `status=$( ... true )` by shfmt. The `true` on its own line is the "suppress curl exit code" pattern — semantically identical, just reformatted.

#### Formatting-only files (spot-check 5-6)

- [ ] Spot-check `scripts/activate-workspace.sh` — verify indentation and quote removal are correct
- [ ] Spot-check `scripts/bootstrap.sh` — verify case/esac indentation, `$USER` quoting in single quotes
- [ ] Spot-check `scripts/discover-from-thisnode.sh` — verify heredoc indentation preserved
- [ ] Spot-check `scripts/doctor.sh` — verify arithmetic `$(( ))` spacing
- [ ] Spot-check `skills/mesh-readonly/scripts/run-mesh-readonly.sh` — verify `mapfile` and loop formatting
- [ ] Spot-check `skills/mesh-rollout/scripts/` (7 files) — verify drift check, rollout, rollback formatting
- [ ] Spot-check remaining files (`scripts/qa-onboarding-readiness.sh`, `scripts/run-compose-phase1-test.sh`, `scripts/mesh-heartbeat.sh`, `adapters/mesh/collect-nodes.sh`, `adapters/server/collect-health.sh`, `adapters/server/collect-services.sh`, `skills/server-services/scripts/create-network.sh`, `skills/server-services/scripts/*/install.sh` (5 files), `docker/onboarding-test/*/entrypoint.sh` (2 files), `docker/onboarding-test/phase1-test.sh`, `docker/phase1/mock-node/entrypoint.sh`) — confirm consistent formatting

**IMPORTANT:** `tests/run-all.sh` is **excluded** from this batch. It belongs in Batch 6 because it registers new test files that don't exist yet.

- [ ] **Checkpoint:** Run `shfmt -d scripts/ adapters/ skills/ docker/ tests/` to confirm no remaining formatting diffs (exclude `tests/03-schema.sh` if it has intentional non-shfmt patterns)
- [ ] **Checkpoint:** Run `shellcheck --severity=warning scripts/ adapters/ skills/ docker/ tests/` to confirm no new warnings
- [ ] **Stage:** `git add -- '*.sh' && git reset HEAD tests/run-all.sh`
- [ ] **Commit message:** `style: apply shfmt formatting and add new test sections to syntax/schema checks`

**Files (34):** All `.sh` files in `scripts/`, `adapters/`, `skills/`, `docker/`, `tests/` **EXCEPT** `tests/run-all.sh`

---

### Batch 3: Markdown Formatting (markdownlint fixes)

**Rationale:** 32 markdown files with consistent changes: blank lines before lists/tables, ` ``` ` → ` ```text ` for code fences, trailing whitespace removal, and a few minor content tweaks (heading parentheticals in `docs/deployment.md`). The `HEARTBEAT.md` change converts `# comments` to `<!-- HTML comments -->` which is a minor behavioral change worth noting.

**Known issue to fix before committing:**

- [ ] Fix spacing bug in `skills/mesh-onboarding/templates/site-metadata-form.md:197` — the markdownlint-driven underscore escaping changed `Download: ___ Mbps  Upload: ___ Mbps` to `Download: \_\_\_Mbps  Upload:\_\_\_ Mbps`. The spaces around `___` were lost. Restore to `Download: \_\_\_ Mbps  Upload: \_\_\_ Mbps` before committing.

**Review checklist:**

- [ ] Review `AGENTS.md` — blank lines before list sections, ` ```text ` fence annotation
- [ ] Review `BOOTSTRAP.md` — blank lines before list sections throughout
- [ ] Review `HEARTBEAT.md` — comment style change from `#` to `<!-- -->` (verify this doesn't affect agent parsing — agents read markdown as plain text, so `#` vs `<!-- -->` changes what they "see")
- [ ] Review `MEMORY.md` — blank lines before lists, ` ```text ` fences, section heading rename ("Purpose" → "Purpose (Decisions Log)")
- [ ] Review `README.md` — badge URL fixes (empty `()` → anchored `(#status)`, `(#platform)`), ` ```text ` fences, blank line additions
- [ ] Review `RUN.md` — blank line addition, angle-bracket URL formatting (`http://localhost:3000` → `<http://localhost:3000>`)
- [ ] Review `SOUL.md` — ` ```text ` fence changes, blank line before list
- [ ] Review `TOOLS.md` — blank lines before list items in examples
- [ ] Review `secrets/README.md` — formatting changes
- [ ] Review `docs/architecture.md` — ` ```text ` fences, blank lines before lists
- [ ] Review `docs/configuration.md` — blank lines before lists
- [ ] Review `docs/deployment.md` — heading suffix additions (`(macOS)`, `(Windows)`) for clarity, ` ```text ` fences, blank lines
- [ ] Review `docs/known-issues/README.md` — minor formatting
- [ ] Review `docs/known-issues/channel-congestion-2ghz.md` — minor formatting
- [ ] Review `docs/known-issues/tplink-wr841n-power-loss.md` — minor formatting
- [ ] Review `docs/onboarding/jellyfin.md` — minor formatting
- [ ] Review `docs/onboarding/kolibri.md` — minor formatting
- [ ] Review `docs/onboarding/nextcloud.md` — minor formatting
- [ ] Review `docs/playbooks/firmware-rollout.md` — blank lines, ` ```text ` fences
- [ ] Review `docs/playbooks/incident-response.md` — blank lines, ` ```text ` fences
- [ ] Review `docs/playbooks/local-service-install.md` — blank lines, ` ```text ` fences
- [ ] Review `docs/playbooks/maintenance-window.md` — blank lines, ` ```text ` fences
- [ ] Review `docs/playbooks/node-onboarding.md` — blank lines, ` ```text ` fences
- [ ] Review `docs/playbooks/rollout-orchestration.md` — blank lines, ` ```text ` fences
- [ ] Review `docs/sites/README.md` — minor formatting
- [ ] Review `docs/sites/associacao-portal-sem-porteiras.md` — minor formatting
- [ ] Review `docs/troubleshooting.md` — formatting
- [ ] Review `adapters/channels/README.md` — ` ```text ` fences, blank lines
- [ ] Review `adapters/channels/telegram/README.md` — ` ```text ` fences, blank lines
- [ ] Review `desired-state/mesh/node-overrides/README.md` — minor formatting
- [ ] Review `skills/mesh-onboarding/templates/site-metadata-form.md` — markdownlint-disable comment, ` ```text ` fence, **fix underscore spacing bug first**
- [ ] Review `skills/server-services/scripts/README.md` — formatting
- [ ] **Checkpoint:** Run `markdownlint .` to confirm all files pass
- [ ] **Stage:** `git add -- '*.md'`
- [ ] **Commit message:** `style: apply markdownlint formatting to all markdown files`

**Files (32):** All modified `.md` files across root, `docs/`, `adapters/`, `skills/`, `secrets/`

---

### Batch 4: Python Formatting (ruff fixes)

**Rationale:** 7 Python files with import reordering, line wrapping, and one type annotation modernization (`Optional[dict]` → `dict | None`). The `from datetime import timezone` → `from datetime import UTC, datetime` change in `normalize.py` is a Python 3.11+ modernization. All changes are formatting-only except the type annotation and import changes which are functionally equivalent.

- [ ] Review `adapters/mesh/normalize.py` — import reordering, `Optional[X]` → `X | None`, `timezone.utc` → `UTC`, line wrapping, `open(path, "r")` → `open(path)`
- [ ] Review `skills/mesh-rollout/scripts/helpers/check_change_window.py` — formatting
- [ ] Review `skills/mesh-rollout/scripts/helpers/parse_resume_state.py` — formatting
- [ ] Review `skills/mesh-rollout/scripts/helpers/parse_ring_nodes.py` — formatting
- [ ] Review `skills/mesh-rollout/scripts/helpers/parse_rings.py` — formatting
- [ ] Review `skills/mesh-rollout/scripts/helpers/update_node_state.py` — formatting
- [ ] Review `skills/mesh-rollout/scripts/helpers/write_rollout_state.py` — formatting
- [ ] Verify Python 3.11 baseline is acceptable (project already targets 3.11 per `pyproject.toml`)
- [ ] **Checkpoint:** Run `ruff check . && ruff format --check .` to confirm no remaining issues
- [ ] **Stage:** `git add -- '*.py'`
- [ ] **Commit message:** `style: apply ruff formatting to all Python files`

**Files (7):** All `.py` files in `adapters/`, `skills/mesh-rollout/scripts/helpers/`

---

### Batch 5: YAML Config Formatting

**Rationale:** Small formatting changes in YAML config files (yamllint compliance). These are data files, not code.

- [ ] Review `desired-state/mesh/maintenance-windows.yaml` — minor formatting
- [ ] Review `desired-state/server/monitoring/alerting-rules.yaml` — minor formatting
- [ ] Review `inventories/gateways.yaml` — formatting
- [ ] Review `inventories/mesh-nodes.yaml` — formatting
- [ ] Review `inventories/sites.yaml` — formatting
- [ ] Review `skills/server-services/scripts/homer/docker-compose.yaml` — formatting
- [ ] Review `skills/server-services/scripts/jellyfin/docker-compose.yaml` — formatting
- [ ] Review `skills/server-services/scripts/kolibri/docker-compose.yaml` — formatting
- [ ] Review `skills/server-services/scripts/prometheus/docker-compose.yaml` — formatting
- [ ] **Checkpoint:** Run `yamllint .` to confirm all YAML files pass
- [ ] **Stage:** `git add desired-state/ inventories/ skills/server-services/scripts/*/docker-compose.yaml`
- [ ] **Commit message:** `style: apply yamllint formatting to YAML files`

**Files (9):** All modified `.yaml` files in `desired-state/`, `inventories/`, `skills/` (excluding `.pre-commit-config.yaml` which is in Batch 1)

---

### Batch 6: New CI Script, Test Files & Test Runner Update

**Rationale:** These are new files that add testing capability, plus the updated test runner that registers them. They must be committed **together** — `tests/run-all.sh` now references `tests/06-uci-validate.sh` and `tests/07-inline-python.sh`, so committing them separately would create a broken intermediate state where the runner tries to source files that don't exist.

- [ ] Review `scripts/ci-run.sh` — CI quality gate runner; verify tool detection, exit codes, error handling
- [ ] Review `tests/06-uci-validate.sh` — UCI config syntax validation; verify regex patterns for valid UCI directives
- [ ] Review `tests/07-inline-python.sh` — inline Python heredoc validation; verify file list and extraction logic
- [ ] Review `tests/unit/test_normalize.py` — Python unit tests for normalize.py; verify test coverage and assertions
- [ ] Review `tests/run-all.sh` — verify new category entries (06, 07) match the new test files' function names (`run_uci_checks`, `run_inline_python_checks`), and `ALL_CATEGORIES` array is updated
- [ ] Verify all test files are executable and have proper shebangs (`ls -la tests/06* tests/07* tests/unit/test_normalize.py`)
- [ ] Verify `tests/unit/__pycache__/` is covered by `.gitignore` (it is — `__pycache__/` is listed)
- [ ] **Checkpoint:** Run `bash tests/run-all.sh -c 06,07` to confirm the new test categories execute correctly
- [ ] **Stage:** `git add scripts/ci-run.sh tests/06-uci-validate.sh tests/07-inline-python.sh tests/unit/test_normalize.py tests/run-all.sh`
- [ ] **Commit message:** `feat: add CI runner, UCI validation tests, inline Python checks, and unit tests`

**Files (5):** `scripts/ci-run.sh` (new), `tests/06-uci-validate.sh` (new), `tests/07-inline-python.sh` (new), `tests/unit/test_normalize.py` (new), `tests/run-all.sh` (modified)

---

### Batch 7: New Documentation

**Rationale:** `CONTRIBUTING.md` is a new contributor guide. Review for accuracy against the actual project setup.

- [ ] Review `CONTRIBUTING.md` — verify tool install instructions, pre-commit setup, branch conventions match project reality
- [ ] **Stage:** `git add CONTRIBUTING.md`
- [ ] **Commit message:** `docs: add CONTRIBUTING.md with setup and quality check instructions`

**Files (1):** `CONTRIBUTING.md` (new)

---

### Batch 8: Historical Plans (Optional)

**Rationale:** These are planning documents from the guardrails implementation. They are historical reference material. Consider whether they belong in the repo or should stay local-only. The entire `plans/` directory has never been tracked by git — all 5 files are new to the repository.

**Files in `plans/`:**

- `2026-04-12-mesha-guardrails-v1.md` — initial guardrails plan
- `2026-04-12-mesha-guardrails-v2.md` — revised guardrails plan
- `2026-04-12-mesha-guardrails-v3.md` — revised guardrails plan
- `2026-04-12-mesha-guardrails-v4.md` — final guardrails plan
- `2026-04-16-unstaged-changes-review-batches-v4.md` — this review plan (transient working document)

- [ ] Review `plans/2026-04-12-mesha-guardrails-v1.md` — verify no sensitive content
- [ ] Review `plans/2026-04-12-mesha-guardrails-v2.md` — verify no sensitive content
- [ ] Review `plans/2026-04-12-mesha-guardrails-v3.md` — verify no sensitive content
- [ ] Review `plans/2026-04-12-mesha-guardrails-v4.md` — verify no sensitive content
- [ ] Decide whether to include this review plan (`plans/2026-04-16-unstaged-changes-review-batches-v4.md`) in the commit or delete it after execution
- [ ] Decide: commit all plans, commit only the 4 guardrails plans, or add `plans/` to `.gitignore`
- [ ] **Stage (if committing):** `git add plans/2026-04-12-mesha-guardrails-v*.md` (and optionally this plan)
- [ ] **Commit message (if committing):** `docs: add historical guardrails implementation plans`

**Files (4 or 5):** `plans/` directory

---

## File Accounting

| Batch | New | Modified | Total |
|-------|-----|----------|-------|
| 1. Config | 7 | 2 | 9 |
| 2. Shell | 0 | 34 | 34 |
| 3. Markdown | 0 | 32 | 32 |
| 4. Python | 0 | 7 | 7 |
| 5. YAML | 0 | 9 | 9 |
| 6. CI/Tests | 4 | 1 | 5 |
| 7. Docs | 1 | 0 | 1 |
| 8. Plans | 4-5 | 0 | 4-5 |
| **Total** | **16-17** | **85** | **101-102** |

## Verification Criteria

- [ ] All 85 modified files are accounted for in one of the 8 batches (confirmed: 2 + 34 + 32 + 7 + 9 + 1 = 85)
- [ ] Each batch passes its relevant linter after committing:
  - Batch 2: `shfmt -d .` shows no diffs, `shellcheck --severity=warning` shows no new warnings
  - Batch 3: `markdownlint .` passes clean
  - Batch 4: `ruff check . && ruff format --check .` passes clean
  - Batch 5: `yamllint .` passes clean
- [ ] No logic changes are hidden inside formatting batches — all behavioral changes are explicitly called out per batch
- [ ] New test sections in `tests/02-syntax.sh` and `tests/03-schema.sh` are reviewed line-by-line (not just spot-checked)
- [ ] `tests/lib.sh` quote removal in `[[ ]]` is reviewed and accepted as safe
- [ ] New files in Batch 6 have correct shebangs and are executable
- [ ] `tests/run-all.sh` and new test files are in the same commit (Batch 6)
- [ ] `.gitignore` additions in Batch 1 correctly protect secret file patterns
- [ ] Pre-commit hooks in Batch 1 are compatible with the formatting applied in Batches 2-5
- [ ] `bash tests/run-all.sh` passes after Batch 6 is committed
- [ ] `pre-commit run --all-files` passes clean after all batches are committed

## Potential Risks and Mitigations

1. **Shebang change in `collect-topology.sh`** (`sh` → `bash`)
   Mitigation: The script already uses `local` and will use `[[ ]]` after formatting — both require bash. The change is correct but should be noted as a runtime dependency change, not just formatting.

2. **`HEARTBEAT.md` comment style change** (`#` → `<!-- -->`)
   Mitigation: Verify that downstream tools (OpenClaw, agents) don't parse `#` comments in markdown for instructions. HTML comments are the standard way to add non-rendering notes in markdown. Agents that read the raw file will see different content — `#` comments are visible as text, `<!-- -->` comments are invisible.

3. **Python 3.11+ type union syntax** (`Optional[X]` → `X | None`)
   Mitigation: `pyproject.toml` already targets `py311`. Verify deployment targets support Python 3.11+.

4. **Large diff volume makes manual review error-prone**
   Mitigation: Batches 2-5 are mechanical formatting — review by spot-checking 5-6 files per batch rather than reading every line. Focus detailed review on Batches 1, 6, 7, 8. All behavioral changes within formatting batches are explicitly called out.

5. **Pre-commit hooks may reject existing code**
   Mitigation: The formatting changes in Batches 2-5 are the fixes that make the codebase pass the hooks added in Batch 1. Commit Batch 1 first, then Batches 2-5 will be clean.

6. **Spacing bug in `site-metadata-form.md`** (underscore escaping lost spaces)
   Mitigation: Fix `Download: \_\_\_Mbps  Upload:\_\_\_ Mbps` to `Download: \_\_\_ Mbps  Upload: \_\_\_ Mbps` before committing Batch 3. This was introduced by the markdownlint auto-fix removing markdown emphasis but also eating adjacent spaces.

7. **Pre-commit hook version mismatches across reviewers**
   Mitigation: Hook versions are pinned in `.pre-commit-config.yaml`. Reviewers should run `pre-commit run` (which uses the pinned versions via virtualenvs) rather than their locally installed tools to avoid formatting disagreements.

8. **`.yamllint` already staged — will leak into wrong commit**
   Mitigation: Run `git reset HEAD .yamllint` as a pre-flight step before starting any batch.

9. **Mixed formatting + new logic in `tests/02-syntax.sh` and `tests/03-schema.sh`**
   Mitigation: Accept the mix rather than trying to split. Review the new test sections (Shebang/executable, Shell safety, PowerShell, .env.example, Docker pinning, field_map cross-reference) line-by-line within the formatting batch. The commit message reflects the mixed nature.

10. **`tests/04-dryrun.sh` heartbeat test restructuring looks like a large diff**
    Mitigation: The logic is equivalent — only the code organization changed (backup/restore variables moved within the same else block). Don't be alarmed by the large diff; verify the before/after behavior is identical.

11. **`tests/lib.sh` quote removal in `[[ ]]` changes style convention for all tests**
    Mitigation: The change is safe in bash (word-splitting doesn't occur inside `[[ ]]`), but it changes the convention from "always quote variables" to "omit quotes in `[[ ]]`". If the team prefers explicit quoting for consistency, this can be reverted with `# shellcheck disable=SC2086` or a `.shfmt` config change.

12. **`tests/03-schema.sh` excluded from shellcheck and shfmt in `.pre-commit-config.yaml`**
    Mitigation: This file contains inline UCI config heredocs that these tools cannot parse. The exclude is intentional. If the file is renamed, the exclude regex must be updated.

## Alternative Approaches

1. **Single mega-commit**: Commit everything as one "apply linting" commit. Simpler but makes bisecting harder and mixes config changes with formatting.
2. **Two commits only**: "Add config files" + "Apply formatting". Simpler batching but loses the ability to isolate Python vs Shell vs Markdown formatting issues.
3. **Skip historical plans**: Add `plans/` to `.gitignore` instead of committing. Keeps the repo focused on operational code rather than planning artifacts.
4. **Merge Batches 2-5 into one formatting commit**: If the per-language split feels excessive, combine all formatting into a single `style: apply automated formatting` commit. Loses per-linter isolation but reduces commit count from 8 to 5.
5. **Extract new test sections into a separate commit**: Manually split the new test sections from `tests/02-syntax.sh` and `tests/03-schema.sh` into their own commit. Purest separation but requires manual editing and is error-prone.
