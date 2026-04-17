#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
"""Parse rollout-state.yaml to extract resume information.

Outputs key=value lines to stdout:
    status=<value>
    firmware_url=<value>
    rollout_id=<value>
    done:<hostname>   (for each already-validated/upgraded node)

Usage:
    parse_resume_state.py <state_file>
"""

import re
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: parse_resume_state.py <state_file>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    with open(path) as f:
        content = f.read()

    status_match = re.search(r"^status:\s*(\S+)", content, re.MULTILINE)
    status = status_match.group(1) if status_match else "unknown"

    fw_match = re.search(r"^firmware_url:\s*(.+)", content, re.MULTILINE)
    fw = fw_match.group(1).strip().strip('"') if fw_match else ""

    id_match = re.search(r"^rollout_id:\s*(.+)", content, re.MULTILINE)
    rid = id_match.group(1).strip().strip('"') if id_match else ""

    print(f"status={status}")
    print(f"firmware_url={fw}")
    print(f"rollout_id={rid}")

    # Find nodes that are already validated/upgraded -- output as done:<hostname>
    current_host = None
    for line in content.splitlines():
        if re.match(r"\s+-\s+hostname:", line):
            hm = re.match(r'\s+-\s+hostname:\s*"?([^\s"]+)"?', line)
            current_host = hm.group(1).strip().strip('"') if hm else None
        sm = re.match(r"\s+status:\s*(\S+)", line)
        if sm and current_host:
            current_status = sm.group(1).strip()
            if current_status in ("validated", "upgraded"):
                print(f"done:{current_host}")
            current_host = None


if __name__ == "__main__":
    main()
