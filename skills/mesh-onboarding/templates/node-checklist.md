# Node Installation Checklist

**For: Field volunteers installing a community mesh router**

Use this checklist every time you install a new node. Work through each section in order. Check off each item as you complete it. If you get stuck, stop and contact the community maintainer before continuing.

---

## Section 1 — Before You Go to the Site

Complete this section at home or the community office, before you travel to the installation site.

### Hardware

- [ ] I have the router in hand and the model name is confirmed (check the label on the back)
- [ ] I have the power adapter that matches this router model
- [ ] I have an ethernet cable (at least 1 metre) for connecting the router to a switch, modem, or your laptop
- [ ] If this is an outdoor router: I have a weatherproof enclosure, cable gland, and outdoor-rated ethernet cable
- [ ] If power-over-ethernet (PoE) is needed: I have the correct PoE injector or switch

### Firmware and SSH Key

- [ ] The community maintainer has confirmed the correct firmware image file name for this router model
- [ ] I have the firmware image file on my laptop (or the maintainer will apply it remotely)
- [ ] My SSH public key has been added to the community authorized keys list (ask the maintainer if unsure)
- [ ] I have tested SSH login on at least one existing mesh node before this trip

### Site Information

- [ ] I know the exact physical address or GPS coordinates of the site
- [ ] I have the name and phone number of the site contact person
- [ ] I know where power is available at the site (wall socket, PoE switch, solar panel)
- [ ] I know the planned mounting location (rooftop, wall bracket, window mount, pole)
- [ ] I have confirmed the site contact will be available to let me in on the day

### Approvals

- [ ] The community maintainer has approved the node configuration (hostname, role, settings)
- [ ] I have the node hostname assigned by the maintainer (example: `lm-clinica-antena`)
- [ ] I have the provisional inventory entry reference (site name and node ID)

---

## Section 2 — Physical Installation Checklist

Complete this section on-site during physical installation.

### Power

- [ ] Power outlet or PoE source is available and working (test with a phone charger if unsure)
- [ ] Power cable is long enough to reach the mount location without strain
- [ ] If outdoor: power cable is rated for outdoor use or is routed through conduit
- [ ] Power is NOT connected to the router yet (connect power last)

### Cable Routing

- [ ] Ethernet cable route is planned and clear of sharp edges, heat sources, and foot traffic
- [ ] Cable is long enough to reach from the router to the switch/modem/uplink point
- [ ] Cable is secured along the route (cable clips, zip ties) so it cannot be tripped over or pulled out
- [ ] If passing through walls or ceilings: holes are sealed against weather and pests

### Mounting and Antenna Direction

- [ ] The router is mounted securely at the planned location (it does not move when you push it gently)
- [ ] If directional antenna (outdoor point-to-point router): the antenna is pointed toward the nearest node it should connect to
- [ ] Line of sight to the nearest existing node has been visually confirmed (or noted as blocked)
- [ ] If rooftop: the router is above the roof edge or parapet for clear line of sight
- [ ] The router is not mounted behind metal structures, inside metal enclosures, or directly against reinforced concrete

### Weather Protection (Outdoor Only)

- [ ] The router body is inside a weatherproof enclosure (IP65 or better)
- [ ] All cable entry points use waterproof cable glands or self-amalgamating tape
- [ ] The enclosure has ventilation or is UV-rated (direct sun heats enclosures quickly)
- [ ] The mounting bracket is rust-proof or stainless steel

---

## Section 3 — First Boot and SSH Access

Complete this section after you connect power to the router for the first time.

### Powering On

- [ ] Connect the ethernet cable between the router and the network switch or your laptop
- [ ] Connect the power adapter (or PoE cable) to the router
- [ ] Wait 2 minutes for the router to finish booting (the lights will stop flashing)

### Connecting to the Router

- [ ] Connect your laptop to the router's WiFi network (the SSID is usually printed on the label), OR connect your laptop directly via ethernet cable to the router's LAN port
- [ ] Open a terminal and try: `ssh root@192.168.1.1` (or the default IP for this router model — ask the maintainer if you are unsure)
- [ ] If the router already has LibreMesh installed, the default password is printed on the label or was set by the maintainer — use that password

> **Security note:** Do not write the SSH password or default credentials in any shared document. Ask the maintainer for credentials through a private message only.

