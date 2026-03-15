# MacBookPro14,2-linux

This repository is for my `MacBookPro14,2` running Omarchy.

## Machine

- Model identifier: `MacBookPro14,2`
- Marketing model: `MacBook Pro (13-inch, 2017, Four Thunderbolt 3 Ports)`
- Vendor: `Apple Inc.`
- Board ID: `Mac-CAD6701F7CEA0921`

## Current system snapshot

- Distribution: `Omarchy`
- Kernel: `6.19.6-arch1-1`
- CPU: `Intel Core i7-7567U`
- Memory: `15 GiB`

## Purpose

This repo is a simple place to keep notes, configuration, and machine-specific setup related to this MacBook running Omarchy.

## Documents

- [`omarchy-setup.md`](./omarchy-setup.md) — current Omarchy, hardware, and wireless setup notes for this machine
- [`wireless-solutions.md`](./wireless-solutions.md) — all known solutions for the BCM43602 (`14e4:43ba`) wireless adapter, with weights, tradeoffs, and step-by-step instructions
- [`broadcom-wl-investigation.md`](./broadcom-wl-investigation.md) — investigation log for the BCM43602 proprietary `wl` driver failure
- [`mihomo-setup.md`](./mihomo-setup.md) — notes on the user-local `mihomo` proxy installation and verification
- [`lid-sleep-battery.md`](./lid-sleep-battery.md) — solutions for lid-close wake failure and excessive battery drain (s2idle + NVMe fix)
- [`usb-adapter-hotplug.md`](./usb-adapter-hotplug.md) — solutions for USB/Thunderbolt Ethernet adapter not re-recognized after unplug/replug

## Scripts

- [`repair-broadcom-wl.sh`](./repair-broadcom-wl.sh) — root-runnable helper to align BCM43602 with Omarchy's current `broadcom-wl` package path, using Omarchy-style `lspci` detection extended for `14e4:43ba`
