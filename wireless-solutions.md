# Wireless Solutions for BCM43602 (`14e4:43ba`)

- **Hardware:** Broadcom BCM43602 802.11ac (3×3 MIMO, max 1300 Mbps)
- **Machine:** MacBookPro14,2 (2017 13" Touch Bar)
- **Kernel:** 6.19.6-arch1-1 · **OS:** Omarchy / Arch Linux

## TL;DR

```bash
sudo ./switch-to-brcmfmac.sh   # removes broadcom-wl, enables brcmfmac, rebuilds initramfs
sudo reboot
# after reboot:
nmcli device wifi list          # verify networks visible
nmcli device wifi connect "SSID" password "…"
```

The proprietary `wl` driver is **broken on kernel 6.19+** and has **never been
confirmed working** for `14e4:43ba` in the omarchy community. The open-source
`brcmfmac` driver with `brcmfmac.feature_disable=0x82000` is the confirmed
fix (omarchy [#4611], discussion [#4692]).

[#4611]: https://github.com/basecamp/omarchy/issues/4611
[#4692]: https://github.com/basecamp/omarchy/discussions/4692

> **Omarchy installer gap:** `fix-bcm43xx.sh` only handles `14e4:43a0`
> (BCM4360) and `14e4:4331` (BCM4331). The `14e4:43ba` (BCM43602) requires
> the manual steps in this document.

---

## Solution comparison

| # | Solution | Difficulty | Success for `14e4:43ba` | Recommended? |
|---|----------|-----------|------------------------|--------------|
| 1 | `brcmfmac` + `feature_disable=0x82000` | Low | ✅ Confirmed ([#4611], [#4692]) | ✅ Use this |
| 2 | `wireless-regdb` + `iw reg set` | Low | ✅ Combine with Solution 1 | ✅ Use with #1 |
| 3 | `broadcom-wl` (proprietary `wl`) | Medium | ❌ Broken on kernel 6.19+; never confirmed for 43ba | ❌ Do not use |
| 4 | `NetworkConfigurationEnabled` in iwd | Low | ✅ Fixes "Operation failed" if iwd misconfigured | ✅ Check first |
| 5 | Reduce `txpower` | Low | ⚠️ Works but ~25 Mbps (vs 1300 Mbps max) | ⚠️ Diagnostic only |
| 6 | Retry / wait with iwd | None | ❌ Rare, non-reproducible | ❌ Unreliable |

---

## Solution 1 — `brcmfmac` + kernel parameter ✅

The `brcmfmac` driver (open-source, in-kernel) has a feature flag that
disables power-saving and band-steering features which cause BCM43602 cards
to fail association. This is the **confirmed fix** for `14e4:43ba`.

### Automated (recommended)

```bash
sudo ./switch-to-brcmfmac.sh          # switch from wl → brcmfmac
sudo ./switch-to-brcmfmac.sh --undo   # reverse if needed
```

The script removes `broadcom-wl`, clears all `brcmfmac` blacklists, sets
`brcmfmac` to auto-load at boot, installs `wireless-regdb`, and rebuilds
the initramfs.

### Manual steps (if not using the script)

#### 1. Confirm the hardware

```bash
lspci -vnn -d 14e4:
# Expected: BCM43602 802.11ac Wireless LAN SoC [14e4:43ba]
```

#### 2. Remove `broadcom-wl` and its blacklists

```bash
# Remove the package (also removes /usr/lib/modprobe.d/broadcom-wl.conf)
sudo pacman -R --noconfirm broadcom-wl

# Remove any local blacklist files
sudo rm -f /etc/modprobe.d/broadcom-wl-bcm43602.conf

# Verify no remaining brcmfmac blacklist
grep -r 'blacklist brcmfmac' /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null
```

#### 3. Set `brcmfmac` to load at boot

```bash
echo 'brcmfmac' | sudo tee /etc/modules-load.d/brcmfmac.conf
```

#### 4. Add the kernel parameter to Limine

```bash
sudo nano /etc/default/limine
# Append to the KERNEL_CMDLINE[default] line:
#   KERNEL_CMDLINE[default]+=" brcmfmac.feature_disable=0x82000"
sudo limine-update
```

For **systemd-boot**, append `brcmfmac.feature_disable=0x82000` to the
`options` line in `/boot/loader/entries/*.conf`.

Verify after reboot: `cat /proc/cmdline`

#### 5. Rebuild initramfs and reboot

```bash
sudo depmod -a && sudo mkinitcpio -P
sudo reboot
```

#### 6. Verify

```bash
lsmod | grep brcmfmac          # driver loaded
iw dev                          # wireless interface present
nmcli device wifi list          # nearby networks
nmcli device wifi connect "SSID" password "…"
```

---

## Solution 2 — Regulatory domain (`wireless-regdb`) ✅

On a fresh install the regulatory domain may be unset (`00`), restricting
available channels and preventing association. **Combine with Solution 1.**

```bash
sudo pacman -S --needed iw wireless-regdb
iw reg get                      # check current (should not be "country 00:")
sudo iw reg set CN              # replace CN with your country code
```

### Make persistent

**Option A** — `/etc/conf.d/wireless-regdom`:

```bash
echo 'WIRELESS_REGDOM="CN"' | sudo tee /etc/conf.d/wireless-regdom
```

**Option B** — kernel parameter:

Add `cfg80211.ieee80211_regdom=CN` to the bootloader, then `sudo mkinitcpio -P`.

---

## Solution 4 — Enable `NetworkConfigurationEnabled` in iwd

If using `iwd` (Omarchy default) and seeing "Operation failed" after entering
the correct password, iwd may not be configured to handle DHCP.

```bash
sudo mkdir -p /etc/iwd
sudo tee /etc/iwd/main.conf <<'EOF'
[General]
EnableNetworkConfiguration=true
EOF
sudo systemctl restart iwd
```

Then retry: `iwctl station wlan0 connect "<SSID>"`

---

## Solution 5 — Reduce transmit power (diagnostic workaround)

If `brcmfmac` creates an interface but association still fails, reducing
`txpower` can confirm the hardware is functional. **Drops speed to ~25 Mbps.**

```bash
sudo iw dev wlan0 set txpower fixed 1000    # try 1000–1101 mBm
nmcli device wifi connect "SSID" password "…"
```

To persist (NetworkManager dispatcher):

```bash
sudo tee /etc/NetworkManager/dispatcher.d/99-txpower <<'EOF'
#!/bin/bash
[[ "$2" == "up" && "$1" == wlan* ]] && iw dev "$1" set txpower fixed 1000
EOF
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-txpower
```

---

## Solution 3 — Proprietary `wl` driver ❌

> **Do not use on kernel 6.19+.** The proprietary binary blob
> (`wlc_hybrid.o_shipped`) fails to initialize due to unpatched return thunks
> that violate Spectre mitigations. This is confirmed in Arch GitLab
> `broadcom-wl-dkms` [issue #3] and [issue #4] (filed 2026-03-13/14).
> Additionally, **no omarchy community member has ever reported `wl` working
> with `14e4:43ba`** — all success reports are for `14e4:43a0` (BCM4360).
>
> If already installed, switch to `brcmfmac`: `sudo ./switch-to-brcmfmac.sh`

[issue #3]: https://gitlab.archlinux.org/archlinux/packaging/packages/broadcom-wl-dkms/-/issues/3
[issue #4]: https://gitlab.archlinux.org/archlinux/packaging/packages/broadcom-wl-dkms/-/issues/4

The `wl` driver could theoretically work if:
- The kernel is downgraded to ~6.14 or earlier
- Broadcom releases a new blob (upstream is dead/unmaintained)
- The Arch package gains a return thunk workaround

---

## Solution 6 — Retry / wait with iwd ❌

Non-reproducible. Some users in [#4692] reported connection succeeding after
10+ retries over several minutes. Likely a race condition in iwd/firmware
initialization. Not a real solution.

---

## Investigation log

### `wl` driver failure (2026-03-15 / 2026-03-16)

After installing `broadcom-wl-dkms` (later `broadcom-wl`) on kernel
`6.19.6-arch1-1`, the `wl` module loaded but no Wi-Fi interface appeared.

**Package state:**
- `broadcom-wl 6.30.223.271-679` installed
- DKMS: `broadcom-wl/6.30.223.271, 6.19.6-arch1-1, x86_64: installed`
- `/usr/lib/modprobe.d/broadcom-wl.conf` blacklisted all open-source Broadcom drivers

**Kernel log** (`sudo journalctl -k -b --no-pager | grep -Ei 'wl|brcm|firmware'`):

```
wl: loading out-of-tree module taints kernel.
wl: module license 'MIXED/Proprietary' taints kernel.
You are using the broadcom-wl driver, which is not maintained and is
  incompatible with Linux kernel security mitigations.
 getvar+0x20/0x70 [wl]
 wl_module_init+0x23/0xb0 [wl]
wl driver 6.30.223.271 (r587334) failed with code 1
ERROR @wl_cfg80211_detach :
NULL ndev->ieee80211ptr, unable to deref wl
Bluetooth: hci0: BCM: firmware Patch file not found, tried: 'brcm/BCM.hcd'
```

**Root cause:** The proprietary blob aborts at `wl_module_init` → `getvar` due
to unpatched return thunks incompatible with kernel 6.19's Spectre mitigations.

**Matching reports:** Same `failed with code 1` / `NULL ndev->ieee80211ptr`
in [ublue-os/main#244], [patjak/facetimehd#135], [sebanc/brunch#878].

**Omarchy community:** No user with `14e4:43ba` ever reported `wl` working.
`@longsman`, `@spencern`, `@iamobservable` all failed or used `brcmfmac`.

[ublue-os/main#244]: https://github.com/ublue-os/main/issues/244
[patjak/facetimehd#135]: https://github.com/patjak/facetimehd/issues/135
[sebanc/brunch#878]: https://github.com/sebanc/brunch/issues/878

### `brcmfmac` boot persistence issue (2026-03-15)

After `brcmfmac` worked in-session, it was absent after reboot despite
`brcmfmac.feature_disable=0x82000` being in the kernel cmdline.

**Cause:** The `broadcom-wl` package's blacklist
(`/usr/lib/modprobe.d/broadcom-wl.conf`) prevented udev from auto-loading
`brcmfmac`. A local `install` override in `/etc/modprobe.d/allow-brcmfmac.conf`
only worked for explicit `modprobe` calls, not udev alias matching.
With no `/etc/modules-load.d/brcmfmac.conf`, the module was never invoked.

**Fix:** The `switch-to-brcmfmac.sh` script handles this by removing the
`broadcom-wl` package entirely and creating `/etc/modules-load.d/brcmfmac.conf`.

---

## References

| Resource | URL |
|----------|-----|
| Omarchy discussion #4692 — WiFi on MBP / Broadcom | https://github.com/basecamp/omarchy/discussions/4692 |
| Omarchy issue #4611 — BCM43602 confirmed fix | https://github.com/basecamp/omarchy/issues/4611 |
| Omarchy issue #1022 — 2016 MBP WiFi behavior | https://github.com/basecamp/omarchy/issues/1022 |
| Omarchy issue #1083 — wireless-regdb needed | https://github.com/basecamp/omarchy/issues/1083 |
| Omarchy PR #1143 — Fix Broadcom wifi on mid-2010s MacBooks | https://github.com/basecamp/omarchy/pull/1143 |
| Omarchy `fix-bcm43xx.sh` — installer (43ba not covered) | https://github.com/basecamp/omarchy/blob/dev/install/config/hardware/fix-bcm43xx.sh |
| ArchWiki — Broadcom wireless | https://wiki.archlinux.org/title/Broadcom_wireless |
| Arch GitLab — broadcom-wl-dkms #3 (VLA OOPS) | https://gitlab.archlinux.org/archlinux/packaging/packages/broadcom-wl-dkms/-/issues/3 |
| Arch GitLab — broadcom-wl-dkms #4 (return thunk) | https://gitlab.archlinux.org/archlinux/packaging/packages/broadcom-wl-dkms/-/issues/4 |
| ublue-os/main #244 — wl failed with code 1 | https://github.com/ublue-os/main/issues/244 |
| patjak/facetimehd #135 — facetimehd breaks wl | https://github.com/patjak/facetimehd/issues/135 |
| sebanc/brunch #878 — broadcom_wl broken | https://github.com/sebanc/brunch/issues/878 |
