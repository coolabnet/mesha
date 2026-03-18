# Run Mesha

## Fastest Path To First Real Mesh Status

```bash
# 0. Safest first proof without touching a real mesh
bash scripts/test-compose-phase1.sh

# 1. Validate the workspace and print the activation prompt
bash scripts/doctor.sh
bash scripts/activate-workspace.sh

# 2. Start OpenClaw
openclaw gateway start
openclaw chat --workspace "$(pwd)"

# 3. Paste the activation prompt printed by activate-workspace.sh

# 4. If you are already connected to LibreMesh, bootstrap discovery
bash scripts/discover-from-thisnode.sh --plan
bash scripts/discover-from-thisnode.sh

# 5. Review and merge:
#    exports/discovery/latest-candidate-node.yaml
#    exports/discovery/latest-candidate-gateway.yaml

# 6. Verify the live mesh reader
bash skills/mesh-readonly/scripts/run-mesh-readonly.sh --plan
bash skills/mesh-readonly/scripts/run-mesh-readonly.sh

# 7. Write one cached snapshot now
bash scripts/mesh-heartbeat.sh
```

If you are not connected to LibreMesh yet, skip the `thisnode.info` bootstrap step and seed `inventories/` manually with real node targets first.
After step 7, schedule `bash scripts/mesh-heartbeat.sh` with cron or systemd on the ops host.

## Telegram

To use the standalone Telegram adapter:

```bash
cd adapters/channels/telegram
node adapter.mjs
```

Requires `.env` with:
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_MAINTAINER_IDS`
- `TELEGRAM_LEAD_MAINTAINER_IDS`
- `OPERATOR_ENDPOINT` (default: http://localhost:3000)

## Notes

- `inventories/` is the human-maintained source for identity and site context.
- `exports/mesh/latest.json` is the machine-managed cached status.
- The Mesha specialist skills are workspace agents loaded through the activation prompt, not CLI-installable packages.
