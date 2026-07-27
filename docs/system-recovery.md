# System Recovery

The system recovery component preserves selected Debian configuration
required to rebuild the operating system without copying `/etc` blindly.

## Covered areas

- hostname, hosts, locale and filesystem configuration;
- GRUB and initramfs configuration;
- GDM, Wayland and NVIDIA DRM KMS configuration;
- software RAID and UEFI information;
- custom systemd services and timers;
- APT repositories, preferences and public keyrings;
- Docker, Caddy and SSH configuration;
- power, fan, sensors, modules, sysctl and udev configuration.

## Explicit exclusions

The payload does not collect:

- `/etc/shadow` or `/etc/gshadow`;
- SSH host private keys;
- NetworkManager saved connection secrets;
- APT authentication credentials;
- sudoers policy;
- `/etc/machine-id`;
- runtime state or caches.

## Privileged collection

Validation can run as an ordinary user. Unreadable selected paths are
recorded rather than causing the backup to fail.

The future production systemd service will execute as root and preserve the
primary desktop user's context for GNOME and application collection.

## Restoration

System configuration must be restored selectively. Disk identifiers,
hardware compatibility, Debian version and service paths must be reviewed
before any system file is applied.
