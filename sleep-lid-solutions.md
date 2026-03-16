# Sleep / Lid-Close Solutions for MacBookPro14,2

- **Hardware:** MacBookPro14,2 (2017 13-inch, four Thunderbolt 3 ports, T1 chip)
- **Kernel:** 6.19.6-arch1-1 · **OS:** Omarchy / Arch Linux

## TL;DR

```bash
# 1 — logind: treat lid-close as 'sleep', not 'suspend'
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/lid-sleep.conf <<'EOF'
[Login]
HandleLidSwitch=sleep
HandleLidSwitchExternalPower=sleep
EOF

# 2 — sleep.conf: use s2idle memory sleep mode
sudo mkdir -p /etc/systemd/sleep.conf.d
sudo tee /etc/systemd/sleep.conf.d/s2idle.conf <<'EOF'
[Sleep]
MemorySleepMode=s2idle
SuspendState=freeze
EOF

# 3 — kernel cmdline: make s2idle the default (required; sleep.conf alone may not stick)
sudo nano /etc/default/limine
# Append to KERNEL_CMDLINE[default]+= line:
#   mem_sleep_default=s2idle
sudo limine-update

# 4 — NVMe d3cold fix (prevents drive from wedging on resume)
sudo tee /etc/systemd/system/omarchy-nvme-suspend-fix.service <<'EOF'
[Unit]
Description=Disable NVMe D3-cold to allow clean resume on MacBook

[Service]
ExecStart=/bin/bash -c 'echo 0 > /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed'

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now omarchy-nvme-suspend-fix.service

sudo reboot
# After reboot: close lid, wait ~5 s, open lid, press power button to wake.
```

---

## Background

By default, Omarchy / Arch Linux uses `mem_sleep_default=deep` (S3 suspend-to-RAM).
On the MacBookPro14,2 (and most Intel MacBooks without a T2 chip), deep S3 tends to:

- Prevent the machine from waking at all (blank screen, fan spin-up), or
- Wake with severe battery drain (the SoC does not fully enter low-power state), or
- Occasionally leave the NVMe drive in a wedged state, requiring a hard reset.

Switching to `s2idle` (suspend-to-idle / freeze) keeps the kernel in a shallow
freeze loop rather than powering the SoC off completely.  The laptop wakes reliably
on power-button press, battery drain during sleep is significantly reduced, and the
NVMe drive recovers cleanly.

> **Note on T1 vs T2:** MacBookPro14,2 has the Apple T1 security chip (not T2).
> The T2-specific services (`tiny-dfr`, `apple-bce`, `suspend-t2.service`) are **not**
> needed and should not be installed on this machine.

---

## Solution 1 — `s2idle` via logind + sleep.conf + kernel cmdline ✅

### Step 1 — Configure logind (lid-close → sleep)

Create a drop-in so lid-close triggers `sleep` instead of `suspend`:

```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/lid-sleep.conf <<'EOF'
[Login]
HandleLidSwitch=sleep
HandleLidSwitchExternalPower=sleep
EOF
```

### Step 2 — Configure sleep.conf (s2idle mode)

```bash
sudo mkdir -p /etc/systemd/sleep.conf.d
sudo tee /etc/systemd/sleep.conf.d/s2idle.conf <<'EOF'
[Sleep]
MemorySleepMode=s2idle
SuspendState=freeze
EOF
```

### Step 3 — Set kernel parameter (required)

Even with `sleep.conf` set, the kernel may keep `deep` selected until the boot
parameter is added.  Verify after reboot with `cat /sys/power/mem_sleep` — the
active mode appears in brackets.  If it still shows `[deep]`, the parameter is not
taking effect.

Edit `/etc/default/limine` and append `mem_sleep_default=s2idle` to the
`KERNEL_CMDLINE[default]+=` line:

```
KERNEL_CMDLINE[default]+=" ... mem_sleep_default=s2idle"
```

Then rebuild the boot entry:

```bash
sudo limine-update
```

### Step 4 — Verify

```bash
# After reboot:
cat /sys/power/mem_sleep          # should show [s2idle] (not [deep])
systemctl status sleep.target     # observe after closing/opening lid
```

---

## Solution 2 — NVMe D3-cold fix ✅

Even with `s2idle`, the NVMe controller may fail to resume if it entered D3-cold
during sleep.  The Omarchy installer handles this via `fix-apple-suspend-nvme.sh`
for all MacBookPro14,x models, but the fix can be applied manually:

```bash
sudo tee /etc/systemd/system/omarchy-nvme-suspend-fix.service <<'EOF'
[Unit]
Description=Disable NVMe D3-cold to allow clean resume on MacBook

[Service]
ExecStart=/bin/bash -c 'echo 0 > /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now omarchy-nvme-suspend-fix.service
```

> **Note:** The PCI address `0000:01:00.0` is the standard NVMe location on this
> MacBook.  Confirm with `lspci | grep -i nvme`.

---

## References

| Resource | URL |
|----------|-----|
| Omarchy issue #1840 — lid/sleep/suspend on MacBook | https://github.com/basecamp/omarchy/issues/1840 |
| Omarchy `fix-apple-suspend-nvme.sh` | https://github.com/basecamp/omarchy/blob/dev/install/config/hardware/fix-apple-suspend-nvme.sh |
| ArchWiki — Power management/Suspend and hibernate | https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate |
| T2Linux.org — Suspend workaround (T2 only, not needed here) | https://wiki.t2linux.org/guides/postinstall/#suspend-workaround |
