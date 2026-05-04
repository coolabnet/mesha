#!/usr/bin/env bash
# Run unit tests (no QEMU needed)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Mesha Unit Test Suite"
echo "=========================================="
echo ""

# normalize.py unit tests (Python)
python3 "${SCRIPT_DIR}/unit/test_normalize.py" -v

echo ""

# check-drift unit tests (bash)
if [ -f "${SCRIPT_DIR}/unit/test_check_drift.sh" ]; then
    echo "--- check-drift ---"
    bash "${SCRIPT_DIR}/unit/test_check_drift.sh"
    echo ""
fi
