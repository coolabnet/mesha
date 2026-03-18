#!/usr/bin/env bash

set -euo pipefail

mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [[ -f /fixture-ssh/id_ed25519 ]]; then
    cp /fixture-ssh/id_ed25519 /root/.ssh/id_ed25519
    chmod 600 /root/.ssh/id_ed25519
fi

if [[ -f /fixture-ssh/id_ed25519.pub ]]; then
    cp /fixture-ssh/id_ed25519.pub /root/.ssh/id_ed25519.pub
    chmod 644 /root/.ssh/id_ed25519.pub
fi

cat > /root/.ssh/config <<'EOF'
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
chmod 600 /root/.ssh/config

exec "$@"
