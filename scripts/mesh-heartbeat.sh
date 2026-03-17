#!/usr/bin/env bash
# scripts/mesh-heartbeat.sh
#
# Collect a live mesh snapshot on a schedule and persist it under exports/mesh/.
# This keeps derived observed state fresh without overwriting curated inventory.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/skills/mesh-readonly/scripts/run-mesh-readonly.sh"
EXPORT_DIR="$REPO_ROOT/exports/mesh"
SNAPSHOT_DIR="$EXPORT_DIR/snapshots"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
SNAPSHOT_FILE="$SNAPSHOT_DIR/$TIMESTAMP.json"
LATEST_FILE="$EXPORT_DIR/latest.json"
SUMMARY_FILE="$EXPORT_DIR/latest-summary.txt"

if [[ "${1:-}" == "--plan" ]]; then
    bash "$RUNNER" "$@"
    exit 0
fi

mkdir -p "$SNAPSHOT_DIR"

bash "$RUNNER" "$@" > "$SNAPSHOT_FILE"

python3 - "$LATEST_FILE" "$SUMMARY_FILE" <<'PYEOF'
import json
import pathlib
import sys

latest_path = pathlib.Path(sys.argv[1])
summary_path = pathlib.Path(sys.argv[2])
snapshot_path = pathlib.Path(sys.argv[3])

with snapshot_path.open("r", encoding="utf-8") as handle:
    payload = json.load(handle)

if payload.get("mode") == "plan":
    raise SystemExit("Refusing to promote --plan output into exports/mesh/latest.json")

snapshot_path.replace(latest_path)

summary = payload.get("summary", {})
lines = [
    f"collected_at: {payload.get('collected_at', 'unknown')}",
    f"overall: {summary.get('overall', 'no summary available')}",
]

for section_name in ("confirmed_findings", "possible_causes", "recommended_next_steps"):
    items = summary.get(section_name) or []
    if items:
        lines.append(f"{section_name}:")
        lines.extend(f"- {item}" for item in items)

summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PYEOF

printf 'Snapshot written to %s\n' "$SNAPSHOT_FILE"
printf 'Latest snapshot updated at %s\n' "$LATEST_FILE"
printf 'Summary written to %s\n' "$SUMMARY_FILE"
