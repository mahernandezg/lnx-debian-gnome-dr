# Backup Format

Planned recovery-set structure:

    disaster-recovery/
    ├── README.md
    ├── MANIFEST.md
    ├── HISTORY.md
    ├── inventory.txt
    ├── SHA256SUMS
    ├── configuration.tar.zst
    └── logs/
        └── backup.log

Each dated recovery set must be self-contained and understandable
without requiring access to the original workstation.

## Integrated validation recovery set

Before enabling writes to permanent backup storage, the project generates an
integrated recovery set in a temporary validation directory.

It combines:

- machine inventory;
- GUI, TUI and CLI application manifests;
- GNOME desktop state;
- machine-specific recovery instructions;
- project attribution and license;
- nested and top-level SHA-256 verification.

The validation set intentionally excludes encrypted secrets, privileged system
payloads, compression and automated restoration.
