#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap.sh
# Mesha Community Infrastructure Operator — Host Bootstrap
#
# Checks for required tools, prints install suggestions for anything missing,
# verifies OpenClaw CLI, and summarizes next steps.
#
# Usage:
#   ./scripts/bootstrap.sh              # check and suggest installs
#   ./scripts/bootstrap.sh --check-only # check only, make no changes
#
# Risk class: Class B (maintainer-run on a trusted host, no formal approval
# required — see TOOLS.md §Bootstrap and Maintenance Scripts).
#
# This script is safe to run multiple times (idempotent).
# Make this script executable: chmod +x scripts/bootstrap.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve repo root regardless of where the script is called from
# ---------------------------------------------------------------------------
REPO_ROOT="$( cd "$(dirname "$0")/.." && pwd )"

# ---------------------------------------------------------------------------
# Colour helpers (ANSI codes)
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass()  { echo -e "  ${GREEN}[PASS]${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $*"; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $*"; }
info()  { echo -e "  ${CYAN}[INFO]${RESET} $*"; }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
CHECK_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=true ;;
    -h|--help)
      echo "Usage: $0 [--check-only]"
      echo "  --check-only   Only check prerequisites; do not suggest installing"
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# State tracking
# ---------------------------------------------------------------------------
MISSING_REQUIRED=()
MISSING_OPTIONAL=()

# ---------------------------------------------------------------------------
# Detect OS for install suggestions
# ---------------------------------------------------------------------------
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    echo "wsl"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "linux"
  else
    echo "unknown"
  fi
}

OS="$(detect_os)"

# ---------------------------------------------------------------------------
# Install suggestion helper
# ---------------------------------------------------------------------------
suggest_install() {
  local tool="$1"
  local linux_cmd="${2:-}"
  local macos_cmd="${3:-}"

  if $CHECK_ONLY; then
    return
  fi

  case "$OS" in
    macos)
      [[ -n "$macos_cmd" ]] && info "Install suggestion: ${macos_cmd}" ;;
    linux|wsl)
      [[ -n "$linux_cmd" ]] && info "Install suggestion: ${linux_cmd}" ;;
    *)
      info "Install $tool manually for your platform." ;;
  esac
}

# ---------------------------------------------------------------------------
# Check: git
# ---------------------------------------------------------------------------
check_git() {
  header "git"
  if command -v git &>/dev/null; then
    local ver
    ver="$(git --version 2>&1)"
    pass "$ver"
  else
    fail "git not found"
    MISSING_REQUIRED+=("git")
    suggest_install "git" \
      "sudo apt install -y git" \
      "brew install git"
  fi
}

# ---------------------------------------------------------------------------
# Check: Node.js v22+
# ---------------------------------------------------------------------------
check_node() {
  header "Node.js (v22+ required)"
  if command -v node &>/dev/null; then
    local raw_ver
    raw_ver="$(node --version 2>&1)"          # e.g. v22.3.0
    local major
    major="$(echo "$raw_ver" | sed 's/v//' | cut -d. -f1)"
    if [[ "$major" -ge 22 ]]; then
      pass "node $raw_ver"
    else
      fail "node $raw_ver found — v22+ required"
      MISSING_REQUIRED+=("node@22+")
      suggest_install "Node.js 22+" \
        "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs  (or: nvm install 22)" \
        "brew install node@22"
    fi
  else
    fail "node not found"
    MISSING_REQUIRED+=("node@22+")
    suggest_install "Node.js 22+" \
      "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs  (or: nvm install 22)" \
      "brew install node@22"
  fi
}

# ---------------------------------------------------------------------------
# Check: ssh
# ---------------------------------------------------------------------------
check_ssh() {
  header "SSH client"
  if command -v ssh &>/dev/null; then
    local ver
    ver="$(ssh -V 2>&1 || true)"
    pass "ssh — $ver"
  else
    fail "ssh not found"
    MISSING_REQUIRED+=("ssh")
    suggest_install "ssh" \
      "sudo apt install -y openssh-client" \
      "SSH is included with macOS — check your system."
  fi
}

# ---------------------------------------------------------------------------
# Check: curl
# ---------------------------------------------------------------------------
check_curl() {
  header "curl"
  if command -v curl &>/dev/null; then
    local ver
    ver="$(curl --version 2>&1 | head -1)"
    pass "$ver"
  else
    fail "curl not found"
    MISSING_REQUIRED+=("curl")
    suggest_install "curl" \
      "sudo apt install -y curl" \
      "brew install curl"
  fi
}

# ---------------------------------------------------------------------------
# Check: jq
# ---------------------------------------------------------------------------
check_jq() {
  header "jq"
  if command -v jq &>/dev/null; then
    local ver
    ver="$(jq --version 2>&1)"
    pass "$ver"
  else
    warn "jq not found (strongly recommended)"
    MISSING_OPTIONAL+=("jq")
    suggest_install "jq" \
      "sudo apt install -y jq" \
      "brew install jq"
  fi
}

