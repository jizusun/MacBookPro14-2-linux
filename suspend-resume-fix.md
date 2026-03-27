# Suspend/Resume Fix

Fixes for system freeze and slow resume after lid close/open on MacBookPro14,2.

## Symptoms

| Symptom | Cause |
|---|---|
| Mouse moves but apps/buttons unresponsive after resume | Apple NVMe stuck in D3 Cold |
| Resume takes ~65 seconds | Thunderbolt controllers timing out |

## Fix 1: Apple NVMe D3 Cold

The Apple SSD (`AP0512J`, `apsta: 0`) fails to wake from D3 Cold. Disk I/O silently hangs while the compositor (in RAM) keeps running.

### Diagnose

```bash
# Confirm Apple NVMe without APST
sudo nvme id-ctrl /dev/nvme0n1 | grep -E "mn|apsta"
# mn        : APPLE SSD AP0512J
# apsta     : 0

# Check if D3 Cold is enabled (1 = problem)
cat /sys/class/nvme/nvme0/device/d3cold_allowed
```

### Apply

```bash
echo 'ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x106b", ATTR{d3cold_allowed}="0"' \
  | sudo tee /etc/udev/rules.d/50-apple-nvme-no-d3cold.rules
sudo udevadm control --reload-rules
```

### Verify

```bash
# After reboot, confirm D3 Cold is disabled
cat /sys/class/nvme/nvme0/device/d3cold_allowed
# Expected: 0

# Suspend/resume, then check for errors
dmesg | grep -iE "nvme.*(error|timeout)"
# Expected: no output
```

## Fix 2: Blacklist Thunderbolt

Two Intel Alpine Ridge controllers (`JHL6540`) fail to resume, each waiting ~65s before giving up:

```
xhci_hcd 0000:7c:00.0: not ready 65535ms after resume; giving up
xhci_hcd 0000:06:00.0: not ready 65535ms after resume; giving up
```

Only apply this if you don't use Thunderbolt peripherals.

### Diagnose

```bash
# Check for timeout in logs after a suspend/resume cycle
journalctl -b 0 | grep "xhci_hcd.*not ready.*after resume"
```

### Apply

```bash
echo "blacklist thunderbolt" | sudo tee /etc/modprobe.d/no-thunderbolt.conf

# Unload immediately without reboot
sudo modprobe -r thunderbolt
```

### Verify

```bash
# Confirm module is not loaded
lsmod | grep thunderbolt
# Expected: no output

# After suspend/resume, confirm no timeouts
journalctl -b 0 | grep "xhci_hcd.*not ready.*after resume"
# Expected: no output
```

## Notes

- Sleep state should be `deep` (S3): `cat /sys/power/mem_sleep` → `s2idle [deep]`
- `i915.enable_psr=0` was considered but not needed — the freeze was NVMe-related, not GPU
- Hibernate requires disk-backed swap ≥ RAM size (not configured here, only zram)
