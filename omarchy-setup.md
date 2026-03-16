# Omarchy on MacBookPro14,2

This document tracks the current Omarchy setup on this machine.

## Overview

### System

- Distribution: `Omarchy`
- Omarchy version: `3.4.2`
- Omarchy branch: `master`
- Kernel: `6.19.6-arch1-1`
- Hostname: redacted

### Desktop stack

- Compositor / window manager: `Hyprland 0.54.1`
- Status bar: `waybar`
- Idle / lock tools: `hypridle`, `hyprlock`
- Notifications: `mako`
- App launcher: `walker`

### Appearance

- Theme: `Tokyo Night`
- Font: `JetBrainsMono Nerd Font`
- Active theme assets: `~/.config/omarchy/current/theme/`

### Hardware

- Model identifier: `MacBookPro14,2`
- Marketing model: `MacBook Pro (13-inch, 2017, Four Thunderbolt 3 Ports)`
- Vendor: `Apple Inc.`
- Board ID: `Mac-CAD6701F7CEA0921`
- CPU: `Intel Core i7-7567U`
- Memory: `15 GiB`
- Graphics: `Intel Iris Plus Graphics 650`
- Internal display: `2560x1600`

### Wireless

- Adapter: `Broadcom BCM43602 802.11ac Wireless LAN SoC`
- PCI ID: `14e4:43ba`
- Active driver: none currently bound cleanly for Wi-Fi use
- Installed modules available: `brcmfmac`, `wl`
- Interface: none visible in `iw dev`

### Main config locations

- `~/.config/omarchy/`
- `~/.config/hypr/`
- `~/.config/waybar/`
- `~/.config/walker/`
- `~/.config/mako/`
- `~/.config/kitty/`
- `~/.config/ghostty/`
- `~/.config/alacritty/`

### Common user-edited files

- `~/.config/hypr/hyprland.conf`
- `~/.config/hypr/looknfeel.conf`
- `~/.config/hypr/monitors.conf`
- `~/.config/waybar/config.jsonc`
- `~/.config/waybar/style.css`
- `~/.config/omarchy/current/theme/`

## Detailed setup guide

This section explains how to document and re-check this setup in a repeatable way
on the same machine.

### 1. Identify the MacBook model

Use Linux hardware identifiers to confirm the Apple model:

```bash
cat /sys/devices/virtual/dmi/id/sys_vendor
cat /sys/devices/virtual/dmi/id/product_name
cat /sys/devices/virtual/dmi/id/board_name
```

Expected values on this machine:

- Vendor: `Apple Inc.`
- Model identifier: `MacBookPro14,2`
- Board ID: `Mac-CAD6701F7CEA0921`

### 2. Confirm the Omarchy release and current appearance

Check the installed Omarchy release plus the active theme and font:

```bash
omarchy-version
omarchy-theme-current
omarchy-font-current
uname -r
```

Expected values at the time of writing:

- Omarchy version: `3.4.2`
- Theme: `Tokyo Night`
- Font: `JetBrainsMono Nerd Font`
- Kernel: `6.19.6-arch1-1`

### 3. Review the desktop configuration

Inspect the main user-facing Omarchy and Hyprland configuration:

```bash
ls ~/.config/omarchy
ls ~/.config/hypr
ls ~/.config/waybar
```

Main files and directories to review:

- `~/.config/omarchy/current/theme/`
- `~/.config/hypr/hyprland.conf`
- `~/.config/hypr/looknfeel.conf`
- `~/.config/hypr/monitors.conf`
- `~/.config/waybar/config.jsonc`
- `~/.config/waybar/style.css`

### 4. Verify the machine hardware snapshot

Collect the core hardware details used in this repo:

```bash
lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1
free -h | awk '/^Mem:/ {print $2}'
lspci -nnk | grep -A4 -Ei 'network|wireless|broadcom'
```

This machine currently reports:

- CPU: `Intel Core i7-7567U`
- Memory: `15 GiB`
- Wireless adapter: `Broadcom BCM43602`

### 5. Test available wireless solutions

