#!/usr/bin/env bash
set -euo pipefail

mkdir -p /run/sshd /root/.ssh /etc/ssh/sshd_config.d
cp /fixture-ssh/id_ed25519.pub /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

cat > /etc/ssh/sshd_config.d/mesha-test.conf <<'EOF'
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthorizedKeysFile .ssh/authorized_keys
EOF

ssh-keygen -A >/dev/null 2>&1 || true
if [[ -f /fixtures/openwrt_release ]]; then
    cp /fixtures/openwrt_release /etc/openwrt_release
elif [[ -f /fixtures/openwrt_release.txt ]]; then
    cp /fixtures/openwrt_release.txt /etc/openwrt_release
else
    echo "Missing OpenWrt release fixture" >&2
    exit 1
fi

if [[ "${ENABLE_HTTP:-0}" == "1" || "${ENABLE_HTTP:-false}" == "true" ]]; then
    mkdir -p /fixtures/http
    if [[ ! -f /fixtures/http/index.html ]]; then
        printf '<html><body><h1>Mesha fixture node</h1></body></html>\n' > /fixtures/http/index.html
    fi
    python3 -m http.server 80 --directory /fixtures/http >/tmp/http-server.log 2>&1 &
fi

exec /usr/sbin/sshd -D -e
