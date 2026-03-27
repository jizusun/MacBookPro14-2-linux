# Suspend/Resume Fix

Fixes for system freeze and slow resume after closing and opening the lid.

## Problem

After closing the lid (suspend) and reopening it:

1. **System appeared frozen** — mouse moved but clicking buttons did nothing, apps wouldn't launch, couldn't shut down
2. **Resume took ~65 seconds** even after fix #1

## Root Causes

### 1. Apple NVMe not waking from D3 Cold

The Apple SSD (`AP0512J`) does not support APST (`apsta: 0`) and fails to wake properly from D3 Cold power state during resume. Since the mouse/compositor state is in RAM, the cursor moves — but any disk I/O (launching apps, saving state, shutdown) silently hangs.

### 2. Thunderbolt controllers timing out on resume

Two Intel Alpine Ridge Thunderbolt 3 controllers (`JHL6540`) fail to resume and the kernel waits ~65 seconds per controller before giving up:

```
xhci_hcd 0000:7c:00.0: not ready 65535ms after resume; giving up
xhci_hcd 0000:06:00.0: not ready 65535ms after resume; giving up
```

## Fixes Applied

### Fix 1: Disable D3 Cold for Apple NVMe

```bash
echo 'ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x106b", ATTR{d3cold_allowed}="0"' | sudo tee /etc/udev/rules.d/50-apple-nvme-no-d3cold.rules
sudo udevadm control --reload-rules
```

This prevents the Apple NVMe from entering D3 Cold during suspend. Uses vendor ID (`0x106b` = Apple) so it's not tied to a specific PCI address.

### Fix 2: Blacklist Thunderbolt module

```bash
echo "blacklist thunderbolt" | sudo tee /etc/modprobe.d/no-thunderbolt.conf
```

Since no Thunderbolt peripherals are used, blacklisting the module entirely eliminates the 65-second timeout on resume. To unload immediately without rebooting:

```bash
sudo modprobe -r thunderbolt
```

## Other Notes

- Sleep state is already set to `deep` (S3): `cat /sys/power/mem_sleep` → `s2idle [deep]`
- Hibernate is not configured (only zram swap, no disk-backed swap)
- `i915.enable_psr=0` was considered but not needed — the freeze was NVMe-related, not GPU
- Lid close action is the systemd default: suspend
