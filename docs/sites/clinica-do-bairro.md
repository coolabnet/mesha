# Site: Clínica do Bairro

**Address:** Rua da Saúde 45, Bairro Novo
**Coordinates:** -15.8034, -47.9298
**Node count:** 1
**Node role:** gateway (degraded — see Known Issues)
**Last updated:** 2026-03-16

---

## Site overview

The Clínica do Bairro hosts one outdoor antenna node (`lm-clinica-antena`) on its south wall. The node acts as a gateway, providing local connectivity for clinic staff and patients, and as a relay hop for the neighborhood south of Rua da Saúde.

The node's status is currently **degraded**: firmware is one major release behind, and link quality to `lm-escola-telhado` has worsened since a new building was constructed on the same street. Antenna repositioning is a known pending action.

**Nodes at this site:**

| Node name | Hostname | Model | Role | Status |
|-----------|----------|-------|------|--------|
| Clínica do Bairro - Antena | `lm-clinica-antena` | Ubiquiti NanoStation M5 | gateway | degraded |

---

## Physical layout

### Outdoor antenna node

- Mounted on a J-arm bracket on the south exterior wall of the clinic building, approximately 3.5 m above ground level.
- The south wall faces toward Rua das Acácias and the general direction of the school. However, a new residential building constructed in late 2024 now partially blocks the line-of-sight.
- Power cable runs from the antenna through a small wall penetration into the server/pharmacy storage room (sala de medicamentos), where the PoE injector is located.
- The PoE injector sits on a shelf in the pharmacy storage room, next to the medication cabinet. The shelf is accessible only to clinic staff.

### Power supply

- Grid power only. No UPS at this site.
- Power cuts bring the node offline immediately. Recovery requires the node to boot automatically, which it does reliably when power is restored (Ubiquiti NanoStation M5 does not have the flash corruption issue of smaller routers).
- The clinic shares a circuit with the adjacent pharmacy. Tripped breakers in the pharmacy can also cut the node's power.

### Cable summary

```
NanoStation M5 (south wall, 3.5 m height)
    → PoE passive cable, ~12 m, through wall penetration
    → PoE injector, pharmacy storage room shelf
    → Cat5e, ~2 m
    → Clinic's network switch (under the reception desk)
```

---

## Network details

### Antenna node

