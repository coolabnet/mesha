#!/usr/bin/env bash
# configure-vms.sh — Post-boot configuration for Mesha QEMU LibreMesh VMs
# Waits for SSH, configures mesh networking, injects SSH keys

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR="${REPO_ROOT}/testbed/run"
TOPOLOGY_FILE="${REPO_ROOT}/testbed/config/topology.yaml"
SSH_KEY_DIR="${RUN_DIR}/ssh-keys"
SSH_KEY="${SSH_KEY_DIR}/id_ed25519"

# Timeout multiplier for TCG mode
TIMEOUT_MULTIPLIER="${QEMU_TIMEOUT_MULTIPLIER:-1}"
SSH_BASE_TIMEOUT=$((5 * TIMEOUT_MULTIPLIER))
# BOOT_WAIT_TIMEOUT used for reference; actual wait is per-VM with retries
export BOOT_WAIT_TIMEOUT=$((120 * TIMEOUT_MULTIPLIER))
MAX_SSH_RETRIES=15

# Node definitions (fallback if no topology.yaml)
declare -a NODE_IPS=("10.99.0.11" "10.99.0.12" "10.99.0.13" "10.99.0.14")
declare -a NODE_HOSTNAMES=("lm-testbed-node-1" "lm-testbed-node-2" "lm-testbed-node-3" "lm-testbed-tester")

