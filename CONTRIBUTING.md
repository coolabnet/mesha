# Contributing to Mesha

This guide explains how to set up the development environment, run quality checks locally, and work with the guardrail system that protects the Mesha workspace.

---

## Required Tools

The following tools are needed for local development. All of them work offline once installed.

### Core (required)

| Tool | Purpose | Install |
|------|---------|---------|
| **Git** | Version control | System package manager |
| **Bash 4+** | Script runtime | System default on Linux/macOS; use WSL2 on Windows |
| **Python 3** | YAML validation, adapter scripts | `sudo apt install python3` / `brew install python3` |
| **Node.js 22+** | ESM adapter scripts | Use NodeSource or `nvm install 22` on Linux; `brew install node@22` on macOS |
| **pre-commit** | Git hook framework | `pip install pre-commit` or `brew install pre-commit` |

### Linting and Formatting (required)

| Tool | Purpose | Install |
|------|---------|---------|
| **shellcheck** | Shell script static analysis | `sudo apt install shellcheck` / `brew install shellcheck` |
| **shfmt** | Shell script formatting | `brew install shfmt` or `go install mvdan.cc/sh/v3/cmd/shfmt@latest` |
| **yamllint** | YAML linting | `pip install yamllint` |
| **ruff** | Python linting and formatting | `pip install ruff` or `brew install ruff` |
| **deno** | JavaScript linting and formatting (no `package.json` needed) | `curl -fsSL https://deno.land/install.sh \| sh` |

### Optional

