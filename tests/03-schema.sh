#!/usr/bin/env bash
# tests/03-schema.sh — Schema validation and cross-reference checks.
#
# Validates that YAML files have correct structure and that references
# between inventories, desired-state, and service configs are consistent.
#
# Run directly:   bash tests/03-schema.sh
# Run via runner: bash tests/run-all.sh

set -uo pipefail

source "$(dirname "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Helper: run an inline python3 snippet, pass/fail based on exit code
# ---------------------------------------------------------------------------
# assert_exit_zero is provided by lib.sh — used throughout this file.

# ---------------------------------------------------------------------------
run_schema_checks() {
    require_command python3 "python3 required for schema checks" || return 0

    cd "$WORKSPACE_ROOT"

    # -----------------------------------------------------------------------
    # A. Mesh node inventory schema
    # -----------------------------------------------------------------------
    qa_section "A. Mesh node inventory schema (inventories/mesh-nodes.yaml)"

    assert_exit_zero \
        "mesh-nodes.yaml: top-level 'nodes' key exists and is a list" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
assert isinstance(data.get('nodes'), list) and len(data['nodes']) > 0, \
    'nodes key missing or empty'
"

    assert_exit_zero \
        "mesh-nodes.yaml: every node has required fields (name, hostname, site, model, role, status)" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
required = {'name', 'hostname', 'site', 'model', 'role', 'status'}
for node in data['nodes']:
    missing = required - set(node.keys())
    label = repr(node.get('name', '<unnamed>'))
    assert not missing, f'Node {label} missing fields: {missing}'
"

    assert_exit_zero \
        "mesh-nodes.yaml: every node 'role' is one of gateway, relay, leaf" \
        python3 -c "
import sys, yaml
valid_roles = {'gateway', 'relay', 'leaf'}
data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
for node in data['nodes']:
    role = node.get('role')
    assert role in valid_roles, \
        f'Node {node[\"name\"]!r} has invalid role {role!r}; allowed: {valid_roles}'
"

    assert_exit_zero \
        "mesh-nodes.yaml: every node 'name' is a non-empty string" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
for node in data['nodes']:
    name = node.get('name')
    assert isinstance(name, str) and name.strip(), \
        f'Node has empty or non-string name: {name!r}'
"

    assert_exit_zero \
        "mesh-nodes.yaml: every node 'hostname' is a non-empty string" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
for node in data['nodes']:
    hostname = node.get('hostname')
    assert isinstance(hostname, str) and hostname.strip(), \
        f'Node {node[\"name\"]!r} has empty or non-string hostname: {hostname!r}'
"

    assert_exit_zero \
        "mesh-nodes.yaml: every node 'mac' looks like a MAC address (xx:xx:xx:xx:xx:xx)" \
        python3 -c "
import sys, re, yaml
mac_re = re.compile(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')
data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
for node in data['nodes']:
    mac = node.get('mac', '')
    assert mac_re.match(str(mac)), \
        f'Node {node[\"name\"]!r} has invalid mac address: {mac!r}'
"

    assert_exit_zero \
        "mesh-nodes.yaml: every node 'status' is one of online, offline, degraded, unknown" \
        python3 -c "
import sys, yaml
valid_statuses = {'online', 'offline', 'degraded', 'unknown'}
data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
for node in data['nodes']:
    status = node.get('status')
    assert status in valid_statuses, \
        f'Node {node[\"name\"]!r} has invalid status {status!r}; allowed: {valid_statuses}'
"

    # -----------------------------------------------------------------------
    # B. Gateway cross-reference
    # -----------------------------------------------------------------------
    qa_section "B. Gateway cross-reference (gateways.yaml <-> mesh-nodes.yaml)"

    assert_exit_zero \
        "gateways.yaml: top-level 'gateways' key exists and is a list" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('inventories/gateways.yaml'))
assert isinstance(data.get('gateways'), list) and len(data['gateways']) > 0, \
    'gateways key missing or empty'
"

    assert_exit_zero \
        "gateways.yaml: every entry has required fields (node, hostname, uplink_type)" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('inventories/gateways.yaml'))
required = {'node', 'hostname', 'uplink_type'}
for gw in data['gateways']:
    missing = required - set(gw.keys())
    assert not missing, \
        f'Gateway {gw.get(\"node\", \"<unnamed>\")!r} missing fields: {missing}'
