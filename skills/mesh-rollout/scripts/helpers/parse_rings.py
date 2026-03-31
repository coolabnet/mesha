#!/usr/bin/env python3
"""Extract ring names and stabilization periods from rollout-policy.yaml.

Reads the policy file and outputs one line per ring:
    ring_name|stabilization_hours

Usage:
    parse_rings.py <policy_file>
"""

import sys
import re


def main():
    if len(sys.argv) < 2:
        print("Usage: parse_rings.py <policy_file>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    with open(path) as f:
        content = f.read()

    in_rings = False
    current_ring = None
    current_stab = "0"

    for line in content.splitlines():
        stripped = line.strip()
        if stripped == "upgrade_rings:":
            in_rings = True
            continue
        if in_rings:
            # Top-level key after upgrade_rings ends the block
            if stripped and not stripped.startswith("-") and not stripped.startswith("#") \
               and not line.startswith(" ") and not line.startswith("\t"):
                in_rings = False
                continue
            ring_match = re.match(r'\s*-\s*ring:\s*["\']?(\w+)["\']?', line)
            if ring_match:
                if current_ring:
                    print(f"{current_ring}|{current_stab}")
                current_ring = ring_match.group(1)
                current_stab = "0"
                continue
            stab_match = re.match(r'\s+stabilization_period_hours:\s*(\d+)', line)
            if stab_match and current_ring:
                current_stab = stab_match.group(1)

    if current_ring:
        print(f"{current_ring}|{current_stab}")


if __name__ == "__main__":
    main()