| Tool | Purpose | Install |
|------|---------|---------|
| **Docker + Compose** | Onboarding test stack, service installs | System package manager |
| **jq** | JSON processing | `sudo apt install jq` / `brew install jq` |
| **pwsh** | PowerShell syntax validation for `bootstrap.ps1` | See [official docs](https://learn.microsoft.com/powershell/scripting/install/) |

### Initial Setup

After cloning the repository:

```bash
cd mesha

# Install pre-commit hooks
pre-commit install

# Verify everything is in order
bash scripts/doctor.sh
```

---

## Running Checks Locally

There are three ways to run quality checks. Use all three before opening a pull request.

### 1. Pre-commit (fast, runs on staged files)

Pre-commit hooks run automatically on every `git commit`. They check only the files you have staged, so they are fast.

```bash
# Run against all files (useful after initial setup or dependency changes)
pre-commit run --all-files

# Run against staged files only (this is what the hook does automatically)
pre-commit run
```

### 2. QA Test Suite (comprehensive, project-specific)

The custom test suite validates file inventory, syntax, schemas, dry-runs, and service health.

```bash
# Run all 5+ test categories
bash tests/run-all.sh

# Run specific categories only (fast feedback loop)
bash tests/run-all.sh --category 01,02

# List available categories
bash tests/run-all.sh --list
```

Categories:

| ID | Name | What it checks |
|----|------|----------------|
| 01 | File Inventory | All expected files exist, are non-empty, and executable |
| 02 | Syntax Checks | `bash -n`, Python `py_compile`, Node ESM, YAML parse |
| 03 | Schema & Cross-References | YAML structure, node/gateway/site cross-references |
| 04 | Dry-Run Smoke Tests | `doctor.sh`, `run-rollout --dry-run`, `normalize.py` |
| 05 | Service Healthchecks | HTTP health probes (skipped if services not running) |

### 3. CI Runner (full pipeline, mirrors CI)

The CI runner script executes all quality checks in sequence. It exits on the first failure with a clear error message. If a tool is not installed, it prints a warning and skips that check (does not fail).

```bash
bash scripts/ci-run.sh
```

This runs: secret scanning, shellcheck, shfmt, yamllint, ruff, JSON syntax, the full QA test suite, and Docker compose validation (if Docker is available).

---

## What to Do When a Check Fails

### Shellcheck

Shellcheck reports warnings and errors in shell scripts.

**Common fixes:**

- **SC2086 (double quote variables):** Wrap variable expansions in quotes.

  ```bash
  # Wrong
  cat $file
  # Right
  cat "$file"
  ```

- **SC2155 (declare and assign separately):** Split local declaration from assignment.

  ```bash
  # Wrong
  local var="$(command)"
  # Right
  local var
  var="$(command)"
  ```

- **SC2034 (unused variable):** Remove the variable or prefix with `_`.
- **SC1090/SC1091 (can't follow source):** Add a `# shellcheck source=path/to/file` directive above the `source` line.

**Suppressing a false positive:**

Add a disable directive above the offending line or at the top of the file:

```bash
# shellcheck disable=SC2086
some_command $unquoted_var
```

Only suppress when you understand why the warning is a false positive. Document the reason in a comment.

### shfmt (shell formatting)

shfmt enforces consistent indentation (2 spaces), simplification, and binary-next-line style.

**Fix automatically:**

```bash
shfmt -w path/to/file.sh
# Or format all shell scripts:
find . -name '*.sh' -not -path './.git/*' -exec shfmt -w {} +
```

### yamllint

yamllint checks YAML style issues (line length, trailing spaces, indentation).

**Common fixes:**

- **line-length:** Break long lines. The project limit is 120 characters.
- **trailing-spaces:** Remove trailing whitespace.
- **indentation:** Use 2 spaces for YAML files.

**Fix automatically:** Many editors can fix these on save. The `.editorconfig` file in the project root configures the standard settings.

### ruff (Python)

ruff checks Python code quality and formatting.

**Fix automatically:**

```bash
ruff check --fix .
ruff format .
```

### deno (JavaScript)

deno provides linting and formatting for `.mjs` files without requiring a `package.json`.

**Fix formatting:**

```bash
deno fmt
```

**Fix lint issues manually** — deno does not auto-fix lint errors:

```bash
deno lint
```

### Pre-commit hooks (general)

If a pre-commit hook modifies files (e.g., `end-of-file-fixer`, `trailing-whitespace`):

```bash
# Stage the changes and commit again
git add -u
git commit
```

### QA Test Suite

If `bash tests/run-all.sh` fails, check which category failed:

```bash
# Run just the failing category for faster iteration
bash tests/run-all.sh --category 02
```

Each test file can also be run directly:

```bash
bash tests/02-syntax.sh
bash tests/03-schema.sh
```

---

## Emergency Bypass

In urgent situations (hotfix for a production outage, broken CI that blocks critical work), you can bypass pre-commit hooks:

```bash
git commit --no-verify -m "hotfix: description of the emergency change

no-verify justification: <reason why bypass was necessary>"
```

**Rules:**

- Every `--no-verify` commit **must** include a justification in the commit message.
- The justification should explain why the bypass was necessary (e.g., "CI runner script has a bug that blocks all commits, fix will follow").
- Bypass commits are visible in git history and will be reviewed.
- Do not use `--no-verify` to skip checks you could fix in 5 minutes.

After a bypass commit, run the checks manually as soon as possible:

```bash
pre-commit run --all-files
bash tests/run-all.sh
```

---

## How to Add New Guardrails

### Add a pre-commit hook

Edit `.pre-commit-config.yaml` at the project root. Add a new hook entry:

```yaml
repos:
  - repo: https://github.com/example/some-linter
    rev: v1.0.0
    hooks:
      - id: some-linter
        args: ["--config", ".some-linter-config"]
```

Then install the updated hooks:

```bash
pre-commit install
pre-commit run --all-files
```

### Add a CI step

Edit `scripts/ci-run.sh` and add a new step in the appropriate position. Follow the existing pattern:

```bash
step "Name of the check"
if check_command tool_name; then
    tool_name --some-flag . || die "Name of the check failed"
else
    warn "tool_name not installed — skipping"
fi
```

The `check_command` helper gracefully skips the step if the tool is not available. The `die` helper exits with a clear error message.

### Add a QA test category

Create a new test file `tests/NN-name.sh` following the pattern in existing test files:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run_my_checks() {
    cd "$WORKSPACE_ROOT"
    qa_section "My Check Category"
    # ... test logic using qa_pass, qa_fail, qa_skip ...
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_my_checks
    qa_summary
fi
```

Then register it in `tests/run-all.sh` by adding entries to the `CATEGORY_NAME`, `CATEGORY_FILE`, `CATEGORY_FN` maps and the `ALL_CATEGORIES` array.

---

## Project Conventions

- **No `package.json`.** The project intentionally avoids npm dependencies. Use system tools or deno for JavaScript.
- **Offline-first.** All checks must work without internet access after initial tool installation.
- **Shell scripts:** Use `set -euo pipefail` for bash, `set -e` for POSIX sh. Indent with 2 spaces.
- **YAML files:** Indent with 2 spaces. Maximum line length is 120 characters.
- **Python files:** Indent with 4 spaces. Target Python 3.11+. Use `ruff` for linting.
- **UCI config files:** Follow OpenWrt UCI format (`config`/`option`/`list` lines). Hostnames in node overrides must match entries in `inventories/mesh-nodes.yaml`.
- **Commit messages:** Use conventional commit prefixes: `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`.
- **Secrets:** Never commit secrets, tokens, or private keys. Store credentials in `secrets/` (gitignored). See `secrets/README.md` for the credential loading convention.
