#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly BCM_PCI_ID="14e4:43ba"
readonly BCM_BLACKLIST_FILE="/etc/modprobe.d/broadcom-wl-bcm43602.conf"

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this script with sudo: sudo ./${SCRIPT_NAME}"
  fi
}

require_commands() {
  local missing=()
  local command

  for command in pacman lspci depmod modprobe mkinitcpio iw; do
    if ! command -v "${command}" >/dev/null 2>&1; then
      missing+=("${command}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    fail "Missing required command(s): ${missing[*]}"
  fi
}

check_hardware() {
  local pci_info
  pci_info="$(lspci -nnv)"

  # Mirror Omarchy's lspci-based Broadcom detection, extended for BCM43602.
  if echo "${pci_info}" | grep -q "${BCM_PCI_ID}"; then
    log "BCM43602 detected (${BCM_PCI_ID})"
    return
  fi

  fail "This script is intended for the BCM43602 (${BCM_PCI_ID}) in this repo."
}

backup_existing_config() {
  if [[ -f "${BCM_BLACKLIST_FILE}" ]]; then
    local backup_path="${BCM_BLACKLIST_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "${BCM_BLACKLIST_FILE}" "${backup_path}"
    log "Backed up existing blacklist file to ${backup_path}"
  fi
}

replace_package() {
  if pacman -Q broadcom-wl-dkms >/dev/null 2>&1; then
    log "Removing broadcom-wl-dkms to align with Omarchy's current Broadcom fix"
    pacman -R --noconfirm broadcom-wl-dkms
  else
    log "broadcom-wl-dkms is not installed"
  fi

  log "Installing broadcom-wl, dkms, and linux-headers"
  pacman -S --needed --noconfirm broadcom-wl dkms linux-headers
}

write_blacklist_file() {
  log "Writing BCM43602 wl preference file to ${BCM_BLACKLIST_FILE}"
  mkdir -p "$(dirname "${BCM_BLACKLIST_FILE}")"

  cat > "${BCM_BLACKLIST_FILE}" <<'EOF'
# Prefer the proprietary wl driver for BCM43602 on this MacBook.
# These blacklist entries mirror the standard broadcom-wl config, but
# keeping them in /etc makes the intent explicit and user-owned.
blacklist b43
blacklist b43legacy
blacklist bcm43xx
blacklist bcma
blacklist brcm80211
blacklist brcmfmac
blacklist brcmsmac
blacklist ssb
EOF
}

refresh_modules() {
  log "Refreshing module dependency metadata"
  depmod -a
}

rebuild_initramfs() {
  log "Rebuilding initramfs so the next boot sees the updated Broadcom module policy"
  mkinitcpio -P
}

try_live_reload() {
  local module

  log "Trying a live wl reload (safe to ignore if it still fails before reboot)"

  for module in brcmfmac brcmutil brcmsmac bcma ssb b43 b43legacy wl; do
    if lsmod | awk '{print $1}' | grep -qx "${module}"; then
      log "Unloading ${module}"
      modprobe -r "${module}"
    fi
  done

  if modprobe wl >/dev/null 2>&1; then
    log "wl module loaded"
  else
    log "wl still does not load cleanly in the current boot"
    return
  fi

  if iw dev | grep -q '^Interface '; then
    log "A wireless interface is visible in the current boot"
  else
    log "No wireless interface is visible yet"
  fi
}

print_summary() {
  cat <<'EOF'

Done.

This script aligns the machine with Omarchy's current Broadcom package path,
keeps the BCM43602 `wl` blacklist policy in place, refreshes module metadata,
and rebuilds the initramfs for the next boot. That cleanup is useful, but it is
not a guarantee that BCM43602 will successfully initialize with `wl` on the
current kernel.

Next steps:
1. Reboot the machine.
2. After reboot, verify the Omarchy-style Broadcom package state:
     pacman -Q broadcom-wl dkms linux-headers
3. Verify whether the Broadcom card is actually using wl:
     lspci -k -s 02:00.0
4. Check for a wireless interface:
     iw dev
5. Check Omarchy's default wireless stack:
     systemctl status iwd.service --no-pager
     iwctl device list

If `iw dev` is still empty or `lspci -k` still does not show
`Kernel driver in use: wl`, capture:
  sudo journalctl -k -b --no-pager | grep -Ei 'wl|brcm|cfg80211|firmware'

If that still shows `wl` failing, stay on the Omarchy-style `wl` path in this
repo and verify the userspace network stack before changing anything else:
  sudo pacman -S --needed networkmanager
  sudo systemctl disable --now iwd
  sudo systemctl enable --now NetworkManager.service

Then re-check:
  nmcli device status
  iw dev
EOF
}

main() {
  require_root
  require_commands
  check_hardware
  backup_existing_config
  replace_package
  write_blacklist_file
  refresh_modules
  rebuild_initramfs
  try_live_reload
  print_summary
}

main "$@"