For a full list of known solutions for the BCM43602 (`14e4:43ba`) adapter
The recommended approach for this machine is to use the open-source `brcmfmac`
driver with the `brcmfmac.feature_disable=0x82000` kernel parameter
(Solution 1 in `wireless-solutions.md`). This is the confirmed fix for
BCM43602 on Omarchy (issue #4611, discussion #4692).

The proprietary `wl` driver is **broken on kernel 6.19+** and has never been
confirmed working for `14e4:43ba` in the omarchy community. See
`wireless-solutions.md` (Appendix A) for the full analysis.

To switch to `brcmfmac`:

```bash
sudo ./switch-to-brcmfmac.sh
```

Then reboot and verify:

```bash
lsmod | grep brcmfmac        # driver loaded
iw dev                        # wireless interface present
nmcli device wifi list        # nearby networks visible
```

If no networks appear, set the regulatory domain (Solution 2):

```bash
sudo pacman -S --needed wireless-regdb
sudo iw reg set CN            # use your country code
```

For full details on all available solutions, see:

- [`wireless-solutions.md`](./wireless-solutions.md)

### 6. Verify the active wireless driver

Check both the driver bound to the device and the loaded modules:

```bash
lspci -nnk | grep -A4 -Ei 'network|wireless|broadcom'
lsmod | grep -E '^wl\b|^brcmfmac|^bcma|^ssb\b|^brcmsmac'
iw dev
```

### 7. Fix the escape key (Touch Bar / applespi)

The MacBookPro14,2 Touch Bar keyboard is connected over SPI.  Without the
`applespi` driver loaded, the Touch Bar is silent — including the physical Esc key.

The Omarchy installer handles this via `fix-apple-spi-keyboard.sh` for all
`MacBookPro14,[123]` models.  To apply manually:

```bash
# 1. Install the out-of-tree SPI keyboard driver (AUR)
yay -S macbook12-spi-driver-dkms

# 2. Add the required modules to the initramfs
echo 'MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)' \
  | sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf

# 3. Rebuild initramfs and reboot
sudo mkinitcpio -P
sudo reboot
```

After reboot, verify the module is loaded:

```bash
lsmod | grep applespi      # should appear
```

The Touch Bar will still not display its context-sensitive UI (that requires
a separate T1/T2 driver stack not available for this model), but the Esc key
and all Touch Bar function-key areas will emit standard HID key events.

**References:**
- Omarchy `fix-apple-spi-keyboard.sh` —
  https://github.com/basecamp/omarchy/blob/dev/install/config/hardware/fix-apple-spi-keyboard.sh

---

### 8. Fix USB tethering re-connect

When a USB-tethered device (phone in USB tethering mode, or a USB ethernet
adapter) is unplugged and replugged, it may not be re-recognised by
NetworkManager.  The root cause is Linux USB autosuspend — the kernel powers
the USB port down between plug events, and the device re-enumeration can fail.

The Omarchy installer applies this fix globally via `usb-autosuspend.sh`.
To apply manually:

```bash
# Disable USB autosuspend for all devices
echo 'options usbcore autosuspend=-1' \
  | sudo tee /etc/modprobe.d/disable-usb-autosuspend.conf

# Rebuild initramfs so the option is present from early boot
sudo mkinitcpio -P

sudo reboot
```

After reboot, replugging the adapter should cause it to be enumerated
immediately and NetworkManager will create a new connection profile
(or reuse an existing one with `autoconnect=yes`).

**Verify:**

```bash
lsusb                          # adapter appears after replug
nmcli device status            # new ethernet/usb device visible
```

**References:**
- Omarchy `usb-autosuspend.sh` —
  https://github.com/basecamp/omarchy/blob/dev/install/config/hardware/usb-autosuspend.sh

---

### 9. Fix lid-close wake failure and battery drain

See [`sleep-lid-solutions.md`](./sleep-lid-solutions.md) for the full walkthrough.

**TL;DR:** add `mem_sleep_default=s2idle` to the kernel cmdline, set
`HandleLidSwitch=sleep` in logind, and disable NVMe D3-cold with a systemd
service.  This switches the machine from broken `deep` S3 sleep to `s2idle`
(suspend-to-idle), which wakes reliably and drains far less battery.

---

### 10. Update the repo docs safely

When updating this repo:

- Keep personal names out of the repo.
- Use generic wording or `redacted` for personal hostnames or identifiers.
- Prefer verified values from commands over assumptions.
- Keep local changes uncommitted unless explicitly asked to commit or push.

## Notes

This machine is running the Omarchy distro on Apple hardware, so display, power,
keyboard, and desktop behavior may include Apple-specific integrations exposed
through Omarchy commands and Hyprland configuration.

The exact original Omarchy installation date is not recorded here yet; this
document reflects the verified setup state documented on `2026-03-15`, updated
`2026-03-16` to switch from the proprietary `wl` path to `brcmfmac`.
