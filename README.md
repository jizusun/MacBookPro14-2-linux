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
- [`wireless-solutions.md`](./wireless-solutions.md) — all known solutions for the BCM43602 (`14e4:43ba`) wireless adapter, with weights, tradeoffs, step-by-step instructions, and the `wl` driver investigation log
- [`mihomo-setup.md`](./mihomo-setup.md) — notes on the user-local `mihomo` proxy installation and verification
- [`sleep-lid-solutions.md`](./sleep-lid-solutions.md) — fix for lid-close wake failure and excessive battery drain (`s2idle` + NVMe d3cold)

## Scripts

- [`switch-to-brcmfmac.sh`](./switch-to-brcmfmac.sh) — switches from the proprietary `wl` driver to the open-source `brcmfmac` driver for BCM43602 (`14e4:43ba`); supports `--undo` to reverse
