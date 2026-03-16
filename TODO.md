# TODO

- [ ] USB tethered network adapter is not re-recognized by omarchy after being unplugged and replugged
  - **Solution found (omarchy `usb-autosuspend.sh`):** disable USB autosuspend so the kernel
    does not power-gate the device between plug/unplug cycles.
  - See `omarchy-setup.md` §"Fix USB tethering re-connect" for steps.

- [ ] Closing the lid prevents the system from waking up and causes excessive battery drain
  - **Solution found (omarchy issue #1840 + `fix-apple-suspend-nvme.sh`):** switch the kernel
    sleep back-end to `s2idle`, configure logind to use `sleep` on lid-close, and disable
    NVMe D3-cold to prevent the drive from wedging during resume.
  - See [`sleep-lid-solutions.md`](./sleep-lid-solutions.md) for full steps and rationale.

- [ ] Escape key is non-functional due to Touch Bar not being supported
  - **Solution found (omarchy `fix-apple-spi-keyboard.sh`):** install `macbook12-spi-driver-dkms`
    (provides the `applespi` kernel module) and add the SPI modules to the initramfs.  Once
    loaded, the Touch Bar exposes a regular HID keyboard device including the Esc key.
  - See `omarchy-setup.md` §"Fix the escape key (Touch Bar / applespi)" for steps.