# ─── Parse topology ───
parse_topology() {
    if [ ! -f "$TOPOLOGY_FILE" ]; then
        return
    fi
    # Simplified topology parse: extract hostname/ip pairs in order
    NODE_IPS=()
    NODE_HOSTNAMES=()
    while IFS= read -r line; do
        case "$line" in
            *"hostname:"*)
                NODE_HOSTNAMES+=("$(echo "$line" | awk -F': ' '{print $2}' | tr -d '"')")
                ;;
            *" ip:"*)
                NODE_IPS+=("$(echo "$line" | awk -F': ' '{print $2}' | tr -d '"')")
                ;;
        esac
    done < <(awk '
        /^    - id:/ { in_node=1 }
        in_node && /hostname:/ { print }
        in_node && / ip:/ { print; in_node=0 }
    ' "$TOPOLOGY_FILE")
}

# ─── SSH helper ───
ssh_vm() {
    local ip="$1"
    shift
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=no \
        -o ConnectTimeout="${SSH_BASE_TIMEOUT}" \
        "root@${ip}" "$@"
}

ssh_vm_with_key() {
    local ip="$1"
    shift
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        -i "${SSH_KEY}" \
        -o ConnectTimeout="${SSH_BASE_TIMEOUT}" \
        "root@${ip}" "$@"
}

# ─── Wait for SSH on a VM ───
wait_for_ssh() {
    local ip="$1"
    local hostname="$2"
    local attempt=1
    local delay=2

    echo -n "  [${hostname}] Waiting for SSH at ${ip}..."

    while [ $attempt -le $MAX_SSH_RETRIES ]; do
        if ssh_vm "$ip" "echo ok" &>/dev/null; then
            echo " OK (attempt ${attempt})"
            return 0
        fi
        echo -n "."
        sleep "$delay"
        delay=$((delay * 2 > 30 ? 30 : delay * 2))
        attempt=$((attempt + 1))
    done

    echo " FAILED"
    echo "  [${hostname}] ERROR: SSH not reachable after ${MAX_SSH_RETRIES} attempts"
    return 1
}

# ─── Configure a single VM ───
configure_vm() {
    local node_id="$1"
    local ip="$2"
    local hostname="$3"
    echo "  [${hostname}] Phase 1: Basic LibreMesh configuration..."

    # Set hostname
    ssh_vm "$ip" "uci set system.@system[0].hostname='${hostname}' && uci commit system && echo '${hostname}' > /proc/sys/kernel/hostname" || true

    # Configure mesh interface IP on br-lan
    ssh_vm "$ip" "
        uci set network.lan.ipaddr='${ip}'
        uci set network.lan.netmask='255.255.0.0'
        uci commit network
    " || true

    # Load mac80211_hwsim (remove real radios, replaced by vwifi)
    ssh_vm "$ip" "modprobe mac80211_hwsim radios=0 2>/dev/null || true" || true

    # vwifi: add virtual interfaces
    local mac_prefix="52:54:00:00:0${node_id}"
    ssh_vm "$ip" "vwifi-add-interfaces 2 ${mac_prefix} 2>/dev/null || true" || true

    # Set vwifi UCI config (section name is 'config' per vwifi_cli_package README)
    ssh_vm "$ip" "
        uci set vwifi.config.server_ip='10.99.0.254'
        uci set vwifi.config.mac_prefix='${mac_prefix}'
        uci set vwifi.config.enabled='1'
        uci commit vwifi
    " || true

    # Set lime-community UCI config (type is 'lime' per LibreMesh convention)
    # Only set if sections don't already exist from lime-packages install
    ssh_vm "$ip" "
        uci get lime-community.wifi >/dev/null 2>&1 || uci set lime-community.wifi=lime
        uci set lime-community.wifi.ap_ssid='MeshaTestBed'
        uci set lime-community.wifi.apname='MeshaTestBed'
        uci set lime-community.wifi.mode='adhoc'
        uci set lime-community.wifi.channel='11'
        uci get lime-community.network >/dev/null 2>&1 || uci set lime-community.network=lime
        uci set lime-community.network.protocols='bmx7'
        uci set lime-community.network.domain='testbed.mesh'
        uci get lime-community.system >/dev/null 2>&1 || uci set lime-community.system=lime
        uci set lime-community.system.community_name='Mesha-Testbed'
        uci commit lime-community
    " || true

    # Set lime-node UCI config (section may already exist from lime-packages)
    ssh_vm "$ip" "
        uci get lime-node.network >/dev/null 2>&1 || uci set lime-node.network=lime
        uci set lime-node.network.main_ipv4_address='${ip}/16'
        uci commit lime-node
    " || true

    # Run lime-config sequence (single chain, no duplicate vwifi-client start)
    echo "  [${hostname}] Running lime-config sequence..."
    ssh_vm "$ip" "
        service vwifi-client start && \
        wifi config && \
        lime-config && \
        wifi down && \
        sleep 7 && \
        wifi up
    " || echo "  [${hostname}] WARN: lime-config sequence had errors (may be expected if vwifi-client is missing)"

    # Enable uhttpd
    ssh_vm "$ip" "
        uci set uhttpd.main.listen_http='0.0.0.0:80'
        uci commit uhttpd
        service uhttpd enable 2>/dev/null || true
        service uhttpd restart 2>/dev/null || true
    " || true

    # Set /etc/hosts with all node entries
    local hosts_entries=""
    local idx=0
    for node_ip in "${NODE_IPS[@]}"; do
        local hname="${NODE_HOSTNAMES[$idx]}"
        hosts_entries="${hosts_entries}${node_ip}	${hname}
"
        idx=$((idx + 1))
    done
    # Append to /etc/hosts (don't overwrite — keep localhost)
    ssh_vm "$ip" "cat >> /etc/hosts << 'HOSTSEOF'
${hosts_entries}HOSTSEOF" || true

    # Set /etc/openwrt_release with test firmware version
    ssh_vm "$ip" "sed -i 's/OPENWRT_RELEASE=.*/OPENWRT_RELEASE=\"Mesha Testbed v0.1.0 (LibreMesh)\"/' /etc/openwrt_release 2>/dev/null || true" || true

    echo "  [${hostname}] Phase 1 complete."
}

# ─── SSH key injection ───
generate_and_inject_keys() {
    echo ""
    echo "=== Phase 2: SSH key injection ==="

    mkdir -p "${SSH_KEY_DIR}"

    # Generate key pair if needed
    if [ ! -f "${SSH_KEY}" ]; then
        echo "  Generating ed25519 SSH key pair..."
        ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "mesha-testbed" >/dev/null
    fi

    local public_key
    public_key=$(cat "${SSH_KEY}.pub")

    local idx=0
    for ip in "${NODE_IPS[@]}"; do
        local hostname="${NODE_HOSTNAMES[$idx]}"
        echo "  [${hostname}] Injecting SSH key..."

        # Inject public key
        ssh_vm "$ip" "mkdir -p /root/.ssh && echo '${public_key}' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && chmod 700 /root/.ssh" || {
            echo "  [${hostname}] WARN: Key injection failed"
            idx=$((idx + 1))
            continue
        }

        # Lock down dropbear to key-only auth
        ssh_vm "$ip" "
            uci set dropbear.@dropbear[0].PasswordAuth='off'
            uci set dropbear.@dropbear[0].RootPasswordAuth='off'
            uci commit dropbear
            service dropbear restart
        " || echo "  [${hostname}] WARN: Could not lock dropbear"

        echo "  [${hostname}] Key injected, password auth disabled."
        idx=$((idx + 1))
    done
}

# ─── Verify key-based access ───
verify_key_access() {
    echo ""
    echo "=== Verifying key-based SSH access ==="
    local idx=0
    local ok=0
    for ip in "${NODE_IPS[@]}"; do
        local hostname="${NODE_HOSTNAMES[$idx]}"
        if ssh_vm_with_key "$ip" "echo 'key auth works'" &>/dev/null; then
            echo "  [${hostname}] OK — key-based SSH working"
            ok=$((ok + 1))
        else
            echo "  [${hostname}] WARN — key-based SSH not working"
        fi
        idx=$((idx + 1))
    done
    echo "  ${ok}/${#NODE_IPS[@]} VMs accessible via key-based SSH"
}

# ─── Main ───
main() {
    echo "=========================================="
    echo " Mesha VM Configuration"
    echo "=========================================="
    echo ""

    parse_topology

    # Phase 0: Wait for all VMs to be SSH-reachable
    echo "=== Phase 0: Waiting for VMs to boot ==="
    local idx=0
    local failed=0
    for ip in "${NODE_IPS[@]}"; do
        local hostname="${NODE_HOSTNAMES[$idx]}"
        if ! wait_for_ssh "$ip" "$hostname"; then
            failed=$((failed + 1))
        fi
        idx=$((idx + 1))
    done

    if [ "$failed" -gt 0 ]; then
        echo ""
        echo "ERROR: ${failed} VM(s) not reachable via SSH. Aborting configuration."
        exit 1
    fi

    # Phase 1: Basic configuration
    echo ""
    echo "=== Phase 1: Configuring LibreMesh ==="
    idx=0
    for ip in "${NODE_IPS[@]}"; do
        local hostname="${NODE_HOSTNAMES[$idx]}"
        local node_id=$((idx + 1))
        configure_vm "$node_id" "$ip" "$hostname"
        idx=$((idx + 1))
    done

    # Configure thisnode.info on host (for discover-from-thisnode.sh)
    echo "Configuring thisnode.info resolution on host..."
    if [ -w /etc/hosts ]; then
        grep -q 'thisnode.info' /etc/hosts 2>/dev/null || \
            echo "10.99.0.11  thisnode.info" >> /etc/hosts
    else
        # Alternative: create HOSTALIASES file
        mkdir -p "${REPO_ROOT}/testbed/run"
        echo "thisnode.info 10.99.0.11" > "${REPO_ROOT}/testbed/run/host-aliases"
        echo "  Note: set HOSTALIASES=${REPO_ROOT}/testbed/run/host-aliases for thisnode.info resolution"
    fi

    # Phase 2: SSH keys
    generate_and_inject_keys

    # Verification
    verify_key_access

    # Generate SSH config with absolute paths
    sed "s|__REPO_ROOT__|${REPO_ROOT}|g" \
        "${REPO_ROOT}/testbed/config/ssh-config" \
        > "${REPO_ROOT}/testbed/config/ssh-config.resolved"

    echo ""
    echo "=========================================="
    echo " Configuration complete!"
    echo " SSH key: ${SSH_KEY}"
    echo " Connect: ssh -i ${SSH_KEY} root@10.99.0.1{1,2,3,4}"
    echo "=========================================="
}

main "$@"
