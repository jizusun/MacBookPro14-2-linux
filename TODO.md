# TODO

- [ ] USB tethered network adapter is not re-recognized by omarchy after being unplugged and replugged
- [ ] Closing the lid prevents the system from waking up and causes excessive battery drain
- [ ] Escape key is non-functional due to Touch Bar not being supported



After reboot, verify:
  lsmod | grep brcmfmac                    # driver loaded
  iw dev                                    # wireless interface present
  nmcli device wifi list                    # nearby networks visible
  nmcli device wifi connect "SSID" password "…"

If no networks appear, try setting regulatory domain:
  sudo iw reg set CN                        # use your country code
