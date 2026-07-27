# Application Recovery

`lnx-debian-gnome-dr` classifies workstation applications by their
installation and recovery mechanism.

## Covered application types

- Debian and third-party APT packages
- Flatpak applications and runtimes
- Snap applications
- AppImage applications
- Portable executables
- Manually installed binaries
- Desktop launchers
- CLI and TUI tools
- Language-specific tools
- Selected application configuration

## Package and tool ecosystems

The inventory attempts to detect:

- APT and dpkg
- Flatpak
- Snap
- pip and pipx
- uv
- npm
- pnpm
- Cargo and rustup
- Go
- mise
- asdf
- Homebrew
- RubyGems
- Composer
- .NET global tools

## Recovery model

Normal applications should be reinstalled from reproducible manifests.

Portable or manually distributed applications may additionally require
preservation of:

- the executable or installer;
- its SHA-256 checksum;
- its desktop launcher;
- its icon;
- its configuration;
- its original installation path.

## Configuration policy

Application configuration will be collected through an explicit allowlist.

The project must not copy all of `~/.config` or `~/.local/share` blindly.
Caches, credentials, temporary files and large application data stores must
be excluded or handled separately.

## Current implementation status

The current application component produces a read-only inventory.

Copying portable binaries, installers and application configuration will be
implemented in a later backup cycle.
