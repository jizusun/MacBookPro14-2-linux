# Broadcom BCM43602 `wl` Investigation

This document records the current issue with the internal Broadcom Wi-Fi
adapter on this `MacBookPro14,2`, the local evidence gathered on
`2026-03-15`, and the external references that informed the current fix path.

## Problem statement

The machine contains a `Broadcom BCM43602 802.11ac Wireless LAN SoC`
(`14e4:43ba`). The goal is to use the proprietary `wl` driver, but the
currently installed non-DKMS `broadcom-wl` package does not bring up a wireless
interface on the running kernel.

Symptoms observed during investigation:

- the Broadcom PCI device is present
- the `wl` kernel module loads, then aborts during initialization
- no Wi-Fi interface is created
- the only active non-loopback network interface is a separate USB/Thunderbolt
  Ethernet adapter, `enp6s0u2`

## Local investigation summary

### Hardware and interface state

Current live checks showed:

```bash
ip -brief link
lspci -nnk | sed -n '/Network controller\\|Wireless\\|Ethernet controller/,+4p'
ls -1 /sys/class/net
```

Observed state:

- `lo` exists as expected
- `enp6s0u2` is up and active
- no `wlan0` or other Wi-Fi interface is present
- the internal wireless hardware is `Broadcom BCM43602 802.11ac Wireless LAN SoC [14e4:43ba]`

### Driver and module state

Relevant checks:

```bash
lspci -nnk -d 14e4:43ba
lsmod | grep -E '^(wl|brcmfmac|brcmutil|cfg80211|bcma|ssb)\\b'
iw dev
rfkill list
```

Observed state:

- `rfkill` showed no Wi-Fi block
- `iw dev` showed no wireless interface
- `wl` was loaded
- `cfg80211` was loaded
- the device had no active bound driver shown by `lspci -k`

### Package and blacklist state

Relevant checks:

```bash
pacman -Q broadcom-wl linux linux-headers
sed -n '1,120p' /usr/lib/modprobe.d/broadcom-wl.conf
modinfo wl | sed -n '1,120p'
```

Observed state:

- installed package: `broadcom-wl 6.30.223.271-679`
- running kernel: `6.19.6-arch1-1`
- `wl` module file: `/lib/modules/6.19.6-arch1-1/extramodules/wl.ko.zst`
- standard `broadcom-wl` blacklist file was already present and blacklisting:
  - `b43`
  - `b43legacy`
  - `bcm43xx`
  - `bcma`
  - `brcm80211`
  - `brcmfmac`
  - `brcmsmac`
  - `ssb`

This means the failure is not explained by missing blacklist entries alone.

### Kernel log evidence

The most important evidence came from the kernel journal:

```bash
journalctl -k -b --no-pager | grep -Ei 'brcm|wl|cfg80211|wlan|firmware'
```

Key messages observed:

```text
wl: loading out-of-tree module taints kernel.
You are using the broadcom-wl driver, which is not maintained and is incompatible with Linux kernel security mitigations.
Unpatched return thunk in use. This should not happen!
wl driver 6.30.223.271 (r587334) failed with code 1
ERROR @wl_cfg80211_detach :
NULL ndev->ieee80211ptr, unable to deref wl
```

This is the strongest sign that the current failure is not just a missing
userspace configuration. The proprietary module is being loaded but is then
aborting very early in initialization on the current kernel.

### Other checks that ruled things out

- `sudo -n true` failed because an interactive password is required, so no live
  privileged remediation was applied during the investigation session itself
- no `facetimehd` / `bcwc_pcie` webcam module conflict was detected in the
  current boot
- the USB Ethernet adapter `enp6s0u2` was confirmed to be separate from the
  internal Broadcom Wi-Fi card
- `pacman.log` showed `broadcom-wl` was installed during the current day, so a
  clean reboot is still required after any package-level fix

## Conclusion from the investigation

The current problem is best described as:

