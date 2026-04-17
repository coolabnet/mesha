# Site Notes

Site notes are per-location documents that capture context which cannot be expressed in structured inventory fields. Where `inventories/sites.yaml` stores facts (coordinates, node list, contact phone), a site note stores the knowledge that makes those facts useful: how to physically reach the router, which rooms have coverage, what breaks during storms, who to call on a Sunday night, and what has already been tried.

---

## What site notes are for

Site notes exist to answer questions like:

- "Where exactly is the router installed?"
- "Who do I call if I need rooftop access at 6am?"
- "Has this node had recurring power issues before?"
- "What happened the last time someone visited this site?"

They are the field maintainer's cheat sheet for a location. They should be readable on a phone screen during a site visit.

---

## File naming

One file per site, named after the site's slug derived from its name in `inventories/sites.yaml`.

**Pattern:** `<site-slug>.md`

**Examples:**

- `associacao-portal-sem-porteiras.md` — for site "Associação Portal Sem Porteiras"

Use lowercase, replace spaces with hyphens, drop accents for the filename. The title inside the file should use the full proper name.

---

## Minimum sections required

Every site note must include all of the following sections:

1. **Site overview** — address, coordinates, node count, roles (gateway / relay / leaf)
2. **Physical layout** — where nodes are physically installed, cable paths, power supply location
3. **Network details** — gateway model and uplink type, SSID, mesh role, link quality notes
4. **Access and contacts** — who can provide physical access, hours of availability, how to reach them
5. **Known issues** — site-specific hardware or environment quirks, even if not yet confirmed as root causes
6. **Maintenance history** — the last 2–3 maintenance events with dates and a brief description of what was done
7. **Photos and diagrams** — a note on where installation photos are stored, or "none taken yet"

Optional sections (add when relevant):

- Power supply details (UPS capacity, solar system specs, known failure patterns)
- Coverage map or signal notes
- Security or safety notes (locked rooms, access cards, night watchman)

---

## When to update a site note

Update the site note after **every** one of these events:

- A physical site visit (planned or emergency)
- A confirmed incident at this site
- A successful or failed configuration change on a node at this site
- A change in site contact or access procedure
- A hardware swap, node addition, or node decommission
- Any new discovered quirk (power issue, interference, physical obstruction)

The `knowledge-curator` skill is responsible for updating site notes after approved operations. Field maintainers can also update notes directly after a visit.

**Rule:** if you visit a site and learn something not in the site note, add it before closing the session.

---

## Cross-references

- **Node inventory:** `inventories/mesh-nodes.yaml` — structured data for each node at this site
- **Sites inventory:** `inventories/sites.yaml` — coordinates, node list, basic contact
- **Known issues:** `docs/known-issues/` — hardware-wide patterns that affect nodes at this site
- **Incident log:** `logs/incidents/` — records of specific events at this site
- **Maintenance log:** `logs/maintenance/` — records of planned work performed at this site

---

## Current site notes

| File | Site | Nodes |
|------|------|-------|
| `associacao-portal-sem-porteiras.md` | Associação Portal Sem Porteiras | 4 (all leaf nodes) |

Sites without notes yet:

- None (all confirmed sites have notes)
