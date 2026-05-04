#!/usr/bin/env bash
# run-testbed-adapter.sh — Path wrapper to run adapter scripts against the test bed
#
# Temporarily symlinks testbed inventories/ and desired-state/ into the repo
# root so adapter scripts with hardcoded paths work against QEMU VM topology.
#
# Usage: run-testbed-adapter.sh <adapter-script> [args...]
#
# Environment variables set for adapter scripts:
#   REPO_ROOT       — testbed config directory
#   WORKSPACE_ROOT  — testbed config directory
#   GIT_SSH_COMMAND — SSH config pointing to test bed keys

set -euo pipefail

REPO_ROOT_REAL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTBED_CONFIG="${REPO_ROOT_REAL}/testbed/config"

# ─── Usage ───
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <adapter-script> [args...]" >&2
    echo "" >&2
    echo "Runs an adapter script with testbed inventories/desired-state symlinked" >&2
    echo "into the repo root. Restores originals on exit." >&2
    exit 1
fi

ADAPTER_SCRIPT="$1"
shift
ADAPTER_ARGS=("$@")

# ─── Validate adapter script exists ───
if [[ ! -f "$ADAPTER_SCRIPT" ]]; then
    # Try relative to repo root
    if [[ -f "${REPO_ROOT_REAL}/${ADAPTER_SCRIPT}" ]]; then
        ADAPTER_SCRIPT="${REPO_ROOT_REAL}/${ADAPTER_SCRIPT}"
    else
        echo "ERROR: Adapter script not found: ${ADAPTER_SCRIPT}" >&2
        exit 1
    fi
fi

# ─── Resolve SSH config ───
# Replace __REPO_ROOT__ placeholder with absolute path
SSH_KEY="${REPO_ROOT_REAL}/testbed/run/ssh-keys/id_ed25519"
SSH_CONFIG_RESOLVED="${TESTBED_CONFIG}/ssh-config.resolved"
SSH_CONFIG_TEMPLATE="${TESTBED_CONFIG}/ssh-config"

if [[ -f "$SSH_CONFIG_RESOLVED" ]]; then
    SSH_CONFIG="$SSH_CONFIG_RESOLVED"
else
    # Generate resolved config from template
    SSH_CONFIG=$(mktemp /tmp/mesha-ssh-config.XXXXXX)
    sed "s|__REPO_ROOT__|${REPO_ROOT_REAL}|g" "$SSH_CONFIG_TEMPLATE" > "$SSH_CONFIG"
fi

# ─── Backup and symlink function ───
BACKUP_DIR="${REPO_ROOT_REAL}/.testbed-backup"

backup_and_link() {
    local name="$1"
    local target="${REPO_ROOT_REAL}/${name}"
    local source="${TESTBED_CONFIG}/${name}"

    # Idempotency: if already a symlink to our target, skip
    if [[ -L "$target" ]]; then
        local current
        current="$(readlink "$target")"
        if [[ "$current" == "$source" ]]; then
            return 0
        fi
    fi

    # Back up existing real directory
    if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        if [[ ! -e "${BACKUP_DIR}/${name}" ]]; then
            mv "$target" "${BACKUP_DIR}/${name}"
            echo "  Backed up ${name}/ to ${BACKUP_DIR}/${name}" >&2
        else
            # Backup already exists — just remove current (already backed up)
            rm -rf "$target"
        fi
    fi

    # Remove stale symlink if any
    if [[ -L "$target" ]]; then
        unlink "$target"
    fi

    # Create symlink
    ln -s "$source" "$target"
    echo "  Linked ${name}/ -> testbed/config/${name}/" >&2
}

# ─── Restore function ───
restore() {
    local name="$1"
    local target="${REPO_ROOT_REAL}/${name}"

    # Only restore if it's our symlink
    if [[ -L "$target" ]]; then
        unlink "$target"
    fi

    # Restore backup if it exists
    if [[ -e "${BACKUP_DIR}/${name}" ]]; then
        mv "${BACKUP_DIR}/${name}" "$target"
        echo "  Restored ${name}/ from backup" >&2
    fi
}

cleanup() {
    echo "" >&2
    echo "Restoring original inventories/ and desired-state/..." >&2
    restore "inventories"
    restore "desired-state"
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    # Clean up SSH wrapper and resolved config
    rm -rf "${SSH_WRAPPER_DIR:-}" 2>/dev/null || true
    # Clean temp ssh config if we created one
    case "${SSH_CONFIG:-}" in /tmp/mesha-ssh-config.*) rm -f "$SSH_CONFIG" ;; esac
    echo "Done." >&2
}

trap cleanup EXIT

# ─── Set up symlinks ───
echo "Setting up testbed adapter environment..." >&2
backup_and_link "inventories"
backup_and_link "desired-state"

# ─── Export environment variables for adapter scripts ───
export REPO_ROOT="$TESTBED_CONFIG"
export WORKSPACE_ROOT="$TESTBED_CONFIG"
export SSH_CONFIG_PATH="${SSH_CONFIG}"
export SSH_KEY="${SSH_KEY}"
# thisnode.info resolution
HOSTALIASES_FILE="${REPO_ROOT_REAL}/testbed/run/host-aliases"
if [ -f "${HOSTALIASES_FILE}" ]; then
    export HOSTALIASES="${HOSTALIASES_FILE}"
fi
# GIT_SSH_COMMAND works for git-based adapters
export GIT_SSH_COMMAND="ssh -F ${SSH_CONFIG}"
# For adapter scripts that call ssh directly, create a wrapper
SSH_WRAPPER_DIR=$(mktemp -d /tmp/mesha-ssh-wrapper.XXXXXX)
cat > "${SSH_WRAPPER_DIR}/ssh" << 'WRAPPER'
#!/usr/bin/env bash
# SSH wrapper that injects testbed config
if [ -n "${SSH_CONFIG_PATH:-}" ] && [ -f "${SSH_CONFIG_PATH}" ]; then
    exec /usr/bin/ssh -F "${SSH_CONFIG_PATH}" "$@"
else
    exec /usr/bin/ssh "$@"
fi
WRAPPER
chmod +x "${SSH_WRAPPER_DIR}/ssh"
export PATH="${SSH_WRAPPER_DIR}:${PATH}"

echo "" >&2
echo "Running adapter: ${ADAPTER_SCRIPT} ${ADAPTER_ARGS[*]}" >&2
echo "  REPO_ROOT=${REPO_ROOT}" >&2
echo "  WORKSPACE_ROOT=${WORKSPACE_ROOT}" >&2
echo "  GIT_SSH_COMMAND=${GIT_SSH_COMMAND}" >&2
echo "" >&2

# ─── Run the adapter script ───
"$ADAPTER_SCRIPT" "${ADAPTER_ARGS[@]}"
