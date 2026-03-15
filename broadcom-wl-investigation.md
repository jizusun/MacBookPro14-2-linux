# Broadcom BCM43602 `wl` Investigation

This document records the current issue with the internal Broadcom Wi-Fi
adapter on this `MacBookPro14,2`, the local evidence gathered on
`2026-03-15`, and the external references that informed the current fix path.

## Problem statement

The machine contains a `Broadcom BCM43602 802.11ac Wireless LAN SoC`
(`14e4:43ba`). The preferred goal was to use the proprietary `wl` driver.
That led to replacing the stock `broadcom-wl` package with
`broadcom-wl-dkms` and rebooting.

After that cleanup, Wi-Fi is still not up:

- `broadcom-wl-dkms` is installed
- `wl` is loaded
- `iw dev` is empty
- the Broadcom PCI function still does not show a working wireless interface

Symptoms observed during investigation:

- the Broadcom PCI device is present
- the `wl` kernel module loads, but no Wi-Fi interface appears
- no Wi-Fi interface is created
- the only active non-loopback network interface is a separate USB/Thunderbolt
  Ethernet adapter, `enp6s0u2`

## Local investigation summary

### Current post-reboot hardware and interface state

Current live checks showed:

```bash
lspci -k -s 02:00.0
iw dev
lsmod | grep -E '^(wl|brcmfmac|brcmutil|cfg80211|bcma|ssb)\b'
ls -1 /sys/class/net
```

Observed state:

- the internal wireless hardware is `Broadcom BCM43602 802.11ac Wireless LAN SoC [14e4:43ba]`
- `iw dev` showed no wireless interface
- `wl` was loaded
- `cfg80211` was loaded
- `lspci -k -s 02:00.0` still did not report an active `Kernel driver in use`
- only `lo` and `enp6s0u2` were present under `/sys/class/net`

### Package and blacklist state

Relevant checks:

```bash
pacman -Q broadcom-wl-dkms dkms linux linux-headers
dkms status
sed -n '1,120p' /usr/lib/modprobe.d/broadcom-wl.conf
test -f /etc/modprobe.d/broadcom-wl-bcm43602.conf
```

Observed state:

- installed package: `broadcom-wl-dkms 6.30.223.271-47`
- `dkms status` reported `broadcom-wl/6.30.223.271, 6.19.6-arch1-1, x86_64: installed`
- running kernel: `6.19.6-arch1-1`
- the package-provided `/usr/lib/modprobe.d/broadcom-wl.conf` was present and blacklisting:
  - `b43`
  - `b43legacy`
  - `bcm43xx`
  - `bcma`
  - `brcm80211`
  - `brcmfmac`
  - `brcmsmac`
  - `ssb`
- no user-owned `/etc/modprobe.d/broadcom-wl-bcm43602.conf` was present after reboot

This means the DKMS conversion happened, but it still did not result in a usable
wireless interface.

### Earlier kernel log evidence

The most important earlier evidence came from the kernel journal:

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

### Matching external report

The same failure signature was reported in `ublue-os/main#244`, also on a
`BCM43602`, with:

```text
wl driver 6.30.223.271 (r587334) failed with code 1
ERROR @wl_cfg80211_detach :
NULL ndev->ieee80211ptr, unable to deref wl
```

That issue is a useful reminder that getting `wl` onto the system is not the
same as getting a working interface from it.

## Conclusion from the investigation

The current problem is best described as:

> The BCM43602 hardware is present, `broadcom-wl-dkms` is installed, and the
> `wl` module loads, but the device still exposes no wireless interface after a
> reboot.

The earlier `broadcom-wl` to `broadcom-wl-dkms` conversion was a reasonable
cleanup step, but it was not sufficient. Based on the collected evidence, the
most practical next step is now:

1. capture privileged post-reboot kernel logs for the current failed boot
2. align the local helper with Omarchy's current `broadcom-wl` installer path
3. if `wl` later exposes an interface but association still fails, test
   `NetworkManager` instead of `iwd` before changing driver families

This is why the repo now includes:

```bash
sudo ./repair-broadcom-wl.sh
```

The helper script now mirrors Omarchy's current Broadcom package selection for
the proprietary `wl` path while still keeping the BCM43602-specific blacklist
policy local to this repo. Its hardware probe also follows Omarchy's
`lspci -nnv` detection style, extended here with an explicit `14e4:43ba`
match. It should be treated as cleanup and verification support, not as a
complete fix by itself.

## All available solution paths

For a full side-by-side comparison of every known fix (including
`wireless-regdb`, `brcmfmac` kernel parameter, proprietary `wl`, and
txpower workaround) with step-by-step instructions and tradeoffs, see:

- [`wireless-solutions.md`](./wireless-solutions.md)

The summary below focuses on the `wl`-specific investigation path only.

## Recommended next steps

First capture the current failed boot cleanly:

```bash
sudo journalctl -k -b --no-pager | grep -Ei 'wl|brcm|cfg80211|firmware'
sudo lspci -k -s 02:00.0
iw dev
nmcli device status
```

If `iw dev` is still empty and `lspci -k` still does not show
`Kernel driver in use: wl`, stay on the repo's `wl` path and re-check the
package and userspace network state:

```bash
sudo ./repair-broadcom-wl.sh
pacman -Q broadcom-wl dkms linux-headers
```

If `wl` eventually creates an interface but association still fails while using
`iwd`, test the NetworkManager path that upstream Omarchy users reported
improved behavior with:

```bash
sudo pacman -S --needed networkmanager
sudo systemctl disable --now iwd
sudo systemctl enable --now NetworkManager.service
nmcli device status
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
      - it recommends checking the in-kernel `brcm80211` path before resorting
        to other drivers

2. Omarchy issue **2016 MacBook Pro bizarre WiFi behavior**
   - https://github.com/basecamp/omarchy/issues/1022
   - Why it matters:
      - it collected reports from Apple/Broadcom users on recent Omarchy/Arch
        installs
      - it is the upstream issue linked from later Omarchy Broadcom work

3. Omarchy pull request **DRAFT: Fix Broadcom wifi on mid-2010s MacBooks**
   - https://github.com/basecamp/omarchy/pull/1143
   - Especially relevant discussion:
      - the PR explicitly targeted `14e4:43a0` and `14e4:43ba`
      - the proposed fix path was the kernel parameter
        `brcmfmac.feature_disable=0x82000`

4. Omarchy pull request **Add modifications to support Offline ISO**
   - https://github.com/basecamp/omarchy/pull/1621
   - Why it matters:
      - it included Apple/Broadcom installer handling in Omarchy itself
      - it is another sign that the MacBook Broadcom path is hardware-specific
        enough to deserve dedicated setup logic

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

- If `wl` is tried again later, record the exact privileged `journalctl` output
  for that boot rather than relying on older logs.
- If `wl` still fails, the next escalation path is likely one of:
  - testing a different kernel version
  - testing a patched Apple-specific Broadcom STA tree
  - collecting fuller upstream issue data before making more local changes
