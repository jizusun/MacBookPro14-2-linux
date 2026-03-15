# Wireless Solutions for BCM43602 (`14e4:43ba`)

This document lists every reported fix for the **Broadcom BCM43602
802.11ac Wireless LAN SoC** (`14e4:43ba`) on Omarchy / Arch Linux, drawn
from:

- the omarchy community discussion
  [#4692](https://github.com/basecamp/omarchy/discussions/4692)
- omarchy issues
  [#1022](https://github.com/basecamp/omarchy/issues/1022),
  [#1083](https://github.com/basecamp/omarchy/issues/1083), and
  [#4611](https://github.com/basecamp/omarchy/issues/4611)
- omarchy draft PR
  [#1143](https://github.com/basecamp/omarchy/pull/1143)
- the ArchWiki **Broadcom wireless** page
- the investigation in this repo (`broadcom-wl-investigation.md`)

> **Omarchy installer gap:** Omarchy's built-in hardware script
> (`install/config/hardware/fix-bcm43xx.sh`) only installs `broadcom-wl`
> automatically for `14e4:43a0` (BCM4360) and `14e4:4331` (BCM4331).
> The `14e4:43ba` (BCM43602, present in 2016–2017 MacBook Pros) is **not**
> handled by the installer and requires manual steps from this document.

Each solution is scored on three factors and is followed by step-by-step
instructions.

---

## Quick comparison

| # | Solution | Difficulty | Reversibility | Reported success rate for `14e4:43ba` | Recommended? |
|---|----------|-----------|---------------|---------------------------------------|--------------|
| 1 | `brcmfmac` + kernel parameter `brcmfmac.feature_disable=0x82000` | Low | High | **High** — confirmed fix on BCM43602 (issue #4611, discussion #4692) | ✅ Try first |
| 2 | `wireless-regdb` + `iw reg set <COUNTRY>` | Low | High | High (several reports of immediate fix) | ✅ Try second |
| 3 | `broadcom-wl[-dkms]` + blacklist + NetworkManager | Medium | Medium | Moderate (works after reboot; `wl` can still fail on some kernels) | ✅ Try third |
| 4 | Enable `NetworkConfigurationEnabled` in iwd | Low | High | High (fixes "Operation failed" when iwd is missing this setting) | ✅ Try if using iwd |
| 5 | Reduce `txpower` with `iw` | Low | High | High (connection works, but at reduced speed) | ⚠️ Workaround only |
| 6 | Retry / wait with `iwd` | None | N/A | Low (rare, non-reproducible) | ❌ Unreliable |

---

## Solution 1 — `brcmfmac` kernel parameter (`brcmfmac.feature_disable=0x82000`)

### What it does

The `brcmfmac` driver (open-source, in-kernel) has a feature flag that
disables power-saving and band-steering features which can cause
`14e4:43a0` and `14e4:43ba` cards to fail association. Setting the flag
via a kernel parameter keeps the driver in the simplest operating mode.

This was **confirmed to fix `14e4:43ba` (BCM43602)** in omarchy issue
[#4611](https://github.com/basecamp/omarchy/issues/4611) (MacBookPro11,5)
and in discussion [#4692](https://github.com/basecamp/omarchy/discussions/4692).

### Weight

- **Pro:** No proprietary driver required; fully reversible; no speed loss;
  confirmed working on BCM43602.
- **Con:** The `broadcom-wl` blacklist that this repo uses must be removed
  or the `brcmfmac` module will be blocked.
- **Verdict:** The highest-confidence open-source fix for this chip.

### Steps

#### 1. Confirm the hardware

```bash
lspci -vnn -d 14e4:
```

Expected output includes:

```
BCM43602 802.11ac Wireless LAN SoC [14e4:43ba]
```

#### 2. Remove any `broadcom-wl` blacklist that blocks `brcmfmac`

If this repo's blacklist file is present, it will prevent `brcmfmac` from
loading:

```bash
# Check whether the blacklist exists
ls /etc/modprobe.d/broadcom-wl-bcm43602.conf
# If it exists, move it aside instead of deleting it
sudo mv /etc/modprobe.d/broadcom-wl-bcm43602.conf \
        /etc/modprobe.d/broadcom-wl-bcm43602.conf.disabled
```

Also check whether the `broadcom-wl` package ships its own blacklist:

```bash
cat /usr/lib/modprobe.d/broadcom-wl.conf
```

If `brcmfmac` is listed there, you will need to either uninstall
`broadcom-wl` / `broadcom-wl-dkms` or override the package blacklist with
an entry in `/etc/modprobe.d/`:

```bash
# Override: allow brcmfmac even when broadcom-wl.conf is present
echo 'install brcmfmac /sbin/modprobe --ignore-install brcmfmac' \
  | sudo tee /etc/modprobe.d/allow-brcmfmac.conf
```

#### 3. Add the kernel parameter to the bootloader

Omarchy uses the **Limine** bootloader by default.

**Limine (Omarchy default) — confirmed method from issue #4611:**

Edit `/etc/default/limine` and append to the `KERNEL_CMDLINE` line:

```bash
sudo nano /etc/default/limine
# Add or append to the KERNEL_CMDLINE[default] line:
# KERNEL_CMDLINE[default]+=" brcmfmac.feature_disable=0x82000"
```

Then regenerate the Limine config:

```bash
sudo limine-update
```

Alternatively, edit the running Limine config directly at
`/boot/limine/limine.conf` (or wherever your Limine config is) and add the
parameter to the `CMDLINE` value for your boot entry. See the
[Limine config reference](https://github.com/limine-bootloader/limine/blob/v9.x/CONFIG.md)
for the exact syntax.

To confirm the parameter was applied after reboot:

```bash
cat /proc/cmdline
```

**systemd-boot** (if used instead of Limine):

Open `/boot/loader/entries/*.conf` and append `brcmfmac.feature_disable=0x82000`
to the `options` line:

```
options root=... rw quiet brcmfmac.feature_disable=0x82000
```

#### 4. Rebuild the initramfs

```bash
sudo mkinitcpio -P
```

This is required so that the updated module and parameter configuration is
baked into the initramfs used at early boot.

#### 5. Reboot and verify

```bash
sudo reboot
```

After reboot:

```bash
# Check that brcmfmac is loaded and a wireless interface exists
lsmod | grep brcmfmac
iw dev
# Try connecting
iwctl station wlan0 scan
iwctl station wlan0 connect "<SSID>"
```

If `iw dev` shows an interface but connection still fails, move on to
Solution 2 (wireless-regdb) or try NetworkManager (Solution 3).

---

## Solution 2 — `wireless-regdb` + regulatory domain (`iw reg set`)

### What it does

The `brcmfmac` driver reads the wireless regulatory database to determine
which channels and power levels are allowed. On a fresh Omarchy/Arch
install the regulatory domain may be unset (`UNSET` or `00`), which causes
the driver to fall back to a very conservative channel set that can prevent
association entirely. Installing `wireless-regdb` and setting the correct
regulatory domain fixes this.

This was reported in omarchy issue
[#1083](https://github.com/basecamp/omarchy/issues/1083) and confirmed by
multiple users in discussion #4692 as a direct, no-side-effect fix.

### Weight

- **Pro:** The cleanest and most upstream-compatible fix; no proprietary
  driver or blacklisting needed; immediate effect without reboot.
- **Con:** Does not persist automatically on its own after reboot (set it
  permanently via a `systemd` unit or `/etc/conf.d/wireless-regdom`).
- **Verdict:** The highest-confidence, lowest-risk fix to try once
  `brcmfmac` is loaded.

### Steps

#### 1. Install `iw` and `wireless-regdb`

```bash
sudo pacman -S --needed iw wireless-regdb
```

#### 2. Check the current regulatory domain

```bash
iw reg get
```

If the output shows `country 00:` or `country UNSET:`, the domain is not
set.

#### 3. Set the regulatory domain to your country

Replace `US` with your two-letter country code (e.g. `DE`, `GB`, `JP`):

```bash
sudo iw reg set US
```

#### 4. Verify and try connecting

```bash
iw reg get
# Should now show your country
iwctl station wlan0 scan
iwctl station wlan0 connect "<SSID>"
```

#### 5. Make the setting persistent

**Option A — `/etc/conf.d/wireless-regdom`** (recommended):

```bash
# Uncomment or add the line for your country
sudo sed -i 's/^#WIRELESS_REGDOM="US"/WIRELESS_REGDOM="US"/' \
  /etc/conf.d/wireless-regdom
# If the file does not exist:
echo 'WIRELESS_REGDOM="US"' | sudo tee /etc/conf.d/wireless-regdom
```

**Option B — kernel parameter**:

Add `cfg80211.ieee80211_regdom=US` (replace `US`) to the bootloader entry
alongside any other kernel options, then rebuild initramfs:

```bash
sudo mkinitcpio -P
```

---

## Solution 3 — Proprietary `wl` driver + blacklist + NetworkManager

### What it does

The proprietary Broadcom STA driver (`broadcom-wl` / `broadcom-wl-dkms`)
supports `14e4:43ba` and is the approach used by Omarchy's own
`fix-bcm43xx.sh` installer script. It requires:

1. Blacklisting all competing open-source drivers so `wl` has exclusive
   access to the hardware.
2. Using **NetworkManager + wpa\_supplicant** instead of `iwd` because `iwd`
   has known unreliable behavior with some Broadcom cards.

This is the approach documented in `broadcom-wl-investigation.md` and
supported by the `repair-broadcom-wl.sh` helper in this repo.

### Weight

- **Pro:** The approach Omarchy officially uses; `wl` is the only driver
  that fully supports some Broadcom features.
- **Con:** The proprietary `wl` module can fail to initialize on newer
  kernels with the error `wl driver ... failed with code 1` / `NULL
  ndev->ieee80211ptr` (confirmed on kernel `6.19.6-arch1-1`); it is not
  open-source; DKMS rebuild is needed after every kernel update.
- **Verdict:** Best long-term path if the kernel version is compatible;
  currently blocked on this machine by a kernel initialization failure.

### Steps

#### 1. Run the repo helper (combines steps 2–5)

```bash
sudo ./repair-broadcom-wl.sh
```

This script removes `broadcom-wl-dkms`, installs `broadcom-wl`, writes the
BCM43602 blacklist file, runs `depmod -a`, rebuilds initramfs, and attempts
a live `wl` reload. Skip to step 6 if you use it.

#### 2. Remove `broadcom-wl-dkms` if present

```bash
sudo pacman -R --noconfirm broadcom-wl-dkms 2>/dev/null || true
```

#### 3. Install `broadcom-wl`, DKMS support, and kernel headers

```bash
sudo pacman -S --needed broadcom-wl dkms linux-headers
```

#### 4. Write the competing-driver blacklist

Create `/etc/modprobe.d/broadcom-wl-bcm43602.conf`:

```
# Prefer the proprietary wl driver for BCM43602 on this MacBook.
blacklist b43
blacklist b43legacy
blacklist bcm43xx
blacklist bcma
blacklist brcm80211
blacklist brcmfmac
blacklist brcmsmac
blacklist ssb
```

```bash
sudo tee /etc/modprobe.d/broadcom-wl-bcm43602.conf <<'EOF'
# Prefer the proprietary wl driver for BCM43602 on this MacBook.
blacklist b43
blacklist b43legacy
blacklist bcm43xx
blacklist bcma
blacklist brcm80211
blacklist brcmfmac
blacklist brcmsmac
blacklist ssb
EOF
```

#### 5. Rebuild initramfs

```bash
sudo depmod -a
sudo mkinitcpio -P
```

#### 6. Switch from `iwd` to NetworkManager + wpa\_supplicant

`iwd` is Omarchy's default, but multiple users confirmed better Broadcom
behavior with NetworkManager:

```bash
sudo pacman -S --needed networkmanager
sudo systemctl disable --now iwd
sudo systemctl enable --now NetworkManager.service
```

Verify:

```bash
nmcli device status
```

#### 7. Reboot and verify

```bash
sudo reboot
```

After reboot:

```bash
# Find the PCI address of the Broadcom adapter first
lspci -k | grep -A3 BCM43602
# Use the address shown (e.g. 02:00.0) in the next command
lspci -k -s <PCI_ADDRESS e.g. 02:00.0>  # should show "Kernel driver in use: wl"
iw dev                          # should show an interface
nmcli device wifi list
nmcli device wifi connect "<SSID>" password "<PASSWORD>"
```

If `lspci -k` still does not show `Kernel driver in use: wl` and `iw dev`
is empty, capture the kernel log for the current boot:

```bash
sudo journalctl -k -b --no-pager | grep -Ei 'wl|brcm|cfg80211|firmware'
```

The presence of `wl driver ... failed with code 1` means the kernel version
is incompatible with the current `wl` binary. In that case fall back to
Solution 1 or Solution 2 (open-source `brcmfmac` path).

---

## Solution 4 — Enable `NetworkConfigurationEnabled` in `iwd`

### What it does

Omarchy uses `iwd` as its default Wi-Fi backend. On a fresh install `iwd`
may have `NetworkConfigurationEnabled` disabled, which prevents it from
assigning an IP address after association — causing "Operation failed" or a
perpetual "disconnected" status even when the driver and interface are
working correctly.

This was reported in issue
[#1022](https://github.com/basecamp/omarchy/issues/1022) and
[#1806](https://github.com/basecamp/omarchy/issues/1806) and in discussion
[#4692](https://github.com/basecamp/omarchy/discussions/4692).

### Weight

- **Pro:** Simple one-line config change; no package installs or reboots
  needed; fully reversible.
- **Con:** Only relevant when `iwd` is the active network backend; does not
  help if the driver itself is not creating an interface.
- **Verdict:** Check this before troubleshooting the driver. If `iwctl`
  shows `NetworkConfigurationEnabled: disabled` at startup, fix this first.

### Steps

#### 1. Check the current iwd status

```bash
iwctl
```

If the prompt shows `NetworkConfigurationEnabled: disabled`, this fix
applies.

#### 2. Create or edit `/etc/iwd/main.conf`

```bash
sudo mkdir -p /etc/iwd
sudo tee /etc/iwd/main.conf <<'EOF'
[General]
EnableNetworkConfiguration=true
EOF
```

#### 3. Restart iwd

```bash
sudo systemctl restart iwd
```

#### 4. Verify and connect

```bash
iwctl
# Inside iwctl:
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "<SSID>"
```

---

## Solution 5 — Reduce transmit power (`txpower`)

### What it does

The BCM43602 defaults to a high transmit power (around 31 dBm /
`3100` in `iw` units). Some users found that reducing it below approximately
11 dBm (`1101` in `iw` units) allowed the card to associate successfully.
This is a workaround, not a root-cause fix, and it reduces throughput
substantially.

### Weight

- **Pro:** Takes effect immediately with no reboot; easily reversible.
- **Con:** Reduces throughput to roughly 25–30 Mbps on a gigabit connection
  (vs 400+ Mbps); the setting does not persist across reboots without
  automation; does not explain or fix the underlying driver problem.
- **Verdict:** Use only as a temporary workaround to confirm the hardware
  is otherwise functional while you pursue Solutions 1–3.

### Steps

#### 1. Confirm an interface is visible

```bash
iw dev
```

This solution requires `brcmfmac` to already have created an interface (e.g.
`wlan0`). If `iw dev` is empty, solve the interface issue first (Solutions
1–3).

#### 2. Reduce transmit power

```bash
sudo iw dev wlan0 set txpower fixed 1000
```

Try values between `1000` and `1101` (mBm units). Values of `1200` and
above have been reported to still fail.

#### 3. Try connecting

```bash
iwctl station wlan0 connect "<SSID>"
# or with NetworkManager:
nmcli device wifi connect "<SSID>" password "<PASSWORD>"
```

#### 4. Persist across reboots (optional)

Create a NetworkManager dispatcher script or a `systemd` unit that reapplies
the setting after the interface comes up. For example:

```bash
sudo tee /etc/NetworkManager/dispatcher.d/99-txpower <<'EOF'
#!/bin/bash
IFACE="$1"
STATUS="$2"
if [[ "$STATUS" == "up" && "$IFACE" == wlan* ]]; then
  iw dev "$IFACE" set txpower fixed 1000
fi
EOF
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-txpower
```

---

## Solution 6 — Wait and retry with `iwd`

### What it does

Several users in discussion #4692 reported that after entering the correct
password and seeing "Operation failed" multiple times, the connection
eventually succeeded on a later attempt — sometimes after a few minutes,
without changing anything.

### Weight

- **Pro:** No changes required.
- **Con:** Non-reproducible; cannot be relied on; likely a race condition in
  `iwd` or firmware initialization; does not address the root cause.
- **Verdict:** Not a real solution. Document here only for completeness. Do
  not spend more than a few minutes on this approach before moving to
  Solutions 1–5.

### Steps

1. At the Omarchy installer or `iwctl` prompt, scan and attempt to connect:

   ```bash
   iwctl station wlan0 scan
   iwctl station wlan0 connect "<SSID>"
   ```

2. If it fails, wait 60–120 seconds and retry up to 5 times.
3. If still failing, proceed to Solutions 1–5.

---

## Recommended approach for this machine

Given the evidence collected in `broadcom-wl-investigation.md` (kernel
`6.19.6-arch1-1`, `wl driver ... failed with code 1`):

1. **Check iwd config first** (Solution 4) — run `iwctl` and confirm
   `NetworkConfigurationEnabled: enabled` is shown. If not, add
   `/etc/iwd/main.conf` with `EnableNetworkConfiguration=true`.
2. **Try Solution 1** (`brcmfmac.feature_disable=0x82000` in Limine) —
   disable the `broadcom-wl` blacklist first, then add the parameter to
   `/etc/default/limine` and run `sudo limine-update`. This is the
   confirmed fix for BCM43602 on Omarchy (issue #4611).
3. **Combine with Solution 2** (`wireless-regdb` + `iw reg set`) —
   install `wireless-regdb` and set the regulatory domain. This ensures
   the card sees all allowed channels.
4. **If `brcmfmac` creates an interface but association still fails**,
   combine with Solution 5 (reduce txpower) to confirm the hardware is
   functional.
5. **Try Solution 3** (`broadcom-wl` + NetworkManager) only when the above
   open-source paths are exhausted or when a compatible kernel version is
   confirmed. The current kernel (`6.19.6-arch1-1`) shows `wl`
   initialization failures, so this path is currently blocked.

---

## References

| Resource | URL |
|----------|-----|
| Omarchy discussion #4692 — WiFi issues on MBP / Broadcom | https://github.com/basecamp/omarchy/discussions/4692 |
| Omarchy issue #1022 — 2016 MBP bizarre WiFi behavior | https://github.com/basecamp/omarchy/issues/1022 |
| Omarchy issue #1083 — wireless-regdb needed for 6GHz | https://github.com/basecamp/omarchy/issues/1083 |
| Omarchy issue #1806 — MacBook Pro 2020 WiFi (T2/BRCM4377) | https://github.com/basecamp/omarchy/issues/1806 |
| Omarchy issue #4611 — Cannot connect on MacBookPro11,5 (BCM43602 confirmed fix) | https://github.com/basecamp/omarchy/issues/4611 |
| Omarchy PR #1143 — DRAFT: Fix Broadcom wifi on mid-2010s MacBooks | https://github.com/basecamp/omarchy/pull/1143 |
| Omarchy `fix-bcm43xx.sh` — installer script (BCM43602 not yet covered) | https://github.com/basecamp/omarchy/blob/dev/install/config/hardware/fix-bcm43xx.sh |
| ArchWiki — Broadcom wireless | https://wiki.archlinux.org/title/Broadcom_wireless |
| ublue-os/main #244 — BCM43602 wl failed with code 1 | https://github.com/ublue-os/main/issues/244 |
| This repo investigation | broadcom-wl-investigation.md |
