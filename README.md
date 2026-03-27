# MacBookPro14,2-linux

This repository is for my `MacBookPro14,2` running Omarchy.

## Machine

- Model identifier: `MacBookPro14,2`
- Marketing model: `MacBook Pro (13-inch, 2017, Four Thunderbolt 3 Ports)`
- Vendor: `Apple Inc.`
- Board ID: `Mac-CAD6701F7CEA0921`

## Current system snapshot

- Distribution: `CachyOS`
- Kernel: `6.19.10-1-cachyos` (LTS: `6.18.20-1-cachyos-lts`)
- Bootloader: `Limine`
- Compositor: `niri 25.11`
- Display manager: `SDDM`
- CPU: `Intel Core i7-7567U (Kaby Lake)`
- GPU: `Intel Iris Plus Graphics 650 (i915)`
- Memory: `15 GiB`
- Storage: `Apple SSD AP0512J (NVMe)`
- Wi-Fi: `BCM43602 (14e4:43ba)`
- Thunderbolt: `Intel JHL6540 Alpine Ridge 4C (×2, blacklisted)`

## Purpose

This repo is a simple place to keep notes, configuration, and machine-specific setup related to this MacBook running Omarchy.

## Documents

- [`omarchy-setup.md`](./omarchy-setup.md) — current Omarchy, hardware, and wireless setup notes for this machine
- [`wireless-solutions.md`](./wireless-solutions.md) — all known solutions for the BCM43602 (`14e4:43ba`) wireless adapter, with weights, tradeoffs, step-by-step instructions, and the `wl` driver investigation log
- [`mihomo-setup.md`](./mihomo-setup.md) — notes on the user-local `mihomo` proxy installation and verification
- [`suspend-resume-fix.md`](./suspend-resume-fix.md) — fixes for system freeze and slow resume after lid close/open (Apple NVMe D3 Cold + Thunderbolt timeout)

## Scripts

- [`switch-to-brcmfmac.sh`](./switch-to-brcmfmac.sh) — switches from the proprietary `wl` driver to the open-source `brcmfmac` driver for BCM43602 (`14e4:43ba`); supports `--undo` to reverse
