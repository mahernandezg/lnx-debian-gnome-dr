# lnx-debian-gnome-dr

Disaster recovery toolkit for Debian GNU/Linux workstations using GNOME.

The project captures the operating-system configuration, installed
software, desktop settings and technical inventory required to rebuild
a workstation after a fresh Debian installation or hardware failure.


## Author and websites

Created and maintained by **Manuel Alejandro Hernández Giuliani**.

- Personal website: [manuelhernandezgiuliani.com](https://manuelhernandezgiuliani.com)
- The Data Professor: [thedataprofessor.com](https://thedataprofessor.com)
- MAHG: [mahg.es](https://mahg.es)
- GitHub: [github.com/mahernandezg](https://github.com/mahernandezg)

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

## License

Copyright (C) 2026 Manuel Alejandro Hernández Giuliani.

This project is free software licensed under the
**GNU General Public License version 3 only** (`GPL-3.0-only`).

See [LICENSE](LICENSE) for the complete license text and
[NOTICE.md](NOTICE.md) for attribution and project information.

## Testing

Run the complete fail-fast test suite:

    ./tests/all.sh

The test runner stops immediately if any component fails. Do not commit,
publish a tag or create a release unless the complete suite finishes with:

    PASS: all project tests completed successfully
