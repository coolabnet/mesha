# Known Issue: TP-Link TL-WR841N v13 — Does not recover after power loss

```text
hardware-model-or-pattern: TP-Link TL-WR841N v13
symptoms: Node goes offline after power fluctuation or unclean shutdown and does not recover without manual reboot or physical power-cycle
confirmed-root-cause: Flash filesystem corruption under unclean shutdown on 4 MB flash with JFFS2/SquashFS overlay
fix-or-workaround: Use a UPS or voltage regulator on the power circuit; configure hardware watchdog via UCI to enable automatic reboot on lockup
first-observed: 2025-06-12
recurrence-count: 3
```

---

## Description

The TP-Link TL-WR841N v13 has a 4 MB flash chip, which is the minimum supported by OpenWrt/LibreMesh. The device uses a JFFS2 overlay on top of a SquashFS base. When power is interrupted while the overlay filesystem is being written (e.g., during a firmware config commit, log rotation, or any UCI write), the overlay can become corrupted.

After corruption, the node typically boots into a degraded state or into failsafe mode. In most observed cases, it appears offline to the mesh and does not recover on its own. Power cycling the device once (removing and restoring power) usually clears the problem if the corruption is minor. In more severe cases, the overlay may need to be reset via failsafe mode, which requires physical access and basic OpenWrt knowledge.

This is not a manufacturing defect unique to a single unit — it is a known behavior of small-flash OpenWrt devices with read-write overlays when subjected to power interruptions.

---

## Affected nodes in this network

| Node | Site | UPS? | Risk level |
|------|------|------|-----------|
| None | — | — | No TL-WR841N v13 devices confirmed in current inventory |

---

## Symptoms observed

- Node goes offline during or immediately after a power fluctuation or grid outage
- Node does not respond to mesh pings after power is restored
- SSH is unreachable even when the node appears to have power
- Rebooting manually (power-cycle) usually restores normal operation
- In one case (2025-10-08), the node booted into failsafe mode and required a UCI config reset

---

## Confirmed root cause

JFFS2 overlay corruption on 4 MB flash under unclean shutdown. Documented behavior in OpenWrt for v18.06 and earlier on low-flash hardware. LibreMesh 2023.09-minimal reduces flash write frequency compared to the full build but does not eliminate the risk entirely.

Reference: OpenWrt forum thread on TL-WR841N stability (search "WR841N failsafe JFFS2 corruption").

---

## Fix and workaround

### Immediate workaround: power-cycle the node

If the node does not recover after a power cut:

1. Physically power-cycle the PoE injector or USB power adapter.
2. Wait 2–3 minutes for the node to boot.
3. Check if it rejoins the mesh (`batctl n` from a neighboring node).

If it boots into failsafe mode (LED blinks rapidly):

1. Connect via a wired Ethernet cable from a laptop.
2. Set laptop IP to `192.168.1.2`, mask `255.255.255.0`.
3. SSH to `192.168.1.1` (no password in failsafe mode).
4. Run `firstboot && reboot` to reset the overlay to factory state.
5. After reboot, re-apply the UCI configuration from the last known backup.

### Long-term fix 1: install a UPS on the power circuit

A small UPS on the circuit feeding the node's power adapter reduces the risk of unclean shutdowns during grid fluctuations. Even a 300 VA UPS (the same model used at the school director's office) provides enough bridge time to survive most brief grid interruptions.

**Status for Escola Municipal - Corredor:** UPS not yet installed. The hallway power strip is not protected. This is a planned improvement.

### Long-term fix 2: configure the hardware watchdog

The TL-WR841N v13 has a hardware watchdog that can automatically reboot the device if the software becomes unresponsive. Enabling it reduces the risk of the node hanging in a degraded state after a filesystem issue.

```bash
# Enable the hardware watchdog via UCI
# SSH into the node first: ssh root@<node-ip>

# Check if the watchdog device exists
ls /dev/watchdog*

# Configure watchdog timeout using a named UCI section (idempotent — safe to run more than once)
uci set system.watchdog=watchdog
uci set system.watchdog.timeout=30
uci set system.watchdog.max_timeout=60
uci set system.watchdog.stop_on_exit=0
uci commit system

# Enable and start the watchdog service
/etc/init.d/watchdog-kmod enable
/etc/init.d/watchdog-kmod start
```

To verify the watchdog is active:

```bash
# Check watchdog process
ps | grep watchdog

# Check that the watchdog device exists and is accessible
ls -l /dev/watchdog*
# Should show /dev/watchdog0 (or similar) if the kernel module is loaded
```

**Note:** The watchdog does not prevent filesystem corruption — it only ensures the device reboots automatically if it hangs. Combined with a UPS, these two measures significantly reduce the probability of a manual intervention being required after a power event.

### Long-term fix 3: consider replacing this hardware model

The TL-WR841N v13 is at the absolute minimum flash size for OpenWrt/LibreMesh. For indoor leaf nodes that do not need outdoor-grade hardware, a GL.iNet GL-AR750S (as used at Associação de Moradores) is a better choice: larger flash, more RAM, and more reliable under similar workloads.

**Migration note:** if replacing this node, add the new node via `docs/playbooks/node-onboarding.md` before decommissioning the old one, so coverage is not interrupted.

---

## Occurrence history

| Date | Node | Trigger | Recovery |
|------|------|---------|----------|
| None | — | No TL-WR841N v13 devices in current inventory | — |