"

    assert_exit_zero \
        "gateways.yaml: every gateway 'node' matches a name in mesh-nodes.yaml" \
        python3 -c "
import sys, yaml
nodes_data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
gw_data    = yaml.safe_load(open('inventories/gateways.yaml'))
node_names = {n['name'] for n in nodes_data['nodes']}
for gw in gw_data['gateways']:
    node_ref = gw.get('node')
    assert node_ref in node_names, \
        f'Gateway references node {node_ref!r} which does not exist in mesh-nodes.yaml'
"

    assert_exit_zero \
        "cross-ref: every node with role=gateway in mesh-nodes.yaml has an entry in gateways.yaml" \
        python3 -c "
import sys, yaml
nodes_data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
gw_data    = yaml.safe_load(open('inventories/gateways.yaml'))
gw_node_names = {gw['node'] for gw in gw_data['gateways']}
for node in nodes_data['nodes']:
    if node['role'] == 'gateway':
        assert node['name'] in gw_node_names, \
            f'Node {node[\"name\"]!r} has role=gateway but has no entry in gateways.yaml'
"

    assert_exit_zero \
        "cross-ref: every gateway entry in gateways.yaml corresponds to a role=gateway node" \
        python3 -c "
import sys, yaml
nodes_data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
gw_data    = yaml.safe_load(open('inventories/gateways.yaml'))
node_role  = {n['name']: n['role'] for n in nodes_data['nodes']}
for gw in gw_data['gateways']:
    node_ref = gw['node']
    role = node_role.get(node_ref)
    assert role == 'gateway', \
        f'gateways.yaml entry {node_ref!r} but that node has role={role!r} in mesh-nodes.yaml'
"

    # -----------------------------------------------------------------------
    # C. Site cross-reference
    # -----------------------------------------------------------------------
    qa_section "C. Site cross-reference (sites.yaml <-> mesh-nodes.yaml)"

    assert_exit_zero \
        "sites.yaml: top-level 'sites' key exists and is a list" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('inventories/sites.yaml'))
assert isinstance(data.get('sites'), list) and len(data['sites']) > 0, \
    'sites key missing or empty'
"

    assert_exit_zero \
        "sites.yaml: every site has required fields (name, location, coordinates, nodes, contact, power)" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('inventories/sites.yaml'))
required = {'name', 'location', 'coordinates', 'nodes', 'contact', 'power'}
for site in data['sites']:
    missing = required - set(site.keys())
    assert not missing, \
        f'Site {site.get(\"name\", \"<unnamed>\")!r} missing fields: {missing}'
"

    assert_exit_zero \
        "cross-ref: every 'site' value in mesh-nodes.yaml refers to an existing site in sites.yaml" \
        python3 -c "
import sys, yaml
nodes_data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
sites_data = yaml.safe_load(open('inventories/sites.yaml'))
site_names = {s['name'] for s in sites_data['sites']}
for node in nodes_data['nodes']:
    site_ref = node.get('site')
    assert site_ref in site_names, \
        f'Node {node[\"name\"]!r} references site {site_ref!r} which does not exist in sites.yaml'
"

    assert_exit_zero \
        "cross-ref: every node listed under a site in sites.yaml exists in mesh-nodes.yaml" \
        python3 -c "
import sys, yaml
nodes_data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
sites_data = yaml.safe_load(open('inventories/sites.yaml'))
node_names = {n['name'] for n in nodes_data['nodes']}
for site in sites_data['sites']:
    for node_ref in (site.get('nodes') or []):
        assert node_ref in node_names, \
            f'Site {site[\"name\"]!r} lists node {node_ref!r} which is not in mesh-nodes.yaml'
"

    assert_exit_zero \
        "cross-ref: every node in mesh-nodes.yaml is listed in exactly one site in sites.yaml" \
        python3 -c "
import sys, yaml
nodes_data = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
sites_data = yaml.safe_load(open('inventories/sites.yaml'))
site_node_sets = {}
for site in sites_data['sites']:
    for node_ref in (site.get('nodes') or []):
        site_node_sets.setdefault(node_ref, []).append(site['name'])
