# USB Tethered Adapter Not Re-Recognized After Unplug/Replug

This document covers the problem where the USB/Thunderbolt Ethernet
adapter (`enp6s0u2`) is not automatically re-recognized by Omarchy after
being unplugged and replugged.

---

## Background

This machine has no working internal Wi-Fi (the BCM43602 is still under
investigation — see [`wireless-solutions.md`](./wireless-solutions.md)).
The primary network connection is a USB/Thunderbolt Ethernet adapter that
appears as `enp6s0u2`.

When the adapter is unplugged and replugged, the new interface is either
not picked up by the network stack or the existing NetworkManager/iwd
connection profile is not reapplied, leaving the machine without network
access until a manual reconnection step or a reboot.

The root causes are:

1. **USB autosuspend** may power down the adapter before it is fully
   re-registered by the kernel, causing the interface to not come back.
2. **No persistent NetworkManager connection profile** for the adapter, so
   there is nothing to automatically activate when the interface reappears.
3. **Interface name instability** — each replug can assign a new predictable
   name (or the same name but with no active connection) depending on udev
   state.

---

## Diagnosis

Check the current state of the adapter and its connection:

```bash
# What interfaces exist right now?
ip link show

# Is the adapter visible to NetworkManager?
nmcli device status
# If 'nmcli' is not found, NetworkManager is not installed; see Fix 3 below.

# Which connection profiles exist?
nmcli connection show

# Is USB autosuspend disabled?
cat /etc/modprobe.d/disable-usb-autosuspend.conf
# Expected: options usbcore autosuspend=-1
# If this file is missing, apply Fix 1 first.

# What does the kernel say about the adapter right now?
ip link show enp6s0u2
# If this fails, the interface is not present after replug.

# Check kernel events after replug
journalctl -k -n 50 | grep -Ei 'enp6s0u2|usb|eth'
```

---

## Fix 1 — Disable USB autosuspend

USB autosuspend can cause the kernel to power down a USB device that has
been idle for a short time. When the device wakes back up, or when the same
device is replugged, the USB stack sometimes does not re-register it
cleanly.

Omarchy provides a hardware script (`usb-autosuspend.sh`) that disables USB
autosuspend globally:

```bash
# Check if already applied
cat /etc/modprobe.d/disable-usb-autosuspend.conf

# If the file is missing, create it:
echo "options usbcore autosuspend=-1" \
  | sudo tee /etc/modprobe.d/disable-usb-autosuspend.conf

# Rebuild initramfs so the setting is applied at early boot:
sudo mkinitcpio -P
```

Reboot and then test by unplugging and replugging the adapter. Check
whether the interface comes back:

```bash
ip link show
nmcli device status
```

This is the highest-confidence, lowest-risk fix and should be tried first.

---

## Fix 2 — Create a persistent NetworkManager connection profile

If NetworkManager is managing the machine's Ethernet interfaces (which it
should on Omarchy if installed alongside iwd), a persistent connection
profile ensures the adapter is automatically brought up whenever the
interface reappears.

### 2a. Confirm NetworkManager is running

```bash
systemctl status NetworkManager
```

If it is not running:

```bash
sudo pacman -S --needed networkmanager
sudo systemctl enable --now NetworkManager.service
```

> **Note:** Omarchy's default network backend for Wi-Fi is `iwd`, but
> NetworkManager can run alongside it and manage wired/USB interfaces.
> Check `/etc/NetworkManager/conf.d/` to confirm `iwd` is set as the Wi-Fi
> backend if both are installed:
>
> ```
> [device]
> wifi.backend=iwd
> ```

### 2b. Create a connection profile for the USB Ethernet adapter

Use the interface name (`enp6s0u2`) to create a profile that will
auto-connect whenever the interface is present:

```bash
# Create an auto-connect profile for the USB adapter
sudo nmcli connection add \
  type ethernet \
  ifname enp6s0u2 \
  con-name "usb-ethernet" \
  connection.autoconnect yes \
  ipv4.method auto \
  ipv6.method auto
```

Verify it was created:

