#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
"""Update the status of a single node in rollout-state.yaml.

Usage:
    update_node_state.py <state_file> <hostname> <new_status> <ts_field> <now>
"""

import re
import sys


def main():
    if len(sys.argv) < 6:
        print(
            "Usage: update_node_state.py <state_file> <hostname> <new_status> <ts_field> <now>",
            file=sys.stderr,
        )
        sys.exit(1)

    state_path = sys.argv[1]
    hostname = sys.argv[2]
    new_status = sys.argv[3]
    ts_field = sys.argv[4]
    now = sys.argv[5]

    with open(state_path) as f:
        lines = f.readlines()

    in_node = False
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # Detect start of this node's block
        hm = re.match(r'\s+-\s+hostname:\s*"?([^\s"]+)"?', line)
        if hm and hm.group(1).strip().strip('"') == hostname:
            in_node = True
        if in_node:
            sm = re.match(r"(\s+)status:\s*\S+", line)
            if sm:
                line = f"{sm.group(1)}status: {new_status}\n"
            tf_m = re.match(r"(\s+)" + re.escape(ts_field) + r":\s*\S+", line)
            if tf_m:
                line = f'{tf_m.group(1)}{ts_field}: "{now}"\n'
            # Next node block ends this one
            if (
                i > 0
                and re.match(r"\s+-\s+hostname:", line)
                and not (hm and hm.group(1).strip().strip('"') == hostname)
            ):
                in_node = False
        out.append(line)
        i += 1

    with open(state_path, "w") as f:
        f.writelines(out)


if __name__ == "__main__":
    main()