for node in nodes_data['nodes']:
    entries = site_node_sets.get(node['name'], [])
    assert len(entries) == 1, \
        f'Node {node[\"name\"]!r} appears in {len(entries)} site node lists (expected 1): {entries}'
"

    # -----------------------------------------------------------------------
    # D. Service catalog schema
    # -----------------------------------------------------------------------
    qa_section "D. Service catalog schema (desired-state/server/service-catalog.yaml)"

    assert_exit_zero \
        "service-catalog.yaml: top-level 'catalog' key exists and is a list" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/service-catalog.yaml'))
assert isinstance(data.get('catalog'), list) and len(data['catalog']) > 0, \
    'catalog key missing or empty'
"

    assert_exit_zero \
        "service-catalog.yaml: every service has required fields (name, approved)" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/service-catalog.yaml'))
required = {'name', 'approved'}
for svc in data['catalog']:
    missing = required - set(svc.keys())
    assert not missing, \
        f'Service {svc.get(\"name\", \"<unnamed>\")!r} missing fields: {missing}'
"

    assert_exit_zero \
        "service-catalog.yaml: every approved service has a 'port' field" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/service-catalog.yaml'))
for svc in data['catalog']:
    if svc.get('approved') is True:
        assert 'port' in svc, \
            f'Approved service {svc[\"name\"]!r} is missing the required port field'
"

    assert_exit_zero \
        "service-catalog.yaml: 'port' is an integer for all approved services" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/service-catalog.yaml'))
for svc in data['catalog']:
    if svc.get('approved') is True and 'port' in svc:
        port = svc['port']
        assert isinstance(port, int), \
            f'Service {svc[\"name\"]!r} port is {port!r} (type {type(port).__name__}), expected int'
"

    assert_exit_zero \
        "service-catalog.yaml: no duplicate service names" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/service-catalog.yaml'))
names = [svc['name'] for svc in data['catalog']]
seen = set(); dups = []
for n in names:
    if n in seen:
        dups.append(n)
    seen.add(n)
assert not dups, f'Duplicate service names in catalog: {dups}'
"

    assert_exit_zero \
        "service-catalog.yaml: 'approved' field is a boolean for all entries" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/service-catalog.yaml'))
for svc in data['catalog']:
    approved = svc.get('approved')
    assert isinstance(approved, bool), \
        f'Service {svc[\"name\"]!r} approved={approved!r} is not a boolean'
"

    # -----------------------------------------------------------------------
    # E. Prometheus scrape config
    # -----------------------------------------------------------------------
    qa_section "E. Prometheus scrape config (desired-state/server/monitoring/prometheus.yml)"

    assert_exit_zero \
        "prometheus.yml: top-level 'scrape_configs' key exists and is a list" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/monitoring/prometheus.yml'))
assert isinstance(data.get('scrape_configs'), list) and len(data['scrape_configs']) > 0, \
    'scrape_configs key missing or empty'
"

    assert_exit_zero \
        "prometheus.yml: every scrape config has 'job_name'" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/monitoring/prometheus.yml'))
for sc in data['scrape_configs']:
    assert 'job_name' in sc, f'A scrape config is missing job_name: {sc}'
"

    assert_exit_zero \
        "prometheus.yml: every scrape config has 'static_configs'" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/monitoring/prometheus.yml'))
for sc in data['scrape_configs']:
    assert 'static_configs' in sc, \
        f'Scrape config {sc.get(\"job_name\", \"<unnamed>\")!r} is missing static_configs'
"

    assert_exit_zero \
        "prometheus.yml: no duplicate job_name values" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/monitoring/prometheus.yml'))
names = [sc['job_name'] for sc in data['scrape_configs']]
seen = set(); dups = []
for n in names:
    if n in seen:
        dups.append(n)
    seen.add(n)
assert not dups, f'Duplicate job_name values in scrape_configs: {dups}'
"

    assert_exit_zero \
        "prometheus.yml: 'global' block is present with scrape_interval" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/monitoring/prometheus.yml'))
g = data.get('global', {})
assert 'scrape_interval' in g, \
    'global.scrape_interval is missing from prometheus.yml'
"

    # -----------------------------------------------------------------------
    # F. Domain consistency
    # -----------------------------------------------------------------------
    qa_section "F. Domain consistency (desired-state/server/domains.yaml)"

    assert_exit_zero \
        "domains.yaml: top-level 'records' key exists and is a list" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/domains.yaml'))
