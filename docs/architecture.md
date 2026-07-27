# Architecture

The toolkit separates disaster recovery into five operations:

1. Inventory collection
2. Configuration backup
3. Archive verification
4. Controlled restoration
5. Post-restoration validation

## Backup format

Every recovery set should contain:

- A machine-specific README
- A content manifest
- A technical inventory
- A machine history
- One compressed configuration archive
- SHA-256 checksums
- Backup execution logs

## Design requirements

Backups must be:

- Human-readable
- Versioned
- Checksummed
- Independently inspectable
- Selectively restorable
- Safe to test using dry-run mode

Personal documents are intentionally excluded because they are managed
separately using Déjà Dup.
