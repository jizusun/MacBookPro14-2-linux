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
- Active driver: `brcmfmac`
- Installed modules available: `brcmfmac`, `wl`
- Interface: `wlan0`

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

### 5. Install the Broadcom proprietary package

If the `wl` package is needed on this system, install it with:

```bash
sudo pacman -S --needed broadcom-wl
```

Then verify that the package is installed:

```bash
pacman -Q broadcom-wl
```

At the time of writing, the installed package is:

- `broadcom-wl 6.30.223.271-679`

### 6. Verify the active wireless driver

Check both the driver bound to the device and the loaded modules:

```bash
lspci -nnk | grep -A4 -Ei 'network|wireless|broadcom'
lsmod | grep -E '^wl\\b|^brcmfmac|^bcma|^ssb\\b|^brcmsmac'
iw dev
```

Current verified state on this machine:

- Adapter: `Broadcom BCM43602 802.11ac Wireless LAN SoC`
- Interface: `wlan0`
- Active driver: `brcmfmac`
- Installed modules visible: `brcmfmac`, `wl`

### 7. Recover the proprietary `wl` driver

If `broadcom-wl` is installed but `wl` still fails to initialize on this
machine, the repo includes a helper script that switches to the DKMS-backed
package and rewrites the BCM43602 blacklist file:

```bash
sudo ./repair-broadcom-wl.sh
```

What the script does:

- removes the stock `broadcom-wl` package if present
- installs `broadcom-wl-dkms`, `dkms`, and `linux-headers`
- writes `/etc/modprobe.d/broadcom-wl-bcm43602.conf`
- refreshes module dependencies
- attempts a live `wl` reload, but still expects a reboot afterward

After running it, reboot and then verify:

```bash
lspci -k -s 02:00.0
iw dev
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

The proprietary Broadcom `wl` package is installed, but the system is currently
still using `brcmfmac` as the active kernel driver.

The exact original Omarchy installation date is not recorded here yet; this
document reflects the verified setup state documented on `2026-03-15`.
