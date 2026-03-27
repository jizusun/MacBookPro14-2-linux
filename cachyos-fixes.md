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

## Fix 3: Touchpad Palm Rejection (niri)

Cursor jumps unexpectedly while typing because the Apple SPI Touchpad registers accidental palm touches.

### Apply

Add `dwt` to the touchpad block in `~/.config/niri/cfg/input.kdl`:

```kdl
touchpad {
    tap
    natural-scroll
    dwt // Disable while typing
}
```

Niri hot-reloads the config automatically. If the cursor still jumps, also add `dwtp` (disable while trackpad pressing).

## Fix 4: Touch Bar (roadrunner2 driver)

The upstream kernel Touch Bar drivers (`appletbdrm`, `hid-appletb-bl`, `hid-appletb-kbd`) are for T2 Macs (2018+) and don't work on the 2017 iBridge. The `t2linux/apple-ib-drv` driver crashes on kernel 6.19. The working driver is [roadrunner2/macbook12-spi-driver](https://github.com/roadrunner2/macbook12-spi-driver) (`touchbar-driver-hid-driver` branch), patched for kernel 6.19 API changes.

### Prerequisites

- Apple EFI partition (`nvme0n1p1`) must contain the iBridge firmware — keep macOS installed or at least preserve the EFI partition
- `usbmuxd` must not claim the iBridge device (`05ac:8600`) — remove it from udev rules if present
- CachyOS kernel is built with clang/LLVM, so modules must be built with `CC=clang LD=ld.lld`

### Build & Install

```bash
sudo pacman -S --needed dkms linux-cachyos-headers

git clone --branch touchbar-driver-hid-driver \
  https://github.com/roadrunner2/macbook12-spi-driver.git
cd macbook12-spi-driver

# Remove applespi (already in-kernel) and apple-ib-als (broken API, not needed)
sed -i '/applespi\|apple-ib-als/d' Makefile
```

Apply these patches for kernel 6.19 compatibility:

`apple-ibridge.c`:
- Remove `.owner = THIS_MODULE` from `appleib_driver` struct (field removed from `struct acpi_driver`)
- Change `appleib_remove` return type from `int` to `void`, remove `return 0`
- Change `appleib_report_fixup` return type from `__u8 *` to `const __u8 *`

`apple-ib-tb.c`:
- Change `appletb_platform_remove` return type from `int` to `void`, remove error handling and `return`

```bash
make CC=clang LD=ld.lld
sudo mkdir -p /lib/modules/$(uname -r)/updates
sudo cp apple-ibridge.ko apple-ib-tb.ko /lib/modules/$(uname -r)/updates/
sudo depmod
```

### Configure

```bash
# Auto-load on boot
printf 'apple-ibridge\napple-ib-tb\n' | sudo tee /etc/modules-load.d/apple-touchbar.conf

# Blacklist upstream T2-only drivers
printf 'blacklist appletbdrm\nblacklist hid-appletb-bl\nblacklist hid-appletb-kbd\n' \
  | sudo tee /etc/modprobe.d/no-upstream-touchbar.conf
```

### Verify

```bash
# After reboot
lsmod | grep apple_ib
# Expected: apple_ib_tb, apple_ibridge

# Check dmesg for errors
sudo dmesg | grep -i "apple-ibridge\|apple_ib"
```

### Notes

- Modules must be rebuilt after each kernel update (`make CC=clang LD=ld.lld`)
- Reference: [roadrunner2's gist](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7) and [Drayux's comment](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7?permalink_comment_id=4937505#gistcomment-4937505)

## Fix 5: Libinput Touchpad/Keyboard/Touchbar Quirks

Touchpad DPI, touch size, palm rejection thresholds, and keyboard/touchbar integration flags are not set by default for the Apple SPI devices.

### Apply

```bash
sudo mkdir -p /etc/libinput
sudo tee /etc/libinput/local-overrides.quirks << 'EOF'
[MacBook(Pro) SPI Touchpads]
MatchName=*Apple SPI Touchpad*
ModelAppleTouchpad=1
AttrTouchSizeRange=200:150
AttrPalmSizeThreshold=1100

[MacBook(Pro) SPI Keyboards]
MatchName=*Apple SPI Keyboard*
AttrKeyboardIntegration=internal

[MacBookPro Touchbar]
MatchBus=usb
MatchVendor=0x05AC
MatchProduct=0x8600
AttrKeyboardIntegration=internal
EOF
```

Reboot or re-login to apply.

## Fix 6: Audio (Cirrus Logic CS8409)

The upstream `snd-hda-codec-cs8409` driver detects the codec but produces no sound on MacBook Pros. The [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) out-of-tree driver is needed.

Since CachyOS kernels are built with clang, the install script must use `LLVM=1`.

### Apply

```bash
git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro

# Patch install script for LLVM/clang-built kernels
sed -i 's/^\t\tmake \(PATCH_CIRRUS=1\)$/\t\tmake LLVM=1 \1/' install.cirrus.driver.sh
sed -i 's/^\t\tmake install \(PATCH_CIRRUS=1\)$/\t\tmake LLVM=1 install \1/' install.cirrus.driver.sh
sed -i 's/^\t\tmake \(KERNELRELEASE=\$UNAME\)$/\t\tmake LLVM=1 \1/' install.cirrus.driver.sh
sed -i 's/^\t\tmake install \(KERNELRELEASE=\$UNAME\)$/\t\tmake LLVM=1 install \1/' install.cirrus.driver.sh

sudo ./install.cirrus.driver.sh
sudo reboot
```

### Verify

```bash
# After reboot, confirm patched module is loaded from updates/
modinfo snd-hda-codec-cs8409 | head -2
# filename should contain /updates/

# Test audio
speaker-test -c 2 -t wav -l 1
```

### Notes

- Must be rebuilt after every kernel update
- Reference: [roadrunner2's gist](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7) and [gist comments (Jan 2026)](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7?permalink_comment_id=5949932#gistcomment-5949932)
