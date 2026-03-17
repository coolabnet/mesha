# Known Issues

This directory contains documented patterns of recurring hardware and configuration problems observed in the community mesh network.

Known issues are different from incidents. An incident is a specific event at a specific time. A known issue is a pattern: the same hardware model failing in the same way, or the same environmental condition causing the same problem across multiple sites.

When the same root cause appears twice or more, it belongs here.

---

## When to create a known-issue entry

Create an entry when:
- A problem has been observed at least twice with the same root cause
- A hardware model has a confirmed design limitation affecting field operations
- A configuration pattern reliably causes a specific failure
- A workaround has been identified that other maintainers should know about

Do not create an entry for one-off incidents. Use `logs/incidents/` for those. When a one-off incident repeats, promote it here.

**Who writes these:** `knowledge-curator`, or any maintainer who identifies a recurring pattern.

---

## File naming

One file per issue, named descriptively:

**Pattern:** `<hardware-or-pattern-slug>-<brief-issue-name>.md`

**Examples:**
- `tplink-wr841n-power-loss.md` — hardware model + failure type
- `channel-congestion-2ghz.md` — environmental pattern
- `ubiquiti-nanostation-m5-link-degradation.md` — hardware model + failure type

---

## Current known issues

| File | Hardware / Pattern | Symptom | Recurrences |
|------|--------------------|---------|-------------|
| `tplink-wr841n-power-loss.md` | TP-Link TL-WR841N v13 | Node does not recover after power cut without manual reboot | 3 |
| `channel-congestion-2ghz.md` | Any node in dense urban deployment | Mesh link quality degrades during evening peak hours | Multiple sites |

---

## Related resources

- `inventories/hardware-models.yaml` — structured notes on all hardware models in use, including flash size and firmware support status
- `logs/incidents/` — individual incident records; check here when investigating whether an issue has occurred before
- `docs/sites/` — site-specific quirks that may overlap with known hardware issues (e.g., a TL-WR841N at a site without a UPS)
