#!/usr/bin/env bash
# Thin Mesha wrapper for the sibling LibreMesh Lab repository.
set -euo pipefail

MESHA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_ROOT="${LIBREMESH_LAB_ROOT:-${MESHA_ROOT}/../libremesh-lab}"
LAB_CLI="${LAB_ROOT}/bin/libremesh-lab"

if [ ! -x "${LAB_CLI}" ]; then
  cat >&2 <<EOF
ERROR: LibreMesh Lab CLI not found at:
  ${LAB_CLI}

Clone or create LibreMesh Lab next to Mesha, or set LIBREMESH_LAB_ROOT
to its location.
EOF
  exit 1
fi

export MESHA_ROOT
exec "${LAB_CLI}" "$@"
