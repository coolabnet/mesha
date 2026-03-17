# SKILL: server-readonly

## Purpose

The `server-readonly` skill safely inspects local community servers and the services running on them. It collects host health data, checks storage and memory, tests service reachability, verifies local domain resolution, and confirms offline behavior — without making any changes to the host.

This skill is the primary visibility tool for the server and local services layer.

---

## Responsibilities

### Must do

- Collect host health indicators: CPU load, memory usage, uptime, system errors in recent logs.
- Check disk and storage state: mount points, used/free space, inode usage, any filesystems near capacity.
- Test reachability of configured local services: HTTP health-check endpoints, port checks, process status.
- Verify local domain name resolution: confirm that configured domains in `desired-state/server/domains.yaml` resolve correctly on the local network.
- Check reverse proxy configuration health: are the configured routes responding as expected?
- Confirm offline behavior: can local services be reached without internet access? Test this where possible.
- Compare actual running services against the approved service catalog in `desired-state/server/service-catalog.yaml`.
- Detect services that are in the catalog but not running, or running but not in the catalog.
- Read container or service status (Docker, systemd, or equivalent) without modifying it.
- Check backup status where backup policy and logs are available.
- Summarize findings in plain, non-technical language suitable for field maintainers.
- Produce a normalized JSON or YAML snapshot of the collected state for the planning layer.
- Include recommended next steps when problems are detected.

### Must not do

- Restart, stop, or start any service.
- Modify any system configuration, file, or environment variable.
- Create or delete files on the host.
- Change any network or DNS configuration.
- Install or remove any software.
- Execute commands with side effects (writes, flushes, reloads).
- Expose secrets, credentials, or private keys in output — redact these if encountered in log reads.

---

## Inputs

- Host inventory and access configuration: `inventories/` (host addresses, SSH access info)
- Desired-state references: `desired-state/server/hosts.yaml`, `desired-state/server/domains.yaml`, `desired-state/server/service-catalog.yaml`, `desired-state/server/reverse-proxy.yaml`, `desired-state/server/backup-policy.yaml`
- Adapter outputs from `adapters/server/` (host diagnostics, service checks, DNS checks, container status)
- Optional: specific host or service name to scope the inspection
- Optional: focus area (storage, memory, services, domains, offline behavior, backup status)

---

## Outputs

- **Normalized snapshot** (JSON or YAML): structured representation of host health, storage state, service status, domain resolution results, and catalog comparison. Includes a timestamp.
- **Human summary**: plain-language description of what was found. Sections: overall host status, issues detected, services status, storage warnings, recommended next steps.
- **Catalog drift report** (when applicable): list of services that differ from the approved catalog — missing, extra, or misconfigured.
- **Offline readiness report** (when requested): confirmation of which services remain reachable without internet, and which do not.
- **Recommended next steps**: if issues are found, the smallest safe actions to investigate or resolve. May include routing to `incident-triage` or flagging for `server-services` with approval.

---

## Risk Class

**Class A — Read-only**

No approval required. This skill may be triggered directly by the frontdesk or by a maintainer without an approval gate.

---

## Activation Examples

- "Is the local video server working?"
- "Check the server health."
- "How much disk space is left?"
- "Are all local services reachable?"
- "Does the local wiki work without internet?"
- "Show me which services are running."
- "Is anything down on the community server?"
- "Check if the local domain for the media archive resolves."
- "What services are installed but not in the approved catalog?"
- "Is the backup running?"
- "Check the server and tell me if there are any problems."
- "What's the uptime on the server?"

---

## Constraints and Guardrails

1. **Read-only guarantee**: no adapter call used by this skill may trigger a write, restart, reload, or configuration change on any host. Adapter scripts must be reviewed to confirm this.
2. **Structured output required**: all data returned to the planning layer must be in normalized JSON or YAML. No raw shell output passed upstream.
3. **Timestamp all snapshots**: every snapshot must include a `collected_at` field. Stale data must not be presented as current.
4. **Credential safety**: if log or config reads encounter passwords, API keys, or private keys, these must be redacted in all outputs. Never surface secrets.
5. **Graceful degradation**: if a host is unreachable, mark it as unreachable and proceed with any remaining hosts. Do not abort a multi-host inspection because one is down.
6. **Offline operation**: the skill must be able to return the last known snapshot from local inventory when live access is unavailable. Label such data clearly as cached.
7. **Scope limiting**: if given a specific host or service, scope the inspection accordingly. Do not query all hosts for a single-host request.
8. **No speculation without basis**: if a service is unreachable, report that fact. Do not guess the cause unless there is clear supporting evidence from the collected data.
9. **Plain-language storage warnings**: translate raw byte counts and percentage figures into plain-language assessments (e.g. "storage is 89% full — consider cleanup soon").
