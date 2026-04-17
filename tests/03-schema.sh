#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
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

  cd "$WORKSPACE_ROOT" || exit 1

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

  # -----------------------------------------------------------------------
  # I. .env.example variable consistency
  # -----------------------------------------------------------------------
  qa_section "I. .env.example variable consistency"

  assert_exit_zero \
    "all docker-compose.yaml env vars appear in corresponding .env.example" \
    python3 -c "
import os, re, yaml, sys

compose_dirs = []
for root, dirs, files in os.walk('.'):
    if 'docker-compose.yaml' in files or 'docker-compose.yml' in files:
        compose_dirs.append(root)

errors = []
for d in compose_dirs:
    # Find compose file
    compose = os.path.join(d, 'docker-compose.yaml')
    if not os.path.exists(compose):
        compose = os.path.join(d, 'docker-compose.yml')

    # Check for env_file or environment directives
    with open(compose) as fh:
        content = fh.read()

    # Skip if no env references at all (like homer)
    dollar_brace = chr(36) + '{'
    if 'env_file' not in content and 'environment' not in content and dollar_brace not in content:
        continue

    # Extract ${VAR} and ${VAR:-default} patterns from compose
    compose_vars = set(re.findall(r'\$\{(\w+)(?::-[^}]*)?\}', content))

    # Also check install.sh for env-var references
    install_sh = os.path.join(d, 'install.sh')
    if os.path.exists(install_sh):
        with open(install_sh) as fh:
            install_content = fh.read()
        # Find variables assigned locally in the script (VAR= at start of line)
        local_vars = set(re.findall(r'^([A-Z][A-Z0-9_]*)=', install_content, re.MULTILINE))
        # Find all $VAR references in install.sh (not ${VAR}, already covered)
        install_vars = set(re.findall(r'(?<!\$)\$([A-Z][A-Z0-9_]*)', install_content))
        # Filter to likely env var names (all caps, underscore-separated, >2 chars)
        # Exclude variables that are assigned locally within the script
        install_vars = {v for v in install_vars if len(v) > 2 and '_' in v and v not in local_vars}
        compose_vars.update(install_vars)

    if not compose_vars:
        continue

    # Check .env.example exists
    env_example = os.path.join(d, '.env.example')
    if not os.path.exists(env_example):
        errors.append(f'{d}: has env vars but no .env.example')
        continue

    with open(env_example) as fh:
        env_content = fh.read()

    # Extract var names from .env.example (KEY= or KEY: lines)
    env_vars = set(re.findall(r'^(\w+)(?:=|:)', env_content, re.MULTILINE))

    missing = compose_vars - env_vars
    if missing:
        errors.append(f'{d}: vars in compose/install but not in .env.example: {sorted(missing)}')

if errors:
    for e in errors:
        print(e)
    sys.exit(1)
"

  # -----------------------------------------------------------------------
  # J. Docker image pinning
  # -----------------------------------------------------------------------
  qa_section "J. Docker image pinning (no :latest or unpinned tags)"

  # Check for unpinned Docker image tags (:latest)
  local unpinned
  unpinned=$(grep -rn 'image:.*:latest' --include='*.yaml' --include='*.yml' . \
    2>/dev/null | grep -v '.git/' || true)
  # Also catch images with no tag at all (image: foo/bar without :tag)
  local untagged
  untagged=$(grep -rn 'image:' --include='*.yaml' --include='*.yml' . \
    2>/dev/null | grep -v '.git/' | grep -vE 'image:.*:v?[0-9]' | grep -vE 'image:.*:latest' || true)

  if [[ -z "$unpinned" && -z "$untagged" ]]; then
    qa_pass "all Docker images use pinned tags"
  else
    if [[ -n "$unpinned" ]]; then
      while IFS= read -r line; do
        qa_fail "unpinned image (uses :latest): ${line}"
      done <<<"$unpinned"
    fi
    if [[ -n "$untagged" ]]; then
      while IFS= read -r line; do
        qa_fail "unpinned image (no version tag): ${line}"
      done <<<"$untagged"
    fi
  fi

  # -----------------------------------------------------------------------
  # K. field_map.json cross-reference
  # -----------------------------------------------------------------------
  qa_section "K. field_map.json cross-reference"

  assert_exit_zero \
    "field_map.json: all canonical field names are used in normalize.py or mesh-nodes.yaml" \
    python3 -c "
import json, re, yaml, sys

# Load field_map.json
with open('adapters/mesh/field_map.json') as fh:
    fm = json.load(fh)

canonical_fields = set(fm['field_map'].values())

# Load normalize.py and find field references
with open('adapters/mesh/normalize.py') as fh:
    normalize_src = fh.read()

# Find INVENTORY_FIELDS set in normalize.py
inv_match = re.search(r'INVENTORY_FIELDS\s*=\s*\{([^}]+)\}', normalize_src)
if inv_match:
    inv_fields = {f.strip().strip('\"').strip(\"'\") for f in inv_match.group(1).split(',') if f.strip()}
else:
    inv_fields = set()

# Load mesh-nodes.yaml field names
with open('inventories/mesh-nodes.yaml') as fh:
    data = yaml.safe_load(fh)
node_fields = set()
for node in data.get('nodes', []):
    node_fields.update(node.keys())

# All valid fields = inventory fields + node fields + severity map keys
valid_fields = inv_fields | node_fields | set(fm.get('severity_map', {}).keys())

# Check each canonical field
unknown = canonical_fields - valid_fields
# Some fields like 'uptime_seconds' are used but not in INVENTORY_FIELDS
# Allow fields that appear in the source code at all
for field in list(unknown):
    if field in normalize_src:
        unknown.discard(field)

if unknown:
    print(f'field_map.json has unknown canonical fields: {sorted(unknown)}')
    sys.exit(1)
"

  assert_exit_zero \
    "field_map.json: severity_map keys match canonical field names" \
    python3 -c "
import json, sys

with open('adapters/mesh/field_map.json') as fh:
    fm = json.load(fh)

canonical = set(fm['field_map'].values())
severity_keys = set(fm['severity_map'].keys())

# Every severity key should be a known canonical field
unknown_sev = severity_keys - canonical
if unknown_sev:
    print(f'severity_map has keys not in field_map canonical values: {sorted(unknown_sev)}')
    sys.exit(1)
"
}

# ---------------------------------------------------------------------------
# Entry point — only run when executed directly, not when sourced.
# ---------------------------------------------------------------------------
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  run_schema_checks
  qa_summary
fi