- **Model:** Ubiquiti NanoStation M5 (outdoor directional, 5 GHz)
- **Firmware:** LibreMesh 2022.12 — **one major release behind target (2023.09)**
- **Role:** Gateway — provides uplink for clinic, also a relay hop for southern neighborhood nodes
- **Uplink:** VIVO residential fiber (25 Mbps, shared with clinic administrative use)
- **Mesh links:** Primary link to `lm-escola-telhado`. Link has degraded since October 2024 due to partial obstruction from new construction. Signal measured at approximately -78 dBm (below ideal -75 dBm threshold for reliable relay).
- **SSID:** Community SSID on 5 GHz. Also broadcasts a clinic-internal SSID on 2.4 GHz for patient waiting area (configured as a separate VLAN by the clinic's IT person).

### Firmware note

The NanoStation is on LibreMesh 2022.12. It is in the `trailing` upgrade ring in `desired-state/mesh/community-profile/rollout-policy.yaml`, meaning it receives firmware upgrades last and requires human review before each upgrade. Reason: limited physical access and the current degraded status make it higher risk during any rollout.

---

## Access and contacts

### Primary contact

**Enfermeira Sandra**
Phone: +55 61 99800-0002
Available: Monday–Friday 8h–17h, Saturday 8h–12h
She coordinates physical access to the server/pharmacy room. She is familiar with the node and has been briefed on what to do when it goes offline (power-cycle the PoE injector if the node does not recover within 10 minutes of a power outage).

### Clinic operating hours

| Day | Hours |
|-----|-------|
| Monday–Friday | 08h–17h |
| Saturday | 08h–12h |
| Sunday | Closed |

**Critical constraint: do not reboot the gateway node during clinic operating hours.**

The node provides connectivity for the clinic's electronic records system. A reboot during operating hours disrupts patient record access and causes staff to fall back to paper records, which creates extra work and administrative burden. Any maintenance requiring a node reboot must be scheduled for:

- After 17h on weekdays
- After 12h on Saturdays
- Before 08h on any weekday

This aligns with the preferred change windows in `desired-state/mesh/community-profile/rollout-policy.yaml` (Sunday 05h–08h or weeknight 22h–23h30).

### After-hours access

There is no permanent on-site contact outside operating hours. For emergency physical access outside clinic hours, contact Enfermeira Sandra on her personal phone. She can arrange access through the building administrator.

For emergencies that do not require physical access (e.g., power outage recovery), the node usually recovers automatically when power is restored. Enfermeira Sandra can power-cycle the PoE injector remotely via a smart plug — ask her to do this before requesting a physical visit.

---

## Known issues

### 1. Degraded link to escola-telhado

- **Symptom:** Signal from `lm-escola-telhado` is below -75 dBm and variable. During peak traffic times, packet loss is 3–8%.
- **Root cause:** New residential building on Rua da Saúde (constructed ~October 2024) partially blocks line-of-sight from the clinic's south wall to the school rooftop.
- **Current status:** Node is functional but unreliable as a relay hop. Downstream nodes that depend on this relay experience intermittent degradation.
- **Proposed fix:** Reposition the NanoStation to the west side of the roof (requires a new mast and cable run, estimated 2–3 hours of work). Alternatively, add a new relay node on the rooftop of the new building (requires negotiation with building management).
- **Workaround in use:** Mesh routing has partially rerouted traffic through Ponto Comunitário Morro, adding one hop for the southern neighborhood but maintaining basic connectivity.

### 2. Firmware one release behind

- **Symptom:** Node is on LibreMesh 2022.12 while the community target is 2023.09.
- **Reason for delay:** The degraded link situation means a failed firmware upgrade could leave the site without network access and require a physical visit. This risk has deferred the upgrade.
- **Action plan:** Upgrade to 2023.09 as part of the next planned maintenance visit, after scheduling within the trailing ring protocol. Requires scheduling outside clinic operating hours and having a field maintainer physically present.

### 3. No UPS — power cuts take node offline

- **Symptom:** Any power cut at the clinic or on the local grid takes the node offline until power is restored.
- **Recovery:** Node boots automatically and rejoins the mesh within ~3 minutes of power restoration. No manual intervention normally required.
- **Workaround:** Enfermeira Sandra has been shown how to power-cycle the PoE injector in case the node does not recover automatically.
- **Long-term fix:** Install a small UPS on the PoE injector circuit. The clinic has expressed willingness to host one if the community provides it.

---

## Maintenance history

### 2025-12-10 — Link quality investigation

- Remote diagnostic via mesh-readonly skill.
- Confirmed degraded link to `lm-escola-telhado`. Signal measured at -78 dBm.
- Identified new building obstruction as likely cause by comparing coordinates and known construction timeline.
- No physical visit. Remote observation only.
- Opened pending action: antenna repositioning assessment.

### 2025-07-22 — Firmware check and deferred upgrade

- Remote check confirmed node on LibreMesh 2022.12.
- Upgrade to 2023.09 was planned for this window but deferred because the link was already borderline and a failed upgrade would require immediate physical recovery.
- Upgrade moved to trailing ring with manual review requirement.
- Enfermeira Sandra briefed on PoE injector power-cycle procedure.

### 2024-09-15 — Initial installation and configuration

- NanoStation M5 installed on south wall bracket.
- PoE injector placed in pharmacy storage room.
- VIVO uplink connected and tested.
- Clinic-internal SSID configured for patient waiting area.
- Community SSID confirmed working.
- Site note created.

---

## Photos and diagrams

- Installation photos (September 2024): stored in community shared drive, folder "mesha-instalacoes/clinica-do-bairro/2024-09".
- No updated photos since the new building obstruction was identified. A comparison photo showing the obstruction would be useful — add during next site visit.
- No cable diagram yet. One should be drawn and added during the antenna repositioning visit.
