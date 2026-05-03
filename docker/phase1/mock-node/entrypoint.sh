#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
set -euo pipefail

PROFILE="${MOCK_PROFILE:-thisnode}"
PROFILE_DIR="/fixtures/${PROFILE}"

if [[ ! -d $PROFILE_DIR ]]; then
  echo "Missing fixture profile: $PROFILE_DIR" >&2
  exit 1
fi

ln -sfn "$PROFILE_DIR" /mock-current

mkdir -p /root/.ssh
chmod 700 /root/.ssh
cp /test-ssh/id_ed25519.pub /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

mkdir -p /run/sshd /var/www/mock

if [[ -f "$PROFILE_DIR/openwrt_release" ]]; then
  cp "$PROFILE_DIR/openwrt_release" /etc/openwrt_release
fi

if [[ -f "$PROFILE_DIR/http/index.html" ]]; then
  cp "$PROFILE_DIR/http/index.html" /var/www/mock/index.html
fi

cat >/etc/ssh/sshd_config <<'EOF'
Port 22
Protocol 2
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
UsePAM no
PidFile /run/sshd.pid
X11Forwarding no
PrintMotd no
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

ssh-keygen -A >/dev/null 2>&1

/usr/sbin/sshd
python3 -m http.server 80 --directory /var/www/mock >/tmp/mock-http.log 2>&1 &

exec tail -f /tmp/mock-http.log
