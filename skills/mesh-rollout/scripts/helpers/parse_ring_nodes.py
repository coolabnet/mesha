#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
"""Resolve node hostnames that belong to a given ring.

Cross-references ring node names (from rollout-policy.yaml) against the
inventory to output resolved hostnames, one per line.

Usage:
    parse_ring_nodes.py <policy_file> <inventory_file> <ring_name>
"""

import re
import sys


def main():
    if len(sys.argv) < 4:
        print("Usage: parse_ring_nodes.py <policy_file> <inventory_file> <ring_name>", file=sys.stderr)
        sys.exit(1)

    policy_path = sys.argv[1]
    inventory_path = sys.argv[2]
    target_ring = sys.argv[3]

    # --- Parse rollout-policy.yaml: find node display names for the target ring ---
    ring_node_names = []
    with open(policy_path) as f:
        content = f.read()

    in_rings = False
    in_target_ring = False
    in_nodes = False

    for line in content.splitlines():
        stripped = line.strip()
        if stripped == "upgrade_rings:":
            in_rings = True
            continue
        if in_rings:
            # End of upgrade_rings block
            if (
                stripped
                and not stripped.startswith("-")
                and not stripped.startswith("#")
                and not line.startswith(" ")
                and not line.startswith("\t")
            ):
                in_rings = False
                continue
            ring_match = re.match(r'\s*-\s*ring:\s*["\']?(\w+)["\']?', line)
            if ring_match:
                in_target_ring = ring_match.group(1) == target_ring
                in_nodes = False
                continue
            if in_target_ring:
                if re.match(r"\s+nodes:", line):
                    in_nodes = True
                    continue
                # Another ring key ends the nodes block
                if in_nodes and re.match(r"\s+\w+:", line) and not re.match(r"\s+-", line):
                    in_nodes = False
                    continue
                if in_nodes:
                    node_match = re.match(r'\s+-\s+"([^"]+)"', line)
                    if not node_match:
                        node_match = re.match(r"\s+-\s+'([^']+)'", line)
                    if not node_match:
                        node_match = re.match(r"\s+-\s+(.+)", line)
                    if node_match:
                        ring_node_names.append(node_match.group(1).strip().strip("\"'"))

    # --- Parse inventories/mesh-nodes.yaml: resolve hostnames by name ---
    with open(inventory_path) as f:
        inv_content = f.read()

    in_nodes_block = False
    current_name = None
    current_hostname = None

    for line in inv_content.splitlines():
        stripped = line.strip()
        if stripped == "nodes:":
            in_nodes_block = True
            continue
        if in_nodes_block:
            if re.match(r"\s*-\s+name:", line):
                # Flush previous node
                if current_name and current_hostname and current_name in ring_node_names:
                    print(current_hostname)
                name_match = re.match(r'\s*-\s+name:\s*"([^"]+)"', line)
                if not name_match:
                    name_match = re.match(r"\s*-\s+name:\s*'([^']+)'", line)
                if not name_match:
                    name_match = re.match(r"\s*-\s+name:\s+(.+)", line)
                current_name = name_match.group(1).strip().strip("\"'") if name_match else None
                current_hostname = None
                continue
            host_match = re.match(r'\s+hostname:\s*"?([^\s"]+)"?', line)
            if host_match and current_name:
                current_hostname = host_match.group(1).strip().strip('"')

    # Flush last node
    if current_name and current_hostname and current_name in ring_node_names:
        print(current_hostname)


if __name__ == "__main__":
    main()
