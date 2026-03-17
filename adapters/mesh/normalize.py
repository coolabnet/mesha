#!/usr/bin/env python3
"""
adapters/mesh/normalize.py

Usage:
    cat raw.json | python3 adapters/mesh/normalize.py
    cat raw.json | python3 adapters/mesh/normalize.py --compare inventories/mesh-nodes.yaml

Description:
    Reads raw JSON from stdin (produced by collect-nodes.sh or
    collect-topology.sh) and normalizes the field names to match the
    inventory schema used in inventories/mesh-nodes.yaml.

    When --compare is provided, also loads the inventory file and produces
    a drift report showing which fields differ between the live collected
    data and the inventory record for the same node (matched by hostname
    or MAC address).

Output (stdout):
    Without --compare: normalized JSON object or array
    With --compare:    drift report as a JSON object with fields:
        {
          "compared_at": "<ISO8601>",
          "inventory_file": "<path>",
          "nodes_checked": <int>,
          "drift_found": true|false,
          "drift": [
            {
              "hostname": "<string>",
              "field": "<field name>",
              "inventory_value": "<value>",
              "live_value": "<value>",
              "severity": "info|warning|error"
            }
          ]
        }

Risk class: A (read-only — reads files and stdin only, no writes)

Dependencies:
    - Python 3 stdlib (json, sys, argparse, datetime)
    - PyYAML (yaml) for reading YAML inventory files
      Install: pip install pyyaml
              or: apt install python3-yaml

Exit codes:
    0 — success (drift may or may not have been found; check drift_found)
    1 — usage or parse error
"""

import sys
import json
import argparse
from datetime import datetime, timezone
from typing import Optional

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False


# ---------------------------------------------------------------------------
# Field name mappings: raw field → normalized inventory field name
#
# The keys are field names that may appear in raw collect-nodes.sh output.
# The values are the canonical field names used in mesh-nodes.yaml.
# ---------------------------------------------------------------------------
FIELD_MAP = {
    # Hostname variants
    "hostname":         "hostname",
    "system_hostname":  "hostname",
    "node_hostname":    "hostname",

    # Firmware version variants
    "firmware_version":        "firmware_version",
    "firmware":                "firmware_version",
    "openwrt_version":         "firmware_version",
    "libremesh_version":       "firmware_version",
    "distrib_description":     "firmware_version",

    # Status
    "status":           "status",
    "node_status":      "status",
    "reachable":        "status",   # bool → mapped to "online"/"offline" in normalize

    # Role
    "role":             "role",
    "node_role":        "role",

    # MAC address
    "mac":              "mac",
    "primary_mac":      "mac",
    "eth_mac":          "mac",

    # Site
    "site":             "site",
    "site_name":        "site",

    # Model
    "model":            "model",
    "hardware_model":   "model",
    "board":            "model",

    # Uptime
    "uptime_seconds":   "uptime_seconds",
    "uptime":           "uptime_seconds",

    # Notes
    "notes":            "notes",
}

# Fields that are expected in a fully normalized inventory record
INVENTORY_FIELDS = {
    "name", "hostname", "mac", "site", "model",
    "firmware_version", "role", "status", "notes",
}

# Drift severity rules:
#   error   — field mismatch that indicates a real operational problem
#   warning — field mismatch that should be reviewed but is not critical
#   info    — informational difference (e.g. uptime, notes)
SEVERITY_MAP = {
    "firmware_version": "warning",
    "status":           "warning",
    "hostname":         "error",
    "mac":              "error",
    "model":            "warning",
    "role":             "error",
    "site":             "info",
    "notes":            "info",
}


def normalize_node(raw: dict) -> dict:
    """
    Normalize a raw collected node dict into the inventory schema.
    Applies FIELD_MAP renames and light value normalization.
    Returns a dict using canonical inventory field names.
    """
    normalized = {}

    for raw_key, raw_value in raw.items():
        canon_key = FIELD_MAP.get(raw_key, raw_key)
        normalized[canon_key] = raw_value

    # Normalize status: convert any truthy/falsy or string representation
    # to the canonical "online" / "offline" values.
    # FIELD_MAP remaps the raw "reachable" bool to the "status" key, so
    # normalized["status"] may be a bool at this point.
    if "status" in normalized:
        s = str(normalized["status"]).lower()
        if s in ("true", "1", "up", "reachable", "online", "running"):
            normalized["status"] = "online"
        elif s in ("false", "0", "down", "unreachable", "offline"):
            normalized["status"] = "offline"
        # else: leave other values (e.g. "degraded", "unknown") as-is

    # Strip the 'error' and internal adapter fields from normalized output
    for internal_field in ("error", "collected_at", "node_ip", "interfaces",
                            "radios", "mesh_neighbors", "uptime_human"):
        normalized.pop(internal_field, None)

    return normalized


