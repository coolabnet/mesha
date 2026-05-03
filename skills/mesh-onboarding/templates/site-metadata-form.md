---
# Site Metadata Form — Machine-readable front matter
# Fill in values between the quotes. Leave unknown fields as empty strings "".
# This block is read by the mesh-onboarding skill when creating inventory entries.

site_id: ""                     # Short identifier, no spaces (e.g. "clinica-bairro")
site_name: ""                   # Human-readable name (e.g. "Clínica do Bairro")
status: "planned"               # planned | surveyed | active | inactive
form_version: "1.0"
completed_by: ""                # Name of the person filling this form
completed_date: ""              # ISO date: YYYY-MM-DD
reviewed_by: ""                 # Maintainer who reviewed this form before onboarding
---

<!-- markdownlint-disable MD035 MD049 MD050 -->

# Site Metadata Form

**Instructions:** Fill in every field. Use `___` if a field is not yet known at the time of filling. Bring this form to the site visit. Update it during or immediately after the visit. Return the completed form to the community maintainer.

---

## 1. Site Identification

**Site name (short, no spaces, used in system):** ___________________________

**Site full name (human-readable):** ___________________________

**Physical address:**

```text
Street / road name and number: ___________________________
Neighbourhood / district:      ___________________________
City:                          ___________________________
State / region:                ___________________________
Postal code (if known):        ___________________________
```

**GPS coordinates:**

- Latitude:  ___________________________
- Longitude: ___________________________
- How were coordinates obtained? (phone GPS / Google Maps / measured on site): ___________________________

**What is this site used for?** (school / clinic / community centre / home / other):

___________________________

---

## 2. Site Contact

**Primary contact name:** ___________________________

**Phone (including country code):** ___________________________

**Preferred contact method** (WhatsApp / call / in person): ___________________________

**Best time to reach them:** ___________________________

**Is this person available on the day of installation?** (yes / no / needs scheduling): ___________________________

**Secondary contact name (if any):** ___________________________

**Secondary contact phone:** ___________________________

---

## 3. Power Source

**What power is available at the installation location?**

- [ ] Grid power (standard wall socket)
- [ ] Solar panel with battery
- [ ] Battery only (no solar or grid)
- [ ] PoE switch already present
- [ ] No power available (needs to be arranged)
- [ ] Other: ___________________________

**Power reliability notes** (e.g., frequent outages, generator used, stable 24/7):

___________________________

**Is a UPS (uninterruptible power supply) present or needed?** ___________________________

**Distance from power source to planned router location (approximate):** ___________________________

---

## 4. Physical Environment

**Where will the router be installed?**

- [ ] Rooftop (flat roof)
- [ ] Rooftop (sloped roof)
- [ ] Exterior wall bracket
- [ ] Pole or mast (height: ___ metres)
- [ ] Window mount (interior)
- [ ] Ceiling mount (indoor)
- [ ] Other: ___________________________

**Indoor or outdoor?**

- [ ] Outdoor (weatherproof enclosure required)
- [ ] Indoor

**Material of the mounting surface:** ___________________________

**Access to the installation location** (easy / requires ladder / requires roof hatch / restricted):

___________________________

**Any physical hazards noted?** (electrical cables, sharp edges, unstable surfaces):

___________________________

---

## 5. Line-of-Sight Notes

**Name of the nearest existing mesh node this router should connect to:**

___________________________

**Estimated distance to that node (approximate):** ___________________________

**Is there a clear line of sight to that node?** (yes / partial / no / not confirmed yet): ___________________________

**Obstacles noted between this site and the nearest node** (buildings, trees, hills):

___________________________

**If no clear line of sight: is there an alternative relay node in range?**

___________________________

**Notes from visual survey** (describe what you can see from the planned mounting point):

___________________________

---

## 6. Hardware

**Hardware model being installed** (e.g., TP-Link CPE510 v3, GL.iNet GL-AR750S):

___________________________

**MAC address** (from label on device, format aa:bb:cc:dd:ee:ff):

___________________________

**Serial number** (optional, from label):

___________________________

**Is this a new device or a repurposed device?** ___________________________

**If repurposed: what was it used for before?** ___________________________

**Firmware to be installed** (confirm with maintainer before noting):

___________________________

---

## 7. Planned Node Role

**What role will this node play in the mesh?**

- [ ] Gateway — has internet uplink, connects the mesh to the internet
- [ ] Relay — mesh backbone node, passes traffic between other nodes (no direct user WiFi)
- [ ] Leaf — end-point access point, provides WiFi to users at this site
- [ ] Combined relay + access point
- [ ] Other: ___________________________

**Planned hostname** (to be assigned by maintainer, format: `lm-<site>-<role>-<number>`):

___________________________

**Upgrade ring assignment** (canary / stable / trailing — assigned by maintainer):

___________________________

---

## 8. Internet Uplink Details (Gateway Nodes Only)

*Skip this section if the node is not a gateway.*

**Type of internet connection at this site:**

- [ ] Fibre (fibre optic)
- [ ] Cable / HFC
- [ ] ADSL / VDSL
- [ ] 4G/LTE modem
- [ ] Fixed wireless
- [ ] Other: ___________________________

**Connection speed (if known):** Download: \_\_\_ Mbps  Upload: \_\_\_ Mbps

**Who provides the uplink?** (ISP name or description): ___________________________

**Is the uplink dedicated for the community mesh, or shared with other users?**

___________________________

**Modem / router model providing the uplink (if relevant):** ___________________________

**IP assignment for the gateway uplink** (DHCP / static — confirm with maintainer):

___________________________

---

## 9. Special Considerations

**Any security concerns at the site?** (restricted access, need for locks, surveillance):

___________________________

**Any known interference sources nearby?** (other WiFi networks on the same channel, industrial equipment, microwave towers):

___________________________

**Language spoken by the site contact** (for community communications):

___________________________

**Notes for the installer** (anything the person doing the physical installation should know):

___________________________

**Notes for the maintainer** (anything that affects long-term operation or maintenance):

___________________________

**Outstanding items that need to be resolved before installation can proceed:**

1. ___________________________
2. ___________________________
3. ___________________________

---

## 10. Checklist Before Submitting

- [ ] All fields are filled in or marked as `___` if truly unknown
- [ ] GPS coordinates have been confirmed or flagged as estimated
- [ ] Site contact has been reached and knows about the installation
- [ ] Power source is confirmed available
- [ ] Hardware model has been checked against the community hardware inventory
- [ ] Any unresolved issues are listed in Section 9
- [ ] This form has been sent to the community maintainer

**Submitted by:** ___________________________

**Submission date:** ___________________________
