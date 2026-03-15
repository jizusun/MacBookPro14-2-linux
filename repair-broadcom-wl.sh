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

  for command in pacman lspci depmod modprobe; do
    if ! command -v "${command}" >/dev/null 2>&1; then
      missing+=("${command}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    fail "Missing required command(s): ${missing[*]}"
  fi
}

check_hardware() {
  if ! lspci -nn | grep -qi "${BCM_PCI_ID}"; then
    fail "This script is intended for the BCM43602 (${BCM_PCI_ID}) in this repo."
  fi
}

backup_existing_config() {
  if [[ -f "${BCM_BLACKLIST_FILE}" ]]; then
    local backup_path="${BCM_BLACKLIST_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "${BCM_BLACKLIST_FILE}" "${backup_path}"
    log "Backed up existing blacklist file to ${backup_path}"
  fi
}

replace_package() {
  if pacman -Q broadcom-wl >/dev/null 2>&1; then
    log "Removing stock broadcom-wl package"
    pacman -R --noconfirm broadcom-wl
  else
    log "Stock broadcom-wl package is not installed"
  fi

  log "Installing broadcom-wl-dkms, dkms, and linux-headers"
  pacman -S --needed --noconfirm broadcom-wl-dkms dkms linux-headers
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

try_live_reload() {
  log "Trying a live wl reload (safe to ignore if it still fails before reboot)"
  modprobe -r wl >/dev/null 2>&1 || true

  if modprobe wl >/dev/null 2>&1; then
    log "wl module loaded"
  else
    log "wl still does not load cleanly in the current boot"
  fi
}

print_summary() {
  cat <<'EOF'

Done.

Next steps:
1. Reboot the machine.
2. After reboot, verify the Broadcom card is using wl:
     lspci -k -s 02:00.0
3. Check for a wireless interface:
     iw dev
4. Check NetworkManager or iwd device status:
     nmcli device status

If wl still fails after reboot, capture:
  journalctl -k -b --no-pager | grep -Ei 'wl|brcm|cfg80211'
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
  try_live_reload
  print_summary
}

main "$@"
