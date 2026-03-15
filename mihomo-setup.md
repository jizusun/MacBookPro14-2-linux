# Mihomo setup

This document records how `mihomo` was installed on this machine on
`2026-03-15`.

## Goal

Install the `mihomo` proxy binary in a way that works immediately for the
current user without requiring root access.

## Installation method used

`mihomo` was installed from the upstream GitHub release for Linux `amd64`.

The asset used was:

- `mihomo-linux-amd64-compatible-v1.19.21.gz`

The binary was installed into the user-local bin directory:

- `~/.local/bin/mihomo`

This approach was used because:

- `sudo` was not available non-interactively at the time
- `pacman -Ss` did not show an obvious install candidate
- `~/.local/bin` is already on this user's `PATH`

## Commands used

```bash
ASSET='mihomo-linux-amd64-compatible-v1.19.21.gz'
gh release download -R MetaCubeX/mihomo v1.19.21 -p "$ASSET"
mkdir -p ~/.local/bin
gzip -dc "$ASSET" > ~/.local/bin/mihomo
chmod 0755 ~/.local/bin/mihomo
```

## Verification

The installed binary was verified with:

```bash
mihomo -v
```

Observed result:

```text
Mihomo Meta v1.19.21 linux amd64 with go1.26.1
Use tags: with_gvisor
```

The current shell environment also includes `~/.local/bin` in `PATH`, so the
binary can be run directly as:

```bash
mihomo
```

## Current scope

Only the binary was installed.

This setup does **not** yet include:

- a config file
- a subscription or profile
- a `systemd --user` service
- a system-wide installation under `/usr/local/bin`

## Useful next steps

### Show the version

```bash
mihomo -v
```

### Show available flags

```bash
mihomo -h
```

### Prepare a config directory

If needed later, a common next step is to create a config directory such as:

```bash
mkdir -p ~/.config/mihomo
```

### Run with an explicit config

Example:

```bash
mihomo -d ~/.config/mihomo
```

## Notes

- If a system-wide install is preferred later, the binary can be moved or
  reinstalled to `/usr/local/bin` with `sudo`.
- If automatic startup is needed later, a `systemd --user` service is the
  cleanest next step.
