# Debian GNOME Disaster Recovery

## Machine information

| Property | Value |
|---|---|
| Hostname | {{HOSTNAME}} |
| Machine ID | {{MACHINE_ID}} |
| Manufacturer | {{MANUFACTURER}} |
| Model | {{MODEL}} |
| Operating system | {{OPERATING_SYSTEM}} |
| Kernel | {{KERNEL}} |
| Desktop | {{DESKTOP}} |
| Session type | {{SESSION_TYPE}} |
| Primary user | {{PRIMARY_USER}} |
| Backup date | {{BACKUP_DATE}} |
| Toolkit version | {{TOOLKIT_VERSION}} |

## Purpose

This recovery set contains the operating-system configuration and
technical information required to rebuild this workstation after a
fresh Debian installation or hardware failure.

It does not replace the personal-file backup maintained separately
using Déjà Dup.

## Recovery procedure

1. Confirm that the archive passes its SHA-256 verification.
2. Read this document completely.
3. Review `MANIFEST.md`.
4. Review `inventory.txt`.
5. Install the same Debian major version recorded above.
6. Create the primary user account.
7. Install Git, rsync and zstd.
8. Clone `lnx-debian-gnome-dr`.
9. Mount the disaster recovery storage device.
10. Run the restore command in dry-run mode.
11. Review every proposed change.
12. Execute only the approved restoration sections.
13. Reboot the machine.
14. Run the verification command.

## Initial commands

    sudo apt update
    sudo apt install git rsync zstd
    git clone https://github.com/mahernandezg/lnx-debian-gnome-dr.git
    cd lnx-debian-gnome-dr
    sudo ./scripts/install.sh

## Important warnings

- Do not overwrite SSH keys without reviewing the destination.
- Do not restore NetworkManager secrets onto an untrusted machine.
- Do not copy `/etc` blindly over a different Debian release.
- Review disk names and UUIDs before restoring mount configuration.
- Restore NVIDIA configuration only when compatible hardware exists.
- Review users, groups and permissions before applying them.
- Keep the personal-file backup separate from this recovery set.

## Verification checklist

- [ ] Archive checksum verified
- [ ] Hostname restored
- [ ] Primary user verified
- [ ] Debian packages restored
- [ ] GNOME settings restored
- [ ] Wayland session verified
- [ ] NVIDIA driver verified
- [ ] Git configuration restored
- [ ] SSH configuration reviewed
- [ ] Docker service verified
- [ ] Network connectivity verified
- [ ] Enabled services reviewed
- [ ] Déjà Dup personal-file restore completed separately
