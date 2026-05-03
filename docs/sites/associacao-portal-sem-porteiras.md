# Site: Associação Portal Sem Porteiras

**Address:** Praça Central s/n, Bairro Novo
**Coordinates:** -15.8025, -47.9340
**Node count:** 4
**Node roles:** All leaf nodes (mesh relay within building)
**Last updated:** 2026-03-18

---

## Site overview

The Associação Portal Sem Porteiras is the primary community hub and currently the only confirmed site with active mesh nodes. All four nodes are located within the same building and form a dense local mesh topology with 22+ originators reachable through the network.

The building serves as the weekly meeting location (Thursdays 19h) and has UPS backup providing approximately 30 minutes of power during outages. The basement node (porao) provides full-building coverage and acts as a local access point.

**Nodes at this site:**

| Node name | Hostname | Model | Role | Status |
|-----------|----------|-------|------|--------|
| Porão da PSP | `porao` | UniFi-AC-MESH | leaf | online |
| Yuri - NanoStation AC | `yuri` | NanoStation AC | leaf | online |
| Marie - TL-WDR3500 | `marie` | TL-WDR3500 v1 | leaf | online |
| Carlinhos - CPE210 | `carlinhos` | CPE210 v1.1 | leaf | online |

---

## Physical layout

### Building

- Community center building with central plaza location
- Three floors plus basement area
- UPS installed providing ~30 min backup during power outages
- Weekly community meetings on Thursdays at 19h

### Node locations

**Porão da PSP (Basement):**

- UniFi-AC-MESH dual-band access point
- Provides full-building coverage
- Default gateway via 10.208.39.98
- 22+ mesh originators reachable

**Yuri - NanoStation AC:**

- Wall-mounted indoor unit
- Single ethernet interface (eth0)
- Dual-band AC wave2

**Marie - TL-WDR3500:**

- Indoor router with WiFi
- Dual ethernet ports (eth0/eth1)
- Standard indoor placement

**Carlinhos - CPE210:**

- 5GHz CPE unit
- Dedicated mesh backhaul link
- Outdoor-rated hardware used indoors

### Power supply

- Grid power with UPS backup
- UPS provides approximately 30 minutes of backup power
- Key held by Marcos and one deputy

---

## Network details

All nodes run LibreRouterOs firmware:

| Node | Firmware | Status |
|------|----------|--------|
| porao | LibreRouterOs 1.5-SNAPSHOT | online |
| yuri | LibreRouterOs 1.5-SNAPSHOT | online |
| marie | LibreRouterOs 1.5 | online |
| carlinhos | LibreRouterOs 1.5 | online |

All nodes are reachable via SSH and participate in the mesh with 22+ originators visible from the basement node. No gateway functionality has been confirmed at this site — all nodes currently operate as leaf nodes.

---

## Access and contacts

### Primary contact

**Presidente Marcos**
Phone: +55 61 99800-0003
Role: Site contact, holds UPS and building keys

### Site hours

- Weekly meetings: Thursdays 19h
- Building access: Arranged through Marcos
- UPS key: Held by Marcos + one deputy

---

## Known issues

### 1. No confirmed gateway at this site

- All four nodes are currently configured as leaf nodes
- No upstream uplink (fiber, cable, etc.) has been confirmed
- Mesh connectivity exists but no confirmed internet gateway
- If a gateway is discovered at this site, update `inventories/gateways.yaml`

### 2. Firmware versions inconsistent

- Two nodes on 1.5-SNAPSHOT (porao, yuri)
- Two nodes on 1.5 stable (marie, carlinhos)
- Consider standardizing on stable release for production use

---

## Maintenance history

### 2026-03-18 — Site inventory confirmed

- All four nodes confirmed reachable via SSH
- Mesh topology verified: 22+ originators reachable
- UPS backup confirmed functional (~30 min capacity)
- Site documentation created
- Building coordinates verified

---

## Photos and diagrams

- No installation photos on file yet
- Consider documenting physical node locations during next visit
- Network diagram could be useful for showing mesh interconnections