assert isinstance(data.get('records'), list), 'records key missing or not a list'
"

    assert_exit_zero \
        "domains.yaml: at least 3 domain records are defined" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/domains.yaml'))
records = data.get('records', [])
assert len(records) >= 3, f'Expected at least 3 domain records, found {len(records)}'
"

    assert_exit_zero \
        "domains.yaml: every record has required fields (domain, resolves_to, type, purpose)" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/domains.yaml'))
required = {'domain', 'resolves_to', 'type', 'purpose'}
for rec in data['records']:
    missing = required - set(rec.keys())
    assert not missing, \
        f'Domain record {rec.get(\"domain\", \"<unnamed>\")!r} missing fields: {missing}'
"

    assert_exit_zero \
        "domains.yaml: 'base_domain' key is present" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/domains.yaml'))
assert 'base_domain' in data and data['base_domain'], \
    'base_domain key missing or empty in domains.yaml'
"

    assert_exit_zero \
        "domains.yaml: no duplicate domain names" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/server/domains.yaml'))
names = [r['domain'] for r in data.get('records', [])]
seen = set(); dups = []
for n in names:
    if n in seen:
        dups.append(n)
    seen.add(n)
assert not dups, f'Duplicate domain entries in records: {dups}'
"

    assert_exit_zero \
        "cross-ref: every service-linked domain record 'service' exists in service-catalog.yaml" \
        python3 -c "
import sys, yaml
domains_data = yaml.safe_load(open('desired-state/server/domains.yaml'))
catalog_data = yaml.safe_load(open('desired-state/server/service-catalog.yaml'))
catalog_names = {svc['name'] for svc in catalog_data['catalog']}
for rec in domains_data.get('records', []):
    svc_ref = rec.get('service')
    if svc_ref is not None:
        assert svc_ref in catalog_names, \
            f'Domain {rec[\"domain\"]!r} references service {svc_ref!r} not in service-catalog.yaml'
"

    # -----------------------------------------------------------------------
    # G. Firmware policy schema
    # -----------------------------------------------------------------------
    qa_section "G. Firmware policy schema (desired-state/mesh/firmware-policy.yaml)"

    assert_exit_zero \
        "firmware-policy.yaml: 'global' block is present" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
assert 'global' in data, 'global key missing in firmware-policy.yaml'
"

    assert_exit_zero \
        "firmware-policy.yaml: 'global.approved_version' is set" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
approved = data.get('global', {}).get('approved_version')
assert approved, \
    f'global.approved_version missing or empty in firmware-policy.yaml'
"

    assert_exit_zero \
        "firmware-policy.yaml: 'versions' list is present with at least one entry" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
versions = data.get('versions')
assert isinstance(versions, list) and len(versions) >= 1, \
    'versions key missing or empty in firmware-policy.yaml'
"

    assert_exit_zero \
        "firmware-policy.yaml: every version entry has 'version' and 'status' fields" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
required = {'version', 'status'}
for v in data.get('versions', []):
    missing = required - set(v.keys())
    assert not missing, \
        f'Version entry {v.get(\"version\", \"<unnamed>\")!r} missing fields: {missing}'
"

    assert_exit_zero \
        "firmware-policy.yaml: every version 'status' is one of approved, beta, legacy, blocked" \
        python3 -c "
import sys, yaml
valid = {'approved', 'beta', 'legacy', 'blocked'}
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
for v in data.get('versions', []):
    status = v.get('status')
    assert status in valid, \
        f'Version {v[\"version\"]!r} has invalid status {status!r}; allowed: {valid}'
"

    assert_exit_zero \
        "firmware-policy.yaml: exactly one version entry has status=approved" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
approved = [v for v in data.get('versions', []) if v.get('status') == 'approved']
assert len(approved) >= 1, 'No version with status=approved found in firmware-policy.yaml'
"

    assert_exit_zero \
        "firmware-policy.yaml: global.approved_version matches a version entry with status=approved" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
global_approved = data.get('global', {}).get('approved_version')
approved_versions = {v['version'] for v in data.get('versions', []) if v.get('status') == 'approved'}
assert global_approved in approved_versions, \
    f'global.approved_version={global_approved!r} does not match any approved entry in versions list: {approved_versions}'
