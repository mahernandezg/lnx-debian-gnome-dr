# lnx-debian-gnome-dr

Disaster recovery toolkit for Debian GNU/Linux workstations using GNOME.

The project captures the operating-system configuration, installed
software, desktop settings and technical inventory required to rebuild
a workstation after a fresh Debian installation or hardware failure.

## Scope

This project backs up:

- Machine identity and hostname
- Debian package inventory
- Flatpak and Snap package inventory
- GNOME and dconf configuration
- Selected system configuration from `/etc`
- Git, SSH and terminal configuration
- NetworkManager configuration
- Enabled systemd services
- Docker configuration and inventory
- NVIDIA and Wayland configuration
- Hardware, storage and network inventory
- Recovery instructions and integrity checks

Personal documents are outside this project's scope. They should be
protected separately using tools such as Déjà Dup.

## Planned commands

    lnx-debian-gnome-dr backup
    lnx-debian-gnome-dr restore
    lnx-debian-gnome-dr verify
    lnx-debian-gnome-dr inventory
    lnx-debian-gnome-dr list

## Recovery principles

- Backups must be human-readable.
- Restoration must support dry-run mode.
- Sensitive files must never be overwritten silently.
- Archives must include integrity checks.
- Restoration must be selective rather than blind.
- Personal files remain managed separately.

## Status

Initial development version.

Do not use this project as the only recovery mechanism until backup and
restore procedures have been tested successfully.

## Repository

Personal project maintained by `mahernandezg`:

`github.com/mahernandezg/lnx-debian-gnome-dr`
