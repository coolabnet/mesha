# HEARTBEAT.md

# Keep this file empty (or with only comments) to skip heartbeat API calls.

# Recommended production pattern:
# - run `bash scripts/mesh-heartbeat.sh` from cron or a systemd timer on the
#   primary ops host
# - write machine-managed snapshots to `exports/mesh/latest.json` and
#   `exports/mesh/snapshots/*.json`
# - keep `inventories/` for seeded identity, topology context, and human notes
# - do not treat heartbeat output as a replacement for site contacts, gateway
#   ownership, or other human-maintained metadata
