#!/usr/bin/env bash
#
# switch-to-brcmfmac.sh — Switch from proprietary wl to open-source brcmfmac
#
# For BCM43602 (14e4:43ba) on MacBookPro14,2.
# Assumes brcmfmac.feature_disable=0x82000 is already in kernel cmdline.
#
# Usage:
#   sudo ./switch-to-brcmfmac.sh          # switch to brcmfmac
#   sudo ./switch-to-brcmfmac.sh --undo   # switch back to wl
#
# After running, reboot to apply changes.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2; }
fail() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || fail "Run with sudo: sudo ./${SCRIPT_NAME}"

do_switch() {
  log "Switching from wl → brcmfmac for BCM43602"

  # 1. Remove our blacklist that blocks brcmfmac
  if [[ -f /etc/modprobe.d/broadcom-wl-bcm43602.conf ]]; then
    rm -f /etc/modprobe.d/broadcom-wl-bcm43602.conf
    log "Removed /etc/modprobe.d/broadcom-wl-bcm43602.conf"
  fi

  # 2. Remove wl auto-load
  if [[ -f /etc/modules-load.d/wl.conf ]]; then
    rm -f /etc/modules-load.d/wl.conf
    log "Removed /etc/modules-load.d/wl.conf"
  fi

  # 3. Remove broadcom-wl package (ships its own brcmfmac blacklist)
  if pacman -Q broadcom-wl >/dev/null 2>&1; then
    pacman -R --noconfirm broadcom-wl
    log "Removed broadcom-wl package"
  elif pacman -Q broadcom-wl-dkms >/dev/null 2>&1; then
    pacman -R --noconfirm broadcom-wl-dkms
    log "Removed broadcom-wl-dkms package"
  else
    log "No broadcom-wl package installed (OK)"
  fi

  # 4. Verify no remaining brcmfmac blacklist
  local f
  for f in /etc/modprobe.d/*.conf /usr/lib/modprobe.d/*.conf; do
    [[ -f "$f" ]] || continue
    if grep -q '^blacklist brcmfmac' "$f" 2>/dev/null; then
      warn "Removing 'blacklist brcmfmac' from $f"
      sed -i '/^blacklist brcmfmac$/d' "$f"
    fi
  done

  # 5. Create brcmfmac auto-load
  printf 'brcmfmac\n' > /etc/modules-load.d/brcmfmac.conf
  log "Created /etc/modules-load.d/brcmfmac.conf"

  # 6. Install wireless-regdb for proper regulatory domain support
  pacman -S --needed --noconfirm wireless-regdb 2>/dev/null \
    && log "Installed wireless-regdb" \
    || warn "Could not install wireless-regdb (install manually if needed)"

  # 7. Rebuild initramfs
  log "Rebuilding initramfs"
  depmod -a
  mkinitcpio -P || fail "mkinitcpio failed — do NOT reboot until fixed"

  # 8. Verify kernel cmdline has the feature_disable param
  if grep -q 'brcmfmac.feature_disable=0x82000' /proc/cmdline; then
    log "✓ brcmfmac.feature_disable=0x82000 found in kernel cmdline"
  else
    warn "brcmfmac.feature_disable=0x82000 NOT in kernel cmdline!"
    warn "Add it to /etc/default/limine and run: sudo limine-update"
  fi

  cat <<'EOF'

Done — switched to brcmfmac. Reboot to apply.

After reboot, verify:
  lsmod | grep brcmfmac                    # driver loaded
  iw dev                                    # wireless interface present
  nmcli device wifi list                    # nearby networks visible
  nmcli device wifi connect "SSID" password "…"

If no networks appear, try setting regulatory domain:
  sudo iw reg set CN                        # use your country code
EOF
}

do_undo() {
  log "Switching back from brcmfmac → wl"

  # 1. Remove brcmfmac auto-load
  rm -f /etc/modules-load.d/brcmfmac.conf
  log "Removed /etc/modules-load.d/brcmfmac.conf"

  # 2. Install broadcom-wl
  pacman -S --needed --noconfirm broadcom-wl dkms linux-headers
  log "Installed broadcom-wl"

  # 3. Write blacklist
  cat > /etc/modprobe.d/broadcom-wl-bcm43602.conf <<'CONF'
blacklist b43
blacklist b43legacy
blacklist bcm43xx
blacklist bcma
blacklist brcm80211
blacklist brcmfmac
blacklist brcmsmac
blacklist ssb
CONF
  log "Wrote /etc/modprobe.d/broadcom-wl-bcm43602.conf"

  # 4. Create wl auto-load
  printf 'wl\n' > /etc/modules-load.d/wl.conf
  log "Created /etc/modules-load.d/wl.conf"

  # 5. Rebuild initramfs
  depmod -a
  mkinitcpio -P || fail "mkinitcpio failed"

  cat <<'EOF'

Done — switched back to wl. Reboot to apply.
Note: wl is known to fail on kernel 6.19+.
EOF
}

case "${1:-}" in
  --undo)    do_undo ;;
  --help|-h) printf 'Usage: sudo ./%s [--undo]\n' "$SCRIPT_NAME" ;;
  "")        do_switch ;;
  *)         fail "Unknown option: $1" ;;
esac
