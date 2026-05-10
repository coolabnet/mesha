#!/usr/bin/env bash
# Compatibility wrapper: QEMU simulation tests live in ../libremesh-lab.
set -euo pipefail

MESHA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${MESHA_ROOT}/scripts/libremesh-lab.sh" test "$@"
