#!/usr/bin/env bash

set -euo pipefail

mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [[ ! -f /fixtures-ssh/id_ed25519 || ! -f /fixtures-ssh/id_ed25519.pub ]]; then
    echo "Missing Phase 1 test SSH key material under /fixtures-ssh" >&2
    exit 1
fi

cp /fixtures-ssh/id_ed25519 /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519

cp /fixtures-ssh/id_ed25519.pub /root/.ssh/id_ed25519.pub
chmod 644 /root/.ssh/id_ed25519.pub

cat > /root/.ssh/config <<'EOF'
Host *
  IdentityFile /root/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
chmod 600 /root/.ssh/config

exec "$@"
