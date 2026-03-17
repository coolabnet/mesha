# Known Issue: Channel congestion on 2.4 GHz in dense urban deployments

```
hardware-model-or-pattern: Any LibreMesh node in a dense urban deployment using 2.4 GHz for mesh or client access
symptoms: Mesh link quality degrades during peak hours (evenings), clients disconnect or see high latency, throughput drops noticeably
confirmed-root-cause: 2.4 GHz channel congestion from neighboring WiFi networks (apartments, businesses) sharing the same or adjacent channels
fix-or-workaround: Use 5 GHz for mesh backbone links where hardware supports it; restrict 2.4 GHz to channel 1 or channel 11 only; enable 5 GHz client access where possible
first-observed: 2025-09-03
recurrence-count: multiple sites (ongoing in Bairro Novo)
```

---

## Description

The 2.4 GHz band has only three non-overlapping channels (1, 6, and 11) in most regulatory domains. In dense urban areas with many WiFi networks from neighboring apartments, offices, and businesses, all three channels can become heavily congested during peak usage hours (typically 19h–23h on weekdays and weekend evenings).

When a community mesh node is using a congested 2.4 GHz channel for mesh backhaul links, the effective throughput drops and latency increases — even if the signal level between nodes is adequate. This appears as degraded connection quality to end users despite the hardware being technically functional.

This is a spectrum management problem, not a hardware defect. It cannot be fully eliminated in a dense urban environment, but it can be significantly mitigated by moving mesh backbone traffic to 5 GHz.

---

## Affected sites in this network

| Site | Node | 2.4 GHz use | 5 GHz available | Mitigation status |
|------|------|-------------|-----------------|------------------|
| Escola Municipal | lm-escola-corredor (TL-WR841N v13) | Mesh + client | No (hardware limitation) | Partial — channel fixed to ch1 |
| Clínica do Bairro | lm-clinica-antena (NanoStation M5) | Not used (5 GHz only) | Yes — backbone on 5 GHz | Not affected |
| Associação de Moradores | lm-associacao-salao (GL-AR750S) | Client only | Yes — mesh on 5 GHz | Not affected |
| Ponto Comunitário Morro | lm-ponto-morro (CPE510 v3) | Not used (5 GHz only) | Yes — backbone on 5 GHz | Not affected |

The main affected node is `lm-escola-corredor`, which is a 2.4 GHz-only device and cannot use 5 GHz for either mesh or client traffic.

---

## Symptoms observed

- Client devices connected to `lm-escola-corredor` experience high latency (>150 ms) during evenings
- Some clients disconnect and fail to reconnect to the 2.4 GHz SSID
- `batctl n` on nearby nodes shows variable link quality to `lm-escola-corredor` during evening hours
- `iwinfo` on the affected node shows high noise floor (-85 dBm or above)
- Running a channel scan (see commands below) shows many competing networks on the same channel

---

## Confirmed root cause

2.4 GHz channel congestion from neighboring networks. The community mesh uses channel 6 by default in LibreMesh's default community profile, which is the most commonly used channel and thus the most congested.

A channel scan in the Escola Municipal area during evening hours typically shows:
- 8–15 competing networks on channel 6
- 3–6 competing networks on channel 1
- 4–8 competing networks on channel 11

---

## Fix and workaround

### Fix 1: move mesh backbone to 5 GHz (recommended for hardware that supports it)

For nodes with 5 GHz radios (CPE510, NanoStation M5, GL-AR750S), mesh backbone links should use 5 GHz. This is already the case for most nodes in this network. The 2.4 GHz radio should be reserved exclusively for client access.

This is configured in the `lime-community` profile at the community level. Check `desired-state/mesh/community-profile/lime-community` to confirm the radio configuration.

### Fix 2: set 2.4 GHz to channel 1 or channel 11 (for 2.4 GHz-only nodes)

For nodes that cannot use 5 GHz (like the TL-WR841N v13), fix the 2.4 GHz channel to either channel 1 or channel 11 — never auto-channel, and avoid channel 6 in congested urban areas.

**How to check the current channel:**

```bash
# SSH into the node
ssh root@<node-ip>

# Check the current radio configuration
iwinfo
# Look for the "Channel" field on the relevant interface

# Or check via UCI
uci show wireless | grep channel
```

**How to change the channel:**

```bash
# SSH into the node
ssh root@<node-ip>

# Find the radio name for 2.4 GHz (usually radio0)
uci show wireless | grep band

# Set the channel to 1 (or 11 — check which is least congested with a scan first)
uci set wireless.radio0.channel='1'
uci commit wireless

# Apply the change without rebooting
wifi reload
```

**How to scan for competing networks and choose the least congested channel:**

```bash
# SSH into the node
ssh root@<node-ip>

# Run a scan on the 2.4 GHz interface (replace wlan0 with the correct interface name)
iwinfo wlan0 scan | grep -E "ESSID|Channel|Signal"
```

Count the number of networks on each of channels 1, 6, and 11. Choose the one with fewest competing networks.

Note: channel changes applied via `wifi reload` take effect immediately but are not persistent across reboots unless committed to UCI first (done by `uci commit wireless` above).

**Applying this via the community profile (for all nodes at once):**

If the community decides to change the default 2.4 GHz channel network-wide, update the channel setting in `desired-state/mesh/community-profile/lime-community` and push it via a Class C config rollout. This is the preferred approach to avoid per-node drift.

### Fix 3: enable 5 GHz client SSID where hardware supports it

For nodes with 5 GHz radios, enable a 5 GHz client SSID alongside the 2.4 GHz SSID. Modern client devices will prefer 5 GHz when available, reducing load on the congested 2.4 GHz band.

This is already configured for most 5 GHz-capable nodes in this network.

### Fix 4: consider replacing 2.4 GHz-only nodes in congested locations

In high-congestion urban locations, 2.4 GHz-only hardware like the TL-WR841N v13 is at a structural disadvantage. If the Escola Municipal corridor node continues to cause problems despite the channel-fix workaround, replacing it with a dual-band device (e.g., GL-AR750S or TP-Link Archer C7) is the most effective long-term solution.

---

## Verification commands summary

```bash
# Check current channel and noise floor on a node
ssh root@<node-ip> "iwinfo"

# Scan for competing networks
ssh root@<node-ip> "iwinfo wlan0 scan | grep -E 'ESSID|Channel|Signal'"

# Check current UCI wireless config
ssh root@<node-ip> "uci show wireless"

# Change channel (example: set radio0 to channel 1)
ssh root@<node-ip> "uci set wireless.radio0.channel='1' && uci commit wireless && wifi reload"

# Check mesh link quality to neighbors (run from any mesh node)
ssh root@<node-ip> "batctl n"
```

---

## Occurrence history

| Date | Site | Observed symptom | Action taken |
|------|------|-----------------|-------------|
| 2025-09-03 | Escola Municipal (corredor) | Client disconnections and high latency during evening classes | First identification; channel scan run; channel changed from 6 to 1 |
| 2025-10-14 | Escola Municipal (corredor) | Recurrence of degraded performance on evenings | Verified channel 1 setting had persisted; congestion confirmed via scan; no further action taken — hardware limitation noted |
| 2025-12-01 | Escola Municipal (corredor) | Evening degradation during school event | Temporary workaround: asked users to use mobile data during the 2-hour event |
| Ongoing | Escola Municipal (corredor) | Regular evening degradation (lower severity since channel change) | Documented as ongoing; hardware replacement on long-term roadmap |
