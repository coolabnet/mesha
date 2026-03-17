# Site: Escola Municipal

**Address:** Rua das Acácias 120, Bairro Novo
**Coordinates:** -15.8012, -47.9322
**Node count:** 2
**Node roles:** 1 gateway (rooftop), 1 leaf (indoor corridor)
**Last updated:** 2026-03-16

---

## Site overview

The Escola Municipal is the primary gateway site for the community mesh. The rooftop node (`lm-escola-telhado`) holds the municipal fiber uplink and serves as the backbone anchor for all other sites. The indoor corridor node (`lm-escola-corredor`) extends coverage inside the school building and is used by staff and students.

This is the most critical site in the network. Loss of the rooftop node disconnects all downstream sites. Work here should be planned carefully and never done unilaterally.

**Nodes at this site:**

| Node name | Hostname | Model | Role | Status |
|-----------|----------|-------|------|--------|
| Escola Municipal - Telhado | `lm-escola-telhado` | TP-Link CPE510 v3 | gateway | online |
| Escola Municipal - Corredor | `lm-escola-corredor` | TP-Link TL-WR841N v13 | leaf | online |

---

## Physical layout

### Rooftop node (Telhado)

- Mounted on a 1.5 m galvanized mast on the main building rooftop, northeast corner.
- Faces north toward the water tower. Line-of-sight to Ponto Comunitário Morro is clear.
- Power cable runs from the main electrical panel in the director's office through a conduit on the exterior wall.
- Ethernet cable (Cat5e) runs from the rooftop antenna to the PoE injector inside the director's office. The injector is on the top shelf of the equipment rack, zip-tied to the cable tray.
- The rooftop hatch key is held by the janitor (Seu Raimundo). The hatch is in the hallway at the top of the back staircase.

### Indoor corridor node (Corredor)

- Wall-mounted at 2.2 m height in the main hallway, midpoint between the principal's office and the staff room.
- Powered by a standard 5V USB adapter plugged into the hallway power strip.
- Ethernet cable connects to a small unmanaged switch under the hallway power strip.
- This switch is shared with the director's office desktop computer — **do not power off the switch without warning staff**.

### Power supply

- Grid power. A small APC UPS (~300 VA) is installed under the desk in the director's office and protects the PoE injector and the small switch.
- The corridor node USB adapter is NOT on the UPS — a power cut takes it offline immediately.
- During storms, grid power fails 2–4 times per year. The rooftop node survives these on the UPS for approximately 20 minutes.

### Cable summary

```
Rooftop antenna (CPE510)
    → Cat5e, exterior conduit, ~18 m
    → PoE injector, director's office, top shelf
    → Cat5e, ~3 m
    → Small switch under desk (on UPS)
    → Director's desktop (not our equipment)

Corridor node (WR841N)
    → USB power, hallway strip (not on UPS)
    → Cat5e, ~2 m, to same small switch
```

---

## Network details

### Rooftop node

- **Model:** TP-Link CPE510 v3 (outdoor directional, 5 GHz)
- **Firmware:** LibreMesh 2023.09
- **Role:** Gateway — carries the municipal fiber uplink
- **Uplink:** Fibra da Prefeitura (ISP-provided fiber, ~50 Mbps symmetrical)
- **Mesh links:** Primary link to Ponto Comunitário Morro (SNR consistently above -65 dBm). Partial line-of-sight to Clínica do Bairro (new building partially obstructs).
- **SSID:** broadcasts community SSID on 5 GHz and 2.4 GHz as configured in `lime-community`

### Corridor node

- **Model:** TP-Link TL-WR841N v13 (indoor, 2.4 GHz only)
- **Firmware:** LibreMesh 2023.09-minimal
- **Role:** Leaf — no mesh relay, local coverage only
- **SSID:** same community SSID on 2.4 GHz
- **Known link issue:** Link quality to the rooftop node degrades in heavy rain. Suspected cause: water on the exterior wall section where the Ethernet cable exits. Recorded in known issues below.

---

## Access and contacts

### Primary contact

**Dona Lúcia (diretora)**
Phone: +55 61 99800-0001
Available: weekdays 7h–17h
She authorizes rooftop access and can unlock the equipment rack in the director's office.

### After-hours contact

**Seu Raimundo (janitor)**
Phone: listed on the internal contact sheet in `secrets/` (do not commit)
Available: weekday evenings and weekends (he lives nearby)
Holds the rooftop hatch key. Can provide physical access on short notice.

### School hours

- Classes: Monday–Friday, 7h–18h (two shifts)
- Building closed: weekends (except for community events)
- Avoid rebooting the gateway during school hours unless it is an emergency. The rooftop node reboot takes 3–5 minutes and cuts internet for all sites.

### Access procedure for rooftop

1. Call Dona Lúcia or Seu Raimundo in advance.
2. Sign in at the front desk with name, date, and reason.
3. Collect the rooftop hatch key from Seu Raimundo.
4. Return the key before leaving.
5. Log the visit in this site note.

---

## Known issues

### 1. Corridor node drops link in heavy rain

- **Node:** `lm-escola-corredor`
- **Symptom:** Link quality to rooftop drops sharply during or after heavy rain, sometimes causing the corridor node to lose mesh connectivity entirely.
- **Suspected cause:** Water ingress at the exterior wall penetration point on the Ethernet cable run. The cable was not sealed properly during initial installation.
- **Current workaround:** The node usually recovers when rain stops. If it does not, rebooting it from the hallway power strip restores connectivity within 2 minutes.
- **Action needed:** Seal the exterior wall penetration point with appropriate weatherproofing compound during next planned visit.
- **See also:** `docs/known-issues/tplink-wr841n-power-loss.md` (this model is also susceptible to flash corruption after unclean shutdown)

### 2. TL-WR841N v13 flash corruption risk

- **Node:** `lm-escola-corredor`
- **Symptom:** Node may not recover after a power cut if the filesystem was being written at the time.
- **Workaround:** A UPS or surge protector for the hallway power strip would reduce the risk. Currently not installed.
- **Reference:** `docs/known-issues/tplink-wr841n-power-loss.md` for full details and UCI watchdog configuration.

### 3. Partial obstruction to Clínica do Bairro

- **Node:** `lm-escola-telhado`
- **Symptom:** Link to `lm-clinica-antena` has degraded since a new building was constructed on Rua da Saúde (approximate date: late 2024).
- **Current status:** Link is usable but weaker than expected. May need antenna repositioning at either end.

---

## Maintenance history

### 2026-01-15 — Routine inspection and firmware verification

- Confirmed both nodes on LibreMesh 2023.09.
- Checked UPS battery status (adequate, estimated 18 months remaining).
- Verified rooftop antenna alignment — no changes needed.
- Photographed cable runs (photos: shared drive, folder "escola-jan-2026").
- No changes made. Node status confirmed: online.

### 2025-11-03 — Corridor node moved and remounted

- Corridor node was relocated from outside the principal's office to the main hallway midpoint.
- Reason: coverage was poor in the staff room and students were gathering outside the office.
- Cable extended by 1 m. New wall bracket installed.
- Coverage verified with a brief walk-test using a phone.

### 2025-08-20 — Initial installation

- Rooftop node installed on mast. Fiber uplink connected and tested.
- Corridor node installed in hallway.
- Community SSID confirmed working at both locations.
- Site note created, contacts documented.

---

## Photos and diagrams

- Installation photos (August 2025): stored in community shared drive, folder "mesha-instalacoes/escola-municipal/2025-08".
- Cable diagram: hand-drawn sketch included in the shared drive folder above.
- No digital diagrams yet. A network diagram for this site is on the to-do list.
