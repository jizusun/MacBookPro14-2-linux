# Lid Close / Sleep / Battery Drain — MacBookPro14,2

This document covers two related problems on this `MacBookPro14,2` running
Omarchy:

1. Closing the lid leaves the machine unable to wake up.
2. The machine drains battery excessively while the lid is closed.

Both problems have the same root cause: Omarchy defaults to the `deep`
suspend mode, which does not work reliably on this 2017 MacBook hardware.

---

## Background

Omarchy (and Arch Linux) trigger the `suspend` action when the lid closes.
The default suspend mode on this hardware is `deep` (S3 sleep), which can
cause:

- the machine to not wake on lid-open — requiring a forced power-off
- fans spinning and high battery drain while "suspended"

The fix is to switch to `s2idle` (also known as S0ix / "freeze" / "modern
standby"), which is the sleep mode Apple hardware uses on Intel MacBooks.

This was confirmed to work on Intel MacBooks without T1/T2 chip in omarchy
issue [#1840](https://github.com/basecamp/omarchy/issues/1840) (where a 2017
MacBook user reported success with the three-file change below).

---

## Problem checklist

Before applying fixes, confirm the current state:

```bash
# Which sleep mode is currently selected?
cat /sys/power/mem_sleep
# If output is "s2idle [deep]", the machine is using deep — change it

# Does the lid action trigger anything?
systemd-analyze blame | head -20

# Check current logind lid behavior
grep -E 'HandleLid' /etc/systemd/logind.conf
```

---

## Fix 1 — Switch to `s2idle` (required)

This is the core fix. It involves three config files and a bootloader
update.

### 1a. Edit `/etc/systemd/logind.conf`

Add or uncomment these two lines:

```
HandleLidSwitch=sleep
HandleLidSwitchExternalPower=sleep
```

```bash
sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=sleep/' /etc/systemd/logind.conf
sudo sed -i 's/^#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=sleep/' /etc/systemd/logind.conf
# If the lines are absent, append them:
grep -q '^HandleLidSwitch=' /etc/systemd/logind.conf \
  || echo 'HandleLidSwitch=sleep' | sudo tee -a /etc/systemd/logind.conf
grep -q '^HandleLidSwitchExternalPower=' /etc/systemd/logind.conf \
  || echo 'HandleLidSwitchExternalPower=sleep' | sudo tee -a /etc/systemd/logind.conf
```

### 1b. Edit `/etc/systemd/sleep.conf`

Add these two lines (or a drop-in at `/etc/systemd/sleep.conf.d/s2idle.conf`):

```
SuspendState=freeze
MemorySleepMode=s2idle
```

```bash
sudo mkdir -p /etc/systemd/sleep.conf.d
sudo tee /etc/systemd/sleep.conf.d/s2idle.conf <<'EOF'
[Sleep]
SuspendState=freeze
MemorySleepMode=s2idle
EOF
```

> **Note:** On some machines the `sleep.conf` change alone is not enough
> because the kernel parameter takes precedence. Always apply Fix 1c as
> well.

### 1c. Add `mem_sleep_default=s2idle` to the Limine bootloader

Edit `/etc/default/limine` and append the parameter using `+=` (not `=`,
which would overwrite any drop-in config):

```bash
sudo nano /etc/default/limine
# Find or add a line like:
# KERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle"
```

Example of the relevant part of that file after the edit:

```
KERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle"
```

Then regenerate the Limine config:

```bash
sudo limine-update
```

Reboot and verify:

```bash
sudo reboot
```

After reboot:

```bash
cat /sys/power/mem_sleep
# Expected: [s2idle] deep   (s2idle in brackets = selected)
```

---

## Fix 2 — NVMe suspend fix (Omarchy built-in for MacBookPro14,x)

Omarchy's own `fix-apple-suspend-nvme.sh` installer script explicitly
supports `MacBookPro14,[123]` models. It creates a systemd service that
writes `0` to the NVMe device's `d3cold_allowed` sysfs attribute at boot,
which prevents the NVMe from entering a D3 cold state that can prevent
clean resume.

Check whether the service is present on this machine:

```bash
systemctl status omarchy-nvme-suspend-fix.service
# If it does not exist, create it manually (see below)
```

If it is missing (e.g. the installer ran before this fix was added to
omarchy), create it manually:

```bash
sudo tee /etc/systemd/system/omarchy-nvme-suspend-fix.service <<'EOF'
[Unit]
Description=Omarchy NVMe Suspend Fix for MacBook

[Service]
ExecStart=/bin/bash -c 'echo 0 > /sys/bus/pci/devices/0000\:01\:00.0/d3cold_allowed'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now omarchy-nvme-suspend-fix.service
```

Verify it ran at boot:

```bash
systemctl status omarchy-nvme-suspend-fix.service
cat /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed
# Expected: 0
```

> **Note:** `0000:01:00.0` is the expected NVMe PCI address on this machine.
> Confirm with `lspci | grep -i nvme` if needed.

---

## Fix 3 — USB autosuspend (prevents USB device loss on resume)

USB autosuspend can cause USB devices (including USB Ethernet adapters) to
not come back correctly after suspend. Omarchy disables it by default via
`/etc/modprobe.d/disable-usb-autosuspend.conf`, but verify it is present:

```bash
cat /etc/modprobe.d/disable-usb-autosuspend.conf
# Expected: options usbcore autosuspend=-1
```

If the file is missing:

```bash
echo "options usbcore autosuspend=-1" \
  | sudo tee /etc/modprobe.d/disable-usb-autosuspend.conf
sudo mkinitcpio -P
```

---

## Verification after all fixes

Close the lid and leave it for a few minutes, then open and press the power
button to resume.

After a successful resume, check:

```bash
# Confirm s2idle was used
journalctl -b -1 | grep -Ei 'suspend|s2idle|sleep'

# Check the battery did not drain excessively while sleeping
upower -i $(upower -e | grep battery)
# or:
cat /sys/class/power_supply/BAT0/status

# Confirm NVMe is still accessible
ls /sys/bus/pci/devices/0000:01:00.0/
```

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| Machine won't wake (black screen) | `deep` sleep still active | Verify `/sys/power/mem_sleep` shows `[s2idle]` |
| `cat /sys/power/mem_sleep` shows `s2idle [deep]` after reboot | Kernel cmdline not updated | Re-run `sudo limine-update` and reboot |
| Machine wakes but NVMe errors | NVMe d3cold_allowed not fixed | Check `omarchy-nvme-suspend-fix.service` is enabled |
| USB Ethernet adapter offline after resume | USB autosuspend re-enabled or hotplug issue | See [`usb-adapter-hotplug.md`](./usb-adapter-hotplug.md) |
| Very high battery drain while sleeping | Still using `deep` mode | Confirm s2idle is selected and reboot |

---

## References

| Resource | URL |
|----------|-----|
| Omarchy issue #1840 — lid/sleep/suspend on MacBook | https://github.com/basecamp/omarchy/issues/1840 |
| Omarchy `fix-apple-suspend-nvme.sh` — NVMe suspend fix | https://github.com/basecamp/omarchy/blob/master/install/config/hardware/fix-apple-suspend-nvme.sh |
| Omarchy `usb-autosuspend.sh` — USB autosuspend disable | https://github.com/basecamp/omarchy/blob/master/install/config/hardware/usb-autosuspend.sh |
| ArchWiki — Power management / Suspend and hibernate | https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate |
| ArchWiki — Power management / Suspend and hibernate — Changing suspend method | https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate#Changing_suspend_method |
