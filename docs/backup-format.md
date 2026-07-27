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