> The BCM43602 hardware is present, the proprietary `wl` module is installed,
> but the stock non-DKMS `broadcom-wl` package fails to initialize cleanly on
> the running kernel, leaving the Broadcom device unbound and no Wi-Fi
> interface exposed.

Based on the collected evidence, the most practical `wl`-preserving next step
is:

1. replace `broadcom-wl` with `broadcom-wl-dkms`
2. keep an explicit BCM43602 blacklist file in `/etc/modprobe.d/`
3. reboot
4. verify whether `wl` binds cleanly on the next boot

This is why the repo now includes:

```bash
sudo ./repair-broadcom-wl.sh
```

## Recommended next steps

Run:

```bash
sudo ./repair-broadcom-wl.sh
```

Then reboot and verify:

```bash
lspci -k -s 02:00.0
iw dev
nmcli device status
journalctl -k -b --no-pager | grep -Ei 'wl|brcm|cfg80211'
```

## Detailed references

### Primary upstream and distro references

1. ArchWiki, **Broadcom wireless**
   - https://wiki.archlinux.org/title/Broadcom_wireless
   - Relevant points:
     - `BCM43602` is explicitly called out
     - the page documents the `brcmfmac.feature_disable=0x82000` path for
       `14e4:43ba`
     - it also documents both `broadcom-wl` and `broadcom-wl-dkms`
     - it notes that a reboot or reinstall may be needed after kernel updates

2. Omarchy issue **2016 MacBook Pro bizarre WiFi behavior**
   - https://github.com/basecamp/omarchy/issues/1022
   - Why it matters:
     - multiple Apple/Broadcom users discussed `14e4:43a0` and `14e4:43ba`
     - the issue thread moved from `brcmfmac.feature_disable=0x82000` toward
       reports that `broadcom-wl` was still required for some machines

3. Omarchy pull request **DRAFT: Fix Broadcom wifi on mid-2010s MacBooks**
   - https://github.com/basecamp/omarchy/pull/1143
   - Especially relevant discussion:
     - users with `14e4:43ba` reported that the feature-disable flag alone was
       not sufficient
     - one contributor reported better results with `broadcom-wl-dkms` plus a
       BCM43602-specific blacklist file

4. Omarchy pull request **Add modifications to support Offline ISO**
   - https://github.com/basecamp/omarchy/pull/1621
   - Why it matters:
     - this PR included Broadcom/Mac-related installer handling
     - the review discussion referenced placing Apple Broadcom fixes in Omarchy
       hardware scripts

### Additional issue threads with matching failure signatures

5. ublue-os main issue **Wireless device disappeared after recent update**
   - https://github.com/ublue-os/main/issues/244
   - Relevant because:
     - it involved a `BCM43602`
     - it showed the same `wl driver ... failed with code 1`
     - it showed the same `NULL ndev->ieee80211ptr, unable to deref wl`

6. patjak/facetimehd issue **Enabling facetimehd breaks wl**
   - https://github.com/patjak/facetimehd/issues/135
   - Relevant because:
     - it showed the same `failed with code 1` and
       `NULL ndev->ieee80211ptr` signature
     - it demonstrates that Apple hardware can trigger this family of `wl`
       initialization failures
   - Why it was not treated as the root cause here:
     - the current machine did not have the `facetimehd` / `bcwc_pcie` modules
       loaded during investigation

7. sebanc/brunch issue **broadcom_wl does not work since February 2021 update any more**
   - https://github.com/sebanc/brunch/issues/878
   - Relevant because:
     - it contains the same `NULL ndev->ieee80211ptr` error family
     - it is another data point showing that `wl` can fail after platform or
       kernel changes even when hardware is detected

## Notes for future updates

- If the DKMS-based `wl` path works, update this document with the post-reboot
  verification output.
- If it still fails, the next escalation path is likely one of:
  - testing a different kernel version with `wl`
  - testing a patched Apple-specific Broadcom STA tree
  - reconsidering the `brcmfmac` path despite the preference for `wl`
