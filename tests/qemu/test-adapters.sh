#!/usr/bin/env bash
# Compatibility wrapper for Mesha adapter contract tests in LibreMesh Lab.
set -euo pipefail

MESHA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAB_ROOT="${LIBREMESH_LAB_ROOT:-${MESHA_ROOT}/../libremesh-lab}"
LAB_TEST="${LAB_ROOT}/tests/qemu/test-adapters.sh"

if [ ! -f "${LAB_TEST}" ]; then
  echo "ERROR: LibreMesh Lab adapter test not found: ${LAB_TEST}" >&2
  exit 1
fi

export MESHA_ROOT
exec bash "${LAB_TEST}" "$@"