def load_inventory(path: str) -> list:
    """
    Load the mesh-nodes.yaml inventory file. Returns a list of node dicts.
    Exits with error if the file cannot be loaded or YAML is unavailable.
    """
    if not YAML_AVAILABLE:
        print(
            json.dumps({
                "error": "PyYAML not available. Install with: pip install pyyaml or apt install python3-yaml",
                "compared_at": utcnow(),
            }),
            file=sys.stdout
        )
        sys.exit(1)

    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except FileNotFoundError:
        print(
            json.dumps({"error": f"Inventory file not found: {path}", "compared_at": utcnow()}),
            file=sys.stdout
        )
        sys.exit(1)
    except yaml.YAMLError as exc:
        print(
            json.dumps({"error": f"YAML parse error in {path}: {exc}", "compared_at": utcnow()}),
            file=sys.stdout
        )
        sys.exit(1)

    return data.get("nodes", [])


def find_inventory_node(normalized_live: dict, inventory: list) -> Optional[dict]:
    """
    Find the inventory record that matches the live node.
    Tries matching by hostname first, then by MAC address.
    Returns the inventory dict or None if not found.
    """
    live_hostname = normalized_live.get("hostname")
    live_mac = normalized_live.get("mac", "").lower()

    for inv_node in inventory:
        if live_hostname and inv_node.get("hostname") == live_hostname:
            return inv_node
        if live_mac and inv_node.get("mac", "").lower() == live_mac:
            return inv_node
    return None


def compute_drift(live: dict, inventory_node: dict) -> list:
    """
    Compare normalized live data to inventory record.
    Returns a list of drift entries for fields that differ.
    """
    drift = []
    fields_to_check = INVENTORY_FIELDS - {"name", "notes"}  # notes are informational

    for field in sorted(fields_to_check):
        live_val = live.get(field)
        inv_val = inventory_node.get(field)

        # Skip if both are None/missing
        if live_val is None and inv_val is None:
            continue

        # Normalize string comparison
        live_str = str(live_val).strip() if live_val is not None else None
        inv_str = str(inv_val).strip() if inv_val is not None else None

        if live_str != inv_str:
            drift.append({
                "hostname": inventory_node.get("hostname") or live.get("hostname", "unknown"),
                "field": field,
                "inventory_value": inv_val,
                "live_value": live_val,
                "severity": SEVERITY_MAP.get(field, "info"),
            })

    return drift


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    parser = argparse.ArgumentParser(
        description="Normalize mesh node JSON and optionally compare against inventory."
    )
    parser.add_argument(
        "--compare",
        metavar="INVENTORY_YAML",
        help="Path to inventories/mesh-nodes.yaml for drift comparison",
        default=None,
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        default=True,
        help="Pretty-print JSON output (default: true)",
    )
    args = parser.parse_args()

    # --- Read raw JSON from stdin ---
    try:
        raw_input = sys.stdin.read().strip()
        if not raw_input:
            print(json.dumps({"error": "Empty input on stdin", "compared_at": utcnow()}))
            sys.exit(1)
        raw_data = json.loads(raw_input)
    except json.JSONDecodeError as exc:
        print(json.dumps({"error": f"JSON parse error: {exc}", "compared_at": utcnow()}))
        sys.exit(1)

    indent = 2 if args.pretty else None

    # --- Handle single node or list of nodes ---
    if isinstance(raw_data, list):
        raw_nodes = raw_data
    elif isinstance(raw_data, dict):
        # collect-topology.sh returns an object with a 'nodes' array
        if "nodes" in raw_data:
            raw_nodes = raw_data["nodes"]
        else:
            # Single node object from collect-nodes.sh
            raw_nodes = [raw_data]
    else:
        print(json.dumps({"error": "Unexpected input format — expected JSON object or array"}))
        sys.exit(1)

    # --- Normalize all nodes ---
    normalized_nodes = [normalize_node(n) for n in raw_nodes]

    # --- If no --compare flag: just output normalized JSON and exit ---
    if not args.compare:
        if len(normalized_nodes) == 1:
            print(json.dumps(normalized_nodes[0], indent=indent))
        else:
            print(json.dumps(normalized_nodes, indent=indent))
        return

    # --- Drift comparison mode ---
    inventory = load_inventory(args.compare)
    all_drift = []
    matched = 0
    unmatched = []

    for live_node in normalized_nodes:
        inv_node = find_inventory_node(live_node, inventory)
        if inv_node is None:
            unmatched.append(live_node.get("hostname") or live_node.get("mac") or "unknown")
            continue
        matched += 1
        node_drift = compute_drift(live_node, inv_node)
        all_drift.extend(node_drift)

    # Nodes in inventory but not seen in live data
    live_hostnames = {n.get("hostname") for n in normalized_nodes}
    missing_from_live = [
        inv.get("hostname") for inv in inventory
        if inv.get("hostname") not in live_hostnames
    ]

    report = {
        "compared_at": utcnow(),
        "inventory_file": args.compare,
        "nodes_in_inventory": len(inventory),
        "nodes_in_live_data": len(normalized_nodes),
        "nodes_matched": matched,
        "nodes_unmatched_in_live": unmatched,
        "nodes_missing_from_live": missing_from_live,
        "drift_found": len(all_drift) > 0,
        "drift_count": len(all_drift),
        "drift": all_drift,
    }

    print(json.dumps(report, indent=indent))


if __name__ == "__main__":
    main()
