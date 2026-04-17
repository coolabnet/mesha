#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
"""Check if current time falls within a preferred change window.

Reads rollout-policy.yaml and prints "yes" or "no" to stdout.

Usage:
    check_change_window.py <policy_file>
"""

import sys
import re
from datetime import datetime, timezone

try:
    import zoneinfo

    def get_tz(name):
        return zoneinfo.ZoneInfo(name)
except ImportError:
    # Python < 3.9 fallback -- use UTC as approximation
    def get_tz(name):
        return timezone.utc


def main():
    if len(sys.argv) < 2:
        print("Usage: check_change_window.py <policy_file>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    with open(path) as f:
        content = f.read()

    # Extract preferred windows
    windows = []
    current = {}
    in_preferred = False

    for line in content.splitlines():
        stripped = line.strip()
        if re.match(r'\s+preferred:', line):
            in_preferred = True
            continue
        if in_preferred:
            if re.match(r'\s+blackout_periods:', line):
                in_preferred = False
                continue
            if re.match(r'\s+-\s+description:', line):
                if current:
                    windows.append(current)
                current = {}
                continue
            days_match = re.match(r'\s+days:\s*\[([^\]]+)\]', line)
            if days_match:
                current['days'] = [d.strip().strip('"') for d in days_match.group(1).split(',')]
            start_match = re.match(r'\s+start_time:\s*"?(\d+:\d+)"?', line)
            if start_match:
                current['start'] = start_match.group(1)
            end_match = re.match(r'\s+end_time:\s*"?(\d+:\d+)"?', line)
            if end_match:
                current['end'] = end_match.group(1)
            tz_match = re.match(r'\s+timezone:\s*"?([^\s"]+)"?', line)
            if tz_match:
                current['tz'] = tz_match.group(1)

    if current:
        windows.append(current)

    day_names = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']

    for w in windows:
        tz_name = w.get('tz', 'UTC')
        try:
            tz = get_tz(tz_name)
        except Exception:
            tz = timezone.utc
        now = datetime.now(tz)
        today = day_names[now.weekday()]
        if today not in w.get('days', []):
            continue
        start_h, start_m = map(int, w.get('start', '00:00').split(':'))
        end_h, end_m = map(int, w.get('end', '23:59').split(':'))
        now_minutes = now.hour * 60 + now.minute
        start_minutes = start_h * 60 + start_m
        end_minutes = end_h * 60 + end_m
        if start_minutes <= now_minutes <= end_minutes:
            print("yes")
            sys.exit(0)

    print("no")


if __name__ == "__main__":
    main()
