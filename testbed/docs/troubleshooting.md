# Test Bed Troubleshooting

## VM won't boot

**Symptoms:** No serial output, QEMU process exits immediately

**Checks:**

```bash
# Verify image exists
ls -lh testbed/images/*.img

# Check QEMU version
qemu-system-x86_64 --version

# Try with more RAM
# Edit topology.yaml: ram_mb: 512 for the failing node

# Check serial log
cat testbed/run/logs/node-N.serial.log
```

**Common causes:**

- Image file missing or corrupt — rebuild with `build-libremesh-image.sh`
- KVM not available — script auto-detects and falls back to TCG
- Insufficient RAM — increase in `topology.yaml`

## vwifi-server won't start

**Symptoms:** `vwifi-server failed to start`

**Checks:**

```bash
# Check dependencies
dpkg -l cmake g++ pkg-config libnl-3-dev libnl-genl-3-dev

# Check port availability
ss -tlnp | grep 8212

# Try manual compilation
cd testbed/src/vwifi/build && cmake .. && make

# Check if binary exists
ls -la testbed/bin/vwifi-server
```

## BMX7 not forming mesh

**Symptoms:** `bmx7 -c originators` shows only self

**Checks:**

```bash
# On a VM:
ssh -F testbed/config/ssh-config.resolved root@lm-testbed-node-1
bmx7 -c status
bmx7 -c interfaces
iw dev  # Check wlan interfaces exist
logread | grep bmx7 | tail -20

# Check vwifi-client
uci show vwifi
logread | grep vwifi | tail -10

# Check mac80211_hwsim
lsmod | grep mac80211
```

**Common causes:**

- vwifi-client not connected to server — check server_ip in UCI
- mac80211_hwsim loaded with wrong radio count — must be `radios=0`
- lime-config not run — re-run configure-vms.sh

## SSH connection refused

**Symptoms:** `ssh: Connection refused` to 10.99.0.x

**Checks:**

```bash
# Verify VM running
cat testbed/run/node-N.pid && kill -0 $(cat testbed/run/node-N.pid)

# Verify bridge
ip addr show mesha-br0

# Verify TAP
ip link show mesha-tap0

# Try from QEMU monitor
# Check if VM got an IP on its eth0
```

## `ip -j` not working

**Symptoms:** Empty or non-JSON output from `ip -j addr show`

**Fix:** Install `ip-full` package in the firmware image.
Add `CONFIG_PACKAGE_ip-full=y` to `libremesh-testbed.defconfig` and rebuild.

## Bridge/TAP issues

**Symptoms:** VMs can't communicate, bridge not visible

```bash
# Show bridge members
bridge link show

# Re-create networking
sudo bash scripts/qemu-testbed/stop-mesh.sh
sudo bash scripts/qemu-testbed/start-mesh.sh
```

## Lock file stuck

**Symptoms:** "Test bed already running" but no VMs

```bash
# Remove stale lock
rm -rf testbed/run/testbed.lock

# Kill orphaned QEMU processes
pgrep -a qemu-system
kill $(pgrep qemu-system)
```

## Orphaned QEMU processes

```bash
# Find all QEMU processes
ps aux | grep qemu

# Kill specific VM
kill $(cat testbed/run/node-N.pid)

# Kill all
pkill -f qemu-system-x86_64

# Full cleanup
sudo bash scripts/qemu-testbed/stop-mesh.sh
```