```bash
nmcli connection show usb-ethernet
```

After creating the profile, test by unplugging and replugging the adapter:

```bash
# After replug, check whether the connection activates automatically
watch -n1 nmcli device status
```

### 2c. If the interface name changes after replug

USB Ethernet adapters can sometimes be assigned a different interface name
after replug if udev assigns a new suffix (e.g. `enp6s0u2c4i2`).

To make the interface name stable regardless of the USB port used, create a
udev rule that assigns a permanent name based on the adapter's MAC address
or USB path:

```bash
# Find the current MAC address of the adapter
ip link show enp6s0u2 | awk '/link\/ether/ {print $2}'
```

Example udev rule (replace `XX:XX:XX:XX:XX:XX` with the actual MAC):

```bash
sudo tee /etc/udev/rules.d/70-usb-ethernet.rules <<'EOF'
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="XX:XX:XX:XX:XX:XX", NAME="usb-eth0"
EOF

sudo udevadm control --reload-rules
```

Then update the NetworkManager profile to use the new stable name:

```bash
sudo nmcli connection modify usb-ethernet connection.interface-name usb-eth0
```

---

## Fix 3 — iwd-only setup: ensure systemd-networkd manages Ethernet

If the machine is using `iwd` only (without NetworkManager), wired and USB
Ethernet interfaces are managed by `systemd-networkd`. Verify it is running:

```bash
systemctl status systemd-networkd
```

If it is not running:

```bash
sudo systemctl enable --now systemd-networkd
```

Create a network file for the USB adapter so systemd-networkd brings it up
on each hotplug:

```bash
sudo tee /etc/systemd/network/20-usb-ethernet.network <<'EOF'
[Match]
Name=enp6s0u2*

[Network]
DHCP=yes
EOF

sudo systemctl restart systemd-networkd
```

The `enp6s0u2*` wildcard matches even if the suffix changes after replug.

Verify:

```bash
networkctl status
networkctl status enp6s0u2
```

---

## Fix 4 — udev rule to trigger reconnect on replug

As a belt-and-suspenders measure, add a udev rule that asks NetworkManager
(or systemd-networkd) to bring up the interface whenever the USB device
is added:

```bash
sudo tee /etc/udev/rules.d/72-usb-ethernet-up.rules <<'EOF'
SUBSYSTEM=="net", ACTION=="add", DEVPATH=="*/usb*", \
  RUN+="/usr/bin/nmcli device connect $name"
EOF

sudo udevadm control --reload-rules
```

> **Note:** Replace the `nmcli device connect` line with
> `networkctl up $name` if using `systemd-networkd` instead of
> NetworkManager.

---

## Verification

After applying the fixes:

1. Unplug the adapter and wait 5 seconds.
2. Replug the adapter.
3. Within ~10 seconds the interface should reappear and obtain an address:

```bash
# Check the interface came back
ip link show
ip addr show

# Check connectivity
ping -c 3 1.1.1.1
```

If the interface does not appear:

```bash
# Check kernel messages for USB errors
journalctl -k --since "1 min ago" | grep -Ei 'usb|enp|eth'
# Check USB autosuspend is still off
cat /sys/module/usbcore/parameters/autosuspend
# Expected: -1
```

---

## References

| Resource | URL |
|----------|-----|
| Omarchy `usb-autosuspend.sh` — USB autosuspend disable | https://github.com/basecamp/omarchy/blob/master/install/config/hardware/usb-autosuspend.sh |
| Omarchy `network.sh` — iwd setup | https://github.com/basecamp/omarchy/blob/master/install/config/hardware/network.sh |
| ArchWiki — NetworkManager | https://wiki.archlinux.org/title/NetworkManager |
| ArchWiki — systemd-networkd | https://wiki.archlinux.org/title/Systemd-networkd |
| ArchWiki — udev — Setting static device names | https://wiki.archlinux.org/title/Udev#Setting_static_device_names |
| ArchWiki — USB storage devices — Power management | https://wiki.archlinux.org/title/USB_storage_devices#Power_management |