# ---------------------------------------------------------------------------
# Check: python3
# ---------------------------------------------------------------------------
check_python3() {
  header "Python 3"
  if command -v python3 &>/dev/null; then
    local ver
    ver="$(python3 --version 2>&1)"
    pass "$ver"
  else
    warn "python3 not found (strongly recommended for helper scripts)"
    MISSING_OPTIONAL+=("python3")
    suggest_install "python3" \
      "sudo apt install -y python3 python3-pip" \
      "brew install python3"
  fi
}

# ---------------------------------------------------------------------------
# Check: docker
# ---------------------------------------------------------------------------
check_docker() {
  header "Docker"
  if command -v docker &>/dev/null; then
    local ver
    ver="$(docker --version 2>&1)"
    pass "$ver"
    # Check daemon reachability (non-fatal)
    if ! docker info &>/dev/null; then
      warn "docker is installed but the daemon is not reachable."
      warn "Make sure Docker is running, or that your user is in the 'docker' group."
      warn "  sudo usermod -aG docker \$USER  (then log out and back in)"
    fi
  else
    warn "docker not found (strongly recommended for local services)"
    MISSING_OPTIONAL+=("docker")
    suggest_install "docker" \
      "sudo apt install -y docker.io && sudo usermod -aG docker \$USER" \
      "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
  fi
}

# ---------------------------------------------------------------------------
# Check: OpenClaw CLI
# ---------------------------------------------------------------------------
check_openclaw() {
  header "OpenClaw CLI"
  # Try common command names / locations
  local oc_cmd=""
  for candidate in openclaw openclaw-cli; do
    if command -v "$candidate" &>/dev/null; then
      oc_cmd="$candidate"
      break
    fi
  done

  if [[ -n "$oc_cmd" ]]; then
    local ver
    ver="$("$oc_cmd" --version 2>&1 || true)"
    pass "OpenClaw: $ver"
  else
    fail "OpenClaw CLI not found"
    MISSING_REQUIRED+=("openclaw")
    if ! $CHECK_ONLY; then
      info "Install OpenClaw via npm (requires Node.js 22+ first):"
      info "  npm install -g @openclaw/cli"
      info "Then verify with: openclaw --version"
      info "Full onboarding: openclaw onboard --workspace ."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Check: workspace repo
# ---------------------------------------------------------------------------
check_workspace() {
  header "Workspace repository"
  if [[ -f "$REPO_ROOT/BOOTSTRAP.md" ]]; then
    pass "BOOTSTRAP.md found at $REPO_ROOT"
  else
    fail "BOOTSTRAP.md not found — workspace may not be properly set up"
    MISSING_REQUIRED+=("workspace")
    if ! $CHECK_ONLY; then
      info "Clone or copy the Mesha workspace into this directory."
      info "  git clone <your-repo-url> <target-dir>"
    fi
  fi

  if git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
    pass "Git repository initialized at $REPO_ROOT"
  else
    warn "No git repository found at $REPO_ROOT"
    MISSING_OPTIONAL+=("git-repo")
    if ! $CHECK_ONLY; then
      info "Initialize with: git init && git remote add origin <url>"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  header "Summary"

  if [[ ${#MISSING_REQUIRED[@]} -eq 0 && ${#MISSING_OPTIONAL[@]} -eq 0 ]]; then
    echo -e "\n  ${GREEN}${BOLD}All checks passed. This host is ready.${RESET}\n"
  else
    if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
      echo -e "\n  ${RED}${BOLD}Required tools missing:${RESET}"
      for t in "${MISSING_REQUIRED[@]}"; do
        echo -e "    ${RED}✗ $t${RESET}"
      done
    fi
    if [[ ${#MISSING_OPTIONAL[@]} -gt 0 ]]; then
      echo -e "\n  ${YELLOW}${BOLD}Recommended tools missing:${RESET}"
      for t in "${MISSING_OPTIONAL[@]}"; do
        echo -e "    ${YELLOW}⚠ $t${RESET}"
      done
    fi
  fi

  echo ""
  echo -e "  ${BOLD}Next steps:${RESET}"
  if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
    echo "    1. Install the missing required tools listed above."
    echo "    2. Re-run this script to confirm they are present."
    echo "    3. Then run: bash scripts/activate-workspace.sh"
  else
    echo "    1. Run the health check:    bash scripts/doctor.sh"
    echo "    2. Activate the workspace:  bash scripts/activate-workspace.sh"
    echo "    3. Open OpenClaw and paste the activation prompt from BOOTSTRAP.md."
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}Mesha Community Infrastructure Operator — Bootstrap${RESET}"
echo -e "Repo root: ${REPO_ROOT}"
[[ "$CHECK_ONLY" == true ]] && echo -e "Mode: ${YELLOW}check-only (no changes)${RESET}"

check_git
check_node
check_ssh
check_curl
check_jq
check_python3
check_docker
check_openclaw
check_workspace

print_summary

# Exit with failure code if any required tools are missing
if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
  exit 1
fi
exit 0
