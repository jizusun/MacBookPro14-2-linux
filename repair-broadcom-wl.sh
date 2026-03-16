#!/usr/bin/env bash
#
# repair-broadcom-wl.sh — Solution 3 from wireless-solutions.md
#
# Installs the proprietary Broadcom wl driver for BCM43602 (14e4:43ba),
# blacklists competing open-source drivers, switches from iwd to
# NetworkManager + wpa_supplicant, and rebuilds the initramfs.
#
# Usage:
#   sudo ./repair-broadcom-wl.sh          # install & configure
#   sudo ./repair-broadcom-wl.sh --undo   # reverse all changes

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly PCI_ID="14e4:43ba"
readonly BLACKLIST_FILE="/etc/modprobe.d/broadcom-wl-bcm43602.conf"
readonly BRCMFMAC_OVERRIDE="/etc/modprobe.d/allow-brcmfmac.conf"
readonly WL_MODULES_LOAD="/etc/modules-load.d/wl.conf"
readonly BRCMFMAC_MODULES_LOAD="/etc/modules-load.d/brcmfmac.conf"

# ── Logging ──────────────────────────────────────────────────────────────────

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2; }
fail() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }

# ── Pre-flight checks ───────────────────────────────────────────────────────

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Run with sudo: sudo ./${SCRIPT_NAME}"
}