### Changing the Password (if not already set by the maintainer)

- [ ] After logging in via SSH, run: `passwd root`
- [ ] Enter a strong password (at least 12 characters)
- [ ] Confirm the password
- [ ] Write it down in the community password manager — do not store it only in your head

### Confirming the Router is Running

- [ ] Run: `uname -a` — you should see a Linux kernel version line
- [ ] Run: `cat /etc/openwrt_release` — you should see a LibreMesh or OpenWrt version
- [ ] Take a photo of the screen showing the firmware version (useful for documentation)
- [ ] Send the firmware version to the maintainer so they can confirm it matches the approved version for this hardware model

---

## Section 4 — Applying Community Config

This section applies the community settings to the router. **Do this only after you have confirmation from the maintainer that the config has been approved.**

- [ ] Contact the maintainer and confirm they are ready to apply the config remotely, OR that they have given you the exact commands to run
- [ ] The maintainer will apply the configuration using the `mesh-onboarding` skill (remotely), or will give you specific commands to paste into the SSH session
- [ ] After the config is applied, the maintainer will ask you to run: `lime-config`
- [ ] Wait 30 seconds after running `lime-config`, then run: `logread | tail -20` — copy the output and send it to the maintainer if you see any lines containing the words `error` or `failed`
- [ ] Only reboot when the maintainer confirms there are no errors: `reboot`
- [ ] Wait 2–3 minutes for the node to come back up

> **Important:** Do not run any commands that are not given to you by the maintainer, and do not change any settings manually. All configuration comes from the community profile managed by the maintainer.

### After Reboot

- [ ] SSH back into the router: `ssh root@<hostname or IP>`
- [ ] Run: `hostname` — it should show the assigned hostname (example: `lm-clinica-antena`)
- [ ] Run: `iwinfo` — you should see the community WiFi network name (SSID) in the output
- [ ] Run: `logread | tail -20` — check for any lines that say `error` or `failed` and report them to the maintainer

---

## Section 5 — Mesh Join Verification

This section confirms the new node has joined the community mesh network.

- [ ] From another mesh node (the maintainer will usually do this remotely): run `ping <hostname>` where `<hostname>` is the new node's hostname — it should respond
- [ ] The maintainer will check the mesh topology and confirm the new node appears with at least one neighbor
- [ ] If you have a phone or laptop connected to the mesh WiFi: open a browser and go to `http://<hostname>` — you should see the router's management page
- [ ] The community SSID (the shared WiFi network name) should be visible and connectable from a nearby device
- [ ] Test connecting to the community WiFi from a phone or laptop — you should be able to open websites or reach local services

### If the Node Does Not Appear in the Mesh

- [ ] Check that the ethernet cable between the router and the rest of the network is firmly connected at both ends
- [ ] Check that the community SSID in `iwinfo` output matches exactly (capitalization matters)
- [ ] Report the situation to the maintainer with a copy of the `logread | tail -30` output
- [ ] Do not leave the site until the node is confirmed as visible in the mesh, or the maintainer has told you it is OK to leave

---

## Section 6 — Final Documentation Step

Before you leave the site, collect and share the following information with the maintainer.

- [ ] Node hostname: ___________________________
- [ ] Site name: ___________________________
- [ ] Hardware model: ___________________________
- [ ] Physical mounting location (describe briefly): ___________________________
- [ ] Power source (wall socket / PoE / solar): ___________________________
- [ ] Cable run length (approximate): ___________________________
- [ ] Line-of-sight to nearest node (clear / partial / obstructed): ___________________________
- [ ] Site contact name and phone (if not already recorded): ___________________________
- [ ] Any issues noticed during installation: ___________________________
- [ ] Installation date: ___________________________
- [ ] Your name (installer): ___________________________

Send this information to the maintainer via the agreed community channel (WhatsApp, Telegram, or email). The maintainer will update the network inventory and write the installation record.

- [ ] Information sent to maintainer
- [ ] Maintainer confirmed the node is active in the inventory (`status: active` set in mesh-nodes.yaml)
- [ ] Maintainer confirmed that a maintenance log entry has been written for this installation
- [ ] You have left the site tidy (cables secured, no tools left behind, access point locked if applicable)

---

**Installation complete. Thank you for your work on the community network.**

If you encounter any problem not covered here, contact the maintainer before improvising.
