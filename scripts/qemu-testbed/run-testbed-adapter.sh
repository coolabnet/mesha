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
SSH_CONFIG="${TESTBED_CONFIG}/ssh-config.resolved"
if [[ ! -f "$SSH_CONFIG" ]]; then
    # Fallback: use template with live sed substitution
    SSH_CONFIG="${TESTBED_CONFIG}/ssh-config"
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
            echo "  Backed up ${name}/ to ${BACKUP_DIR}/${name}"
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
    echo "  Linked ${name}/ -> testbed/config/${name}/"
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
        echo "  Restored ${name}/ from backup"
    fi
}

cleanup() {
    echo ""
    echo "Restoring original inventories/ and desired-state/..."
    restore "inventories"
    restore "desired-state"
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    echo "Done."
}

trap cleanup EXIT

# ─── Set up symlinks ───
echo "Setting up testbed adapter environment..."
backup_and_link "inventories"
backup_and_link "desired-state"

# ─── Export environment variables for adapter scripts ───
export REPO_ROOT="$TESTBED_CONFIG"
export WORKSPACE_ROOT="$TESTBED_CONFIG"
export GIT_SSH_COMMAND="ssh -F ${SSH_CONFIG}"

echo ""
echo "Running adapter: ${ADAPTER_SCRIPT} ${ADAPTER_ARGS[*]}"
echo "  REPO_ROOT=${REPO_ROOT}"
echo "  WORKSPACE_ROOT=${WORKSPACE_ROOT}"
echo "  GIT_SSH_COMMAND=${GIT_SSH_COMMAND}"
echo ""

# ─── Run the adapter script ───
"$ADAPTER_SCRIPT" "${ADAPTER_ARGS[@]}"