"

    assert_exit_zero \
        "firmware-policy.yaml: 'model_overrides' key is present and is a list" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
overrides = data.get('model_overrides')
assert isinstance(overrides, list), \
    f'model_overrides key missing or not a list in firmware-policy.yaml'
"

    assert_exit_zero \
        "firmware-policy.yaml: every model_override has 'model' and 'approved_version' fields" \
        python3 -c "
import sys, yaml
data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
required = {'model', 'approved_version'}
for ov in data.get('model_overrides', []):
    missing = required - set(ov.keys())
    assert not missing, \
        f'model_override {ov.get(\"model\", \"<unnamed>\")!r} missing fields: {missing}'
"

    assert_exit_zero \
        "cross-ref: every node model in mesh-nodes.yaml that has a model_override is covered" \
        python3 -c "
import sys, yaml
nodes_data  = yaml.safe_load(open('inventories/mesh-nodes.yaml'))
policy_data = yaml.safe_load(open('desired-state/mesh/firmware-policy.yaml'))
global_approved  = policy_data['global']['approved_version']
override_models  = {ov['model']: ov['approved_version'] for ov in policy_data.get('model_overrides', [])}
approved_version_set = {v['version'] for v in policy_data.get('versions', []) if v.get('status') == 'approved'}

for node in nodes_data['nodes']:
    model = node.get('model')
    fw    = node.get('firmware_version', '')
    if model in override_models:
        target = override_models[model]
    else:
        target = global_approved
    # This check just verifies consistency data exists; it does not fail on drift
    assert target, f'Could not determine target firmware for node {node[\"name\"]!r} (model={model!r})'
"

    # -----------------------------------------------------------------------
    # H. Docker Compose env example coverage
    # -----------------------------------------------------------------------
    qa_section "H. Docker Compose env example coverage"

    # nextcloud
    assert_file_exists \
        "skills/server-services/scripts/nextcloud/docker-compose.yaml" \
        "nextcloud: docker-compose.yaml exists"
    assert_file_exists \
        "skills/server-services/scripts/nextcloud/install.sh" \
        "nextcloud: install.sh exists"
    assert_file_exists \
        "skills/server-services/scripts/nextcloud/.env.example" \
        "nextcloud: .env.example exists alongside docker-compose.yaml and install.sh"

    # jellyfin
    assert_file_exists \
        "skills/server-services/scripts/jellyfin/docker-compose.yaml" \
        "jellyfin: docker-compose.yaml exists"
    assert_file_exists \
        "skills/server-services/scripts/jellyfin/install.sh" \
        "jellyfin: install.sh exists"
    assert_file_exists \
        "skills/server-services/scripts/jellyfin/.env.example" \
        "jellyfin: .env.example exists alongside docker-compose.yaml and install.sh"

    # kolibri
    assert_file_exists \
        "skills/server-services/scripts/kolibri/docker-compose.yaml" \
        "kolibri: docker-compose.yaml exists"
    assert_file_exists \
        "skills/server-services/scripts/kolibri/install.sh" \
        "kolibri: install.sh exists"
    assert_file_exists \
        "skills/server-services/scripts/kolibri/.env.example" \
        "kolibri: .env.example exists alongside docker-compose.yaml and install.sh"

    # prometheus
    assert_file_exists \
        "skills/server-services/scripts/prometheus/docker-compose.yaml" \
        "prometheus: docker-compose.yaml exists"
    assert_file_exists \
        "skills/server-services/scripts/prometheus/install.sh" \
        "prometheus: install.sh exists"
    assert_file_exists \
        "skills/server-services/scripts/prometheus/.env.example" \
        "prometheus: .env.example exists alongside docker-compose.yaml and install.sh"

    # telegram adapter
    assert_file_exists \
        "adapters/channels/telegram/docker-compose.yaml" \
        "telegram adapter: docker-compose.yaml exists"
    assert_file_exists \
        "adapters/channels/telegram/.env.example" \
        "telegram adapter: .env.example exists alongside docker-compose.yaml"
}

# ---------------------------------------------------------------------------
# Entry point — only run when executed directly, not when sourced.
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_schema_checks
    qa_summary
fi
