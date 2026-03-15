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

### 5. Test the Broadcom proprietary package path

If the proprietary `wl` path is being tested on this system, use the repo
helper instead of manually reproducing the Omarchy package commands:

```bash
sudo ./repair-broadcom-wl.sh
```

That helper:

- removes `broadcom-wl-dkms` if it is present
- installs `broadcom-wl`, `dkms`, and `linux-headers`
- writes `/etc/modprobe.d/broadcom-wl-bcm43602.conf`
- refreshes module dependencies
- rebuilds initramfs
- attempts a live `wl` reload, but still expects a reboot afterward

Then verify the resulting package state:

```bash
pacman -Q broadcom-wl dkms linux-headers
```

This mirrors Omarchy's current `fix-bcm43xx.sh` installer path, adapted here
for the local BCM43602 machine-specific helper.

The local helper also mirrors Omarchy's `lspci -nnv` detection style, but adds
an explicit match for this machine's `14e4:43ba` PCI ID.

### 6. Verify the active wireless driver

Check both the driver bound to the device and the loaded modules:

```bash
lspci -nnk | grep -A4 -Ei 'network|wireless|broadcom'
lsmod | grep -E '^wl\\b|^brcmfmac|^bcma|^ssb\\b|^brcmsmac'
iw dev
```

Current verified state on this machine:

- Adapter: `Broadcom BCM43602 802.11ac Wireless LAN SoC`
- Interface: none
- `iw dev` is empty
- `wl` is loaded
- `cfg80211` is loaded
- `lspci -k -s 02:00.0` does not currently show a working Wi-Fi driver in use

### 7. Recover the proprietary `wl` driver

If `broadcom-wl` is installed but `wl` still fails to initialize on this
machine, the repo includes a helper script that aligns the package selection
with Omarchy's current Broadcom fix, rewrites the BCM43602 blacklist file, and
rebuilds initramfs:

```bash
sudo ./repair-broadcom-wl.sh
```

After running it, reboot and then verify:

```bash
lspci -k -s 02:00.0
pacman -Q broadcom-wl dkms linux-headers
iw dev
nmcli device status
sudo journalctl -k -b --no-pager | grep -Ei 'wl|brcm|cfg80211|firmware'
```

If `iw dev` is still empty and `lspci -k` still does not show
`Kernel driver in use: wl`, do not assume another `wl` reinstall will fix it.
For this repo, keep the machine on the proprietary `wl` path and re-check the
package and live device state:

```bash
sudo ./repair-broadcom-wl.sh
pacman -Q broadcom-wl dkms linux-headers
```

Before changing any other part of the stack, capture the failed `wl` boot
evidence with:

```bash
lspci -k -s 02:00.0
iw dev
nmcli device status
sudo journalctl -k -b --no-pager | grep -Ei 'wl|brcm|cfg80211|firmware'
```

If `wl` later exposes an interface but association still fails while using
`iwd`, test the NetworkManager path instead:

```bash
sudo pacman -S --needed networkmanager
sudo systemctl disable --now iwd
sudo systemctl enable --now NetworkManager.service
nmcli device status
```

### 8. Update the repo docs safely

When updating this repo:

- Keep personal names out of the repo.
- Use generic wording or `redacted` for personal hostnames or identifiers.
- Prefer verified values from commands over assumptions.
- Keep local changes uncommitted unless explicitly asked to commit or push.

## Notes

This machine is running the Omarchy distro on Apple hardware, so display, power,
keyboard, and desktop behavior may include Apple-specific integrations exposed
through Omarchy commands and Hyprland configuration.

The DKMS-backed Broadcom `wl` package is installed, but the system still does
not expose a working Wi-Fi interface from the internal BCM43602.

The exact original Omarchy installation date is not recorded here yet; this
document reflects the verified setup state documented on `2026-03-15`.