require_commands() {
  local missing=() cmd
  for cmd in pacman lspci depmod modprobe mkinitcpio iw systemctl; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  (( ${#missing[@]} == 0 )) || fail "Missing command(s): ${missing[*]}"
}

check_hardware() {
  lspci -nn | grep -q "$PCI_ID" \
    || fail "BCM43602 ($PCI_ID) not detected — wrong hardware for this script."
  log "BCM43602 detected ($PCI_ID)"
}

get_pci_address() {
  lspci -nn | grep "$PCI_ID" | awk '{print $1}' | head -1
}

warn_kernel_compat() {
  local kver
  kver="$(uname -r)"
  log "Kernel: $kver"
  warn "The wl driver may fail on some kernel versions (known: 6.19.x)."
  warn "If wl doesn't load after reboot, check:"
  warn "  sudo journalctl -k -b --no-pager | grep -i 'wl.*failed'"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S).$$"
    cp -a "$file" "$backup"
    log "Backed up $file → $backup"
  fi
}

rebuild_initramfs() {
  log "Refreshing module dependencies"
  depmod -a || warn "depmod -a returned non-zero (continuing)"

  log "Rebuilding initramfs"
  mkinitcpio -P || fail "mkinitcpio failed — do NOT reboot until this is fixed"
}

# ── Install flow (default) ──────────────────────────────────────────────────

install_packages() {
  if pacman -Q broadcom-wl-dkms >/dev/null 2>&1; then
    log "Removing broadcom-wl-dkms (replaced by broadcom-wl)"
    pacman -R --noconfirm broadcom-wl-dkms \
      || fail "Could not remove broadcom-wl-dkms — resolve manually"
  fi

  log "Installing broadcom-wl, dkms, linux-headers, networkmanager"
  pacman -S --needed --noconfirm broadcom-wl dkms linux-headers networkmanager \
    || fail "Package installation failed"
}

write_blacklist() {
  backup_file "$BLACKLIST_FILE"
  log "Writing competing-driver blacklist → $BLACKLIST_FILE"

  cat > "$BLACKLIST_FILE" <<'EOF'
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
}

remove_brcmfmac_override() {
  if [[ -f "$BRCMFMAC_OVERRIDE" ]]; then
    log "Removing brcmfmac override from Solution 1 ($BRCMFMAC_OVERRIDE)"
    rm -f "$BRCMFMAC_OVERRIDE"
  fi
}

disable_brcmfmac_modules_load() {
  if [[ -f "$BRCMFMAC_MODULES_LOAD" ]]; then
    backup_file "$BRCMFMAC_MODULES_LOAD"
    rm -f "$BRCMFMAC_MODULES_LOAD"
    log "Removed $BRCMFMAC_MODULES_LOAD (conflicts with wl blacklist)"
  fi
}

enable_wl_modules_load() {
  log "Writing $WL_MODULES_LOAD to load wl at boot"
  printf 'wl\n' > "$WL_MODULES_LOAD"
}

switch_to_networkmanager() {
  log "Switching network backend: iwd → NetworkManager"

  if systemctl is-enabled --quiet iwd 2>/dev/null; then
    systemctl disable --now iwd
    log "Stopped and disabled iwd"
  fi

  systemctl enable --now NetworkManager.service
  log "Enabled and started NetworkManager"
}

try_live_reload() {
  log "Attempting live wl module reload (may require reboot)"

  local module
  for module in brcmfmac brcmutil brcmsmac bcma ssb b43 b43legacy wl; do
    if lsmod | grep -qw "^${module}"; then
      modprobe -r "$module" 2>/dev/null \
        && log "Unloaded $module" \
        || warn "Could not unload $module (may be in use)"
    fi
  done

  if modprobe wl 2>/dev/null; then
    log "wl module loaded successfully"
    if iw dev | grep -q 'Interface'; then
      log "Wireless interface is visible"
    else
      warn "wl loaded but no wireless interface — reboot likely needed"
    fi
  else
    warn "wl did not load in the current boot — reboot required"
  fi
}

do_install() {
  check_hardware
  warn_kernel_compat
  install_packages
  write_blacklist
  remove_brcmfmac_override
  disable_brcmfmac_modules_load
  enable_wl_modules_load
  rebuild_initramfs
  switch_to_networkmanager
  try_live_reload

  local pci_addr
  pci_addr="$(get_pci_address)"

  cat <<EOF

Done — Solution 3 applied. Reboot to complete.

After reboot, verify:
  lspci -k -s ${pci_addr}                         # "Kernel driver in use: wl"
  iw dev                                           # wireless interface present
  nmcli device wifi list                           # nearby networks
  nmcli device wifi connect "SSID" password "…"    # connect

If wl fails to load:
  sudo journalctl -k -b --no-pager | grep -Ei 'wl|brcm|firmware'

To reverse all changes:
  sudo ./${SCRIPT_NAME} --undo
EOF
}

# ── Undo flow ────────────────────────────────────────────────────────────────

do_undo() {
  check_hardware
  log "Reversing Solution 3 changes"

  # Remove our blacklist
  if [[ -f "$BLACKLIST_FILE" ]]; then
    rm -f "$BLACKLIST_FILE"
    log "Removed $BLACKLIST_FILE"
  else
    log "No blacklist file to remove"
  fi

  # Remove wl modules-load entry
  if [[ -f "$WL_MODULES_LOAD" ]]; then
    rm -f "$WL_MODULES_LOAD"
    log "Removed $WL_MODULES_LOAD"
  fi

  # Restore brcmfmac modules-load entry
  if [[ ! -f "$BRCMFMAC_MODULES_LOAD" ]]; then
    printf 'brcmfmac\n' > "$BRCMFMAC_MODULES_LOAD"
    log "Restored $BRCMFMAC_MODULES_LOAD"
  fi

  # Remove broadcom-wl (its package blacklist in /usr/lib also blocks brcmfmac)
  if pacman -Q broadcom-wl >/dev/null 2>&1; then
    pacman -R --noconfirm broadcom-wl
    log "Removed broadcom-wl package"
  fi

  # Switch back to iwd
  if systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    systemctl disable --now NetworkManager.service
    log "Stopped and disabled NetworkManager"
  fi

  if command -v iwctl >/dev/null 2>&1; then
    systemctl enable --now iwd
    log "Enabled and started iwd"
  else
    warn "iwd not found — install it or enable another network backend"
  fi

  rebuild_initramfs

  cat <<'EOF'

Done — Solution 3 reversed. Reboot to complete.

The brcmfmac driver will load on next boot. You can now try
Solution 1 or Solution 2 from wireless-solutions.md.
EOF
}

# ── Entry point ──────────────────────────────────────────────────────────────

main() {
  require_root
  require_commands

  case "${1:-}" in
    --undo)    do_undo ;;
    --help|-h) printf 'Usage: sudo ./%s [--undo]\n' "$SCRIPT_NAME"; exit 0 ;;
    "")        do_install ;;
    *)         fail "Unknown option: $1 (use --help)" ;;
  esac
}

main "$@"
