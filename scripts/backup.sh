#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Manuel Alejandro Hernández Giuliani

set -Eeuo pipefail

umask 077

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CONFIG="${PROJECT_ROOT}/config/default.conf"
LOCAL_CONFIG="${PROJECT_ROOT}/config/local.conf"
VERSION_FILE="${PROJECT_ROOT}/VERSION"
README_TEMPLATE="${PROJECT_ROOT}/templates/machine-readme.md"

MODE=""
CUSTOM_CONFIG=""
SHOW_README=false

usage() {
    printf '%s\n' \
        "Usage:" \
        "  backup.sh --dry-run [--config FILE] [--show-readme]" \
        "  backup.sh --help" \
        "" \
        "Options:" \
        "  --dry-run       Inspect the planned recovery set without writing files." \
        "  --config FILE   Apply an additional configuration file." \
        "  --show-readme   Render the machine-specific recovery README preview." \
        "  --help          Show this help." \
        "" \
        "This development version supports dry-run mode only."
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit "${2:-1}"
}

while (($# > 0)); do
    case "$1" in
        --dry-run)
            MODE="dry-run"
            shift
            ;;
        --config)
            [[ $# -ge 2 ]] || fail "--config requires a file path." 2
            CUSTOM_CONFIG="$2"
            shift 2
            ;;
        --show-readme)
            SHOW_README=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1" 2
            ;;
    esac
done

[[ "$MODE" == "dry-run" ]] || {
    printf '%s\n\n' \
        "ERROR: this development version requires --dry-run." \
        "No backup was created."
    usage
    exit 2
}

[[ -r "$DEFAULT_CONFIG" ]] || {
    fail "default configuration not found: $DEFAULT_CONFIG"
}

# The configuration files are trusted project-controlled shell fragments.
# Defaults are loaded first; local and explicit configuration override them.
source "$DEFAULT_CONFIG"

if [[ -r "$LOCAL_CONFIG" ]]; then
    source "$LOCAL_CONFIG"
fi

if [[ -n "$CUSTOM_CONFIG" ]]; then
    [[ -r "$CUSTOM_CONFIG" ]] || {
        fail "configuration file is not readable: $CUSTOM_CONFIG"
    }
    source "$CUSTOM_CONFIG"
fi

: "${BACKUP_ROOT:=/var/backups/lnx-debian-gnome-dr}"
: "${RETENTION_COUNT:=12}"
: "${COMPRESSION:=zstd}"
: "${BACKUP_PERSONAL_FILES:=false}"
: "${BACKUP_SSH_KEYS:=false}"
: "${BACKUP_NETWORK_CONNECTIONS:=false}"
: "${BACKUP_DOCKER_DATA:=false}"
: "${ENCRYPT_SENSITIVE_DATA:=false}"
: "${BACKUP_APPLICATION_MANIFESTS:=true}"
: "${BACKUP_APPLICATION_CONFIG:=true}"
: "${BACKUP_PORTABLE_APPLICATIONS:=true}"
: "${BACKUP_EXTERNAL_INSTALLERS:=true}"
: "${MAX_PORTABLE_FILE_SIZE_MIB:=2048}"

TOOLKIT_VERSION="unknown"
if [[ -r "$VERSION_FILE" ]]; then
    TOOLKIT_VERSION="$(<"$VERSION_FILE")"
fi

HOSTNAME_VALUE="$(hostnamectl --static 2>/dev/null || hostname)"
PRIMARY_USER="${SUDO_USER:-$(id -un)}"
PRIMARY_HOME="$(getent passwd "$PRIMARY_USER" | cut -d: -f6)"

if [[ -z "$PRIMARY_HOME" ]]; then
    PRIMARY_HOME="${HOME:-unknown}"
fi

MACHINE_ID="unknown"
if [[ -r /etc/machine-id ]]; then
    MACHINE_ID="$(</etc/machine-id)"
fi

MANUFACTURER="unknown"
if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
    MANUFACTURER="$(</sys/class/dmi/id/sys_vendor)"
fi

MODEL="unknown"
if [[ -r /sys/class/dmi/id/product_version ]]; then
    MODEL="$(</sys/class/dmi/id/product_version)"
elif [[ -r /sys/class/dmi/id/product_name ]]; then
    MODEL="$(</sys/class/dmi/id/product_name)"
fi

OPERATING_SYSTEM="unknown"
if [[ -r /etc/os-release ]]; then
    OPERATING_SYSTEM="$(
        . /etc/os-release
        printf '%s' "${PRETTY_NAME:-unknown}"
    )"
fi

KERNEL="$(uname -r)"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"
if command -v gnome-shell >/dev/null 2>&1; then
    DESKTOP="$(gnome-shell --version 2>/dev/null || printf '%s' "$DESKTOP")"
fi

NVIDIA_VERSION="not installed"
if command -v nvidia-smi >/dev/null 2>&1; then
    NVIDIA_VERSION="$(
        nvidia-smi \
            --query-gpu=driver_version \
            --format=csv,noheader \
            2>/dev/null \
            | head -n 1
    )"
fi

BACKUP_DATE="$(date --iso-8601=seconds)"
BACKUP_ID="$(date '+%Y-%m-%d_%H-%M-%S')"
RECOVERY_SET="${BACKUP_ROOT}/${HOSTNAME_VALUE}/${BACKUP_ID}"
ARCHIVE_NAME="configuration-${HOSTNAME_VALUE}-${BACKUP_ID}.tar.zst"

mount_status() {
    local path="$1"
    local candidate="$path"

    while [[ "$candidate" != "/" && ! -e "$candidate" ]]; do
        candidate="$(dirname "$candidate")"
    done

    if findmnt --target "$candidate" >/dev/null 2>&1; then
        findmnt \
            --target "$candidate" \
            --noheadings \
            --output SOURCE,FSTYPE,TARGET \
            2>/dev/null \
            | head -n 1
    else
        printf 'not currently mounted'
    fi
}

render_readme() {
    [[ -r "$README_TEMPLATE" ]] || {
        fail "README template not found: $README_TEMPLATE"
    }

    local content
    content="$(<"$README_TEMPLATE")"

    content="${content//\{\{HOSTNAME\}\}/$HOSTNAME_VALUE}"
    content="${content//\{\{MACHINE_ID\}\}/$MACHINE_ID}"
    content="${content//\{\{MANUFACTURER\}\}/$MANUFACTURER}"
    content="${content//\{\{MODEL\}\}/$MODEL}"
    content="${content//\{\{OPERATING_SYSTEM\}\}/$OPERATING_SYSTEM}"
    content="${content//\{\{KERNEL\}\}/$KERNEL}"
    content="${content//\{\{DESKTOP\}\}/$DESKTOP}"
    content="${content//\{\{SESSION_TYPE\}\}/$SESSION_TYPE}"
    content="${content//\{\{PRIMARY_USER\}\}/$PRIMARY_USER}"
    content="${content//\{\{BACKUP_DATE\}\}/$BACKUP_DATE}"
    content="${content//\{\{TOOLKIT_VERSION\}\}/$TOOLKIT_VERSION}"
    content="${content//\{\{NVIDIA_VERSION\}\}/$NVIDIA_VERSION}"

    printf '%s\n' "$content"
}

printf '%s\n' \
    "lnx-debian-gnome-dr — Backup plan" \
    "=================================" \
    "" \
    "MODE: DRY RUN" \
    "NO FILES WILL BE WRITTEN OR MODIFIED." \
    ""

printf 'Toolkit version:      %s\n' "$TOOLKIT_VERSION"
printf 'Hostname:             %s\n' "$HOSTNAME_VALUE"
printf 'Primary user:         %s\n' "$PRIMARY_USER"
printf 'Primary home:         %s\n' "$PRIMARY_HOME"
printf 'Operating system:     %s\n' "$OPERATING_SYSTEM"
printf 'Kernel:               %s\n' "$KERNEL"
printf 'Desktop:              %s\n' "$DESKTOP"
printf 'Session:              %s\n' "$SESSION_TYPE"
printf 'Backup date:          %s\n' "$BACKUP_DATE"

printf '\nConfiguration\n'
printf '%s\n' "-------------"
printf 'Default config:       %s\n' "$DEFAULT_CONFIG"
printf 'Local config:         %s\n' "$LOCAL_CONFIG"

if [[ -n "$CUSTOM_CONFIG" ]]; then
    printf 'Explicit config:      %s\n' "$CUSTOM_CONFIG"
else
    printf 'Explicit config:      none\n'
fi

printf 'Backup root:          %s\n' "$BACKUP_ROOT"
printf 'Storage status:       %s\n' "$(mount_status "$BACKUP_ROOT")"
printf 'Retention count:      %s recovery sets\n' "$RETENTION_COUNT"
printf 'Compression:          %s\n' "$COMPRESSION"

printf '\nPlanned recovery set\n'
printf '%s\n' "--------------------"
printf '%s/\n' "$RECOVERY_SET"
printf '  README.md\n'
printf '  MANIFEST.md\n'
printf '  HISTORY.md\n'
printf '  inventory.txt\n'
printf '  applications/\n'
printf '    APPLICATIONS.md\n'
printf '    SHA256SUMS\n'
printf '    apt/\n'
printf '    flatpak/\n'
printf '    snap/\n'
printf '    portable/\n'
printf '    local-binaries/\n'
printf '    desktop-launchers/\n'
printf '    language-tools/\n'
printf '  desktop/\n'
printf '    dconf.ini\n'
printf '    gnome-extensions.txt\n'
printf '  system/\n'
printf '    etc-selected/\n'
printf '    systemd-enabled.txt\n'
printf '    grub/\n'
printf '    raid/\n'
printf '    boot/\n'
printf '  user/\n'
printf '    git/\n'
printf '    shell/\n'
printf '    terminal/\n'
printf '    application-config/\n'
printf '  docker/\n'
printf '    inventory/\n'
printf '  logs/\n'
printf '    backup.log\n'
printf '  %s\n' "$ARCHIVE_NAME"
printf '  SHA256SUMS\n'

printf '\nPlanned system configuration\n'
printf '%s\n' "----------------------------"
printf '%s\n' \
    "  - /etc/fstab" \
    "  - /etc/default/grub" \
    "  - /etc/default/grub.d/" \
    "  - /etc/mdadm/" \
    "  - /etc/modprobe.d/" \
    "  - /etc/systemd/system/" \
    "  - /etc/docker/" \
    "  - selected SSH client and server configuration" \
    "  - package repository definitions" \
    "  - enabled systemd units and timers" \
    "  - UEFI, RAID, disk and filesystem metadata"

printf '\nPlanned user configuration\n'
printf '%s\n' "--------------------------"
printf '%s\n' \
    "  - GNOME dconf export" \
    "  - GNOME extension inventory" \
    "  - Git configuration" \
    "  - shell configuration" \
    "  - tmux configuration" \
    "  - terminal configuration" \
    "  - selected application configuration under ~/.config" \
    "  - SSH client configuration without private keys by default"


printf '\nPlanned application recovery\n'
printf '%s\n' "----------------------------"
printf '%s\n' \
    "  - Debian and external APT applications" \
    "  - Flatpak applications, runtimes, remotes and overrides" \
    "  - Snap applications" \
    "  - GUI desktop launchers" \
    "  - TUI and CLI commands" \
    "  - AppImage and portable applications" \
    "  - executables under ~/.local/bin and /usr/local" \
    "  - pip, pipx and uv tools" \
    "  - npm and pnpm global tools" \
    "  - Cargo, rustup and Go tools" \
    "  - mise, asdf and Homebrew tools" \
    "  - selected application configuration"

printf 'Application manifests:     %s\n' "$BACKUP_APPLICATION_MANIFESTS"
printf 'Application configuration: %s\n' "$BACKUP_APPLICATION_CONFIG"
printf 'Portable applications:     %s\n' "$BACKUP_PORTABLE_APPLICATIONS"
printf 'External installers:       %s\n' "$BACKUP_EXTERNAL_INSTALLERS"
printf 'Maximum portable file:     %s MiB\n' "$MAX_PORTABLE_FILE_SIZE_MIB"

printf '\nSensitive data policy\n'
printf '%s\n' "---------------------"
printf 'Personal documents:       %s\n' "$BACKUP_PERSONAL_FILES"
printf 'SSH private keys:          %s\n' "$BACKUP_SSH_KEYS"
printf 'NetworkManager secrets:    %s\n' "$BACKUP_NETWORK_CONNECTIONS"
printf 'Docker runtime data:       %s\n' "$BACKUP_DOCKER_DATA"
printf 'Sensitive-data encryption: %s\n' "$ENCRYPT_SENSITIVE_DATA"

if [[ "$BACKUP_SSH_KEYS" == "true" ||
      "$BACKUP_NETWORK_CONNECTIONS" == "true" ]]; then
    printf '\n'
    printf '%s\n' \
        "WARNING: sensitive material is requested by configuration." \
        "It will remain blocked until encrypted payload support is implemented."
fi

printf '\nExplicit exclusions\n'
printf '%s\n' "-------------------"
printf '%s\n' \
    "  - personal documents managed by Déjà Dup" \
    "  - Downloads" \
    "  - Trash" \
    "  - browser caches" \
    "  - application caches" \
    "  - Docker images and container writable layers" \
    "  - credentials not protected by encryption" \
    "  - transient runtime files" \
    "  - complete raw copies of /etc" \
    "  - complete raw copies of the home directory"

printf '\nExecution gates for the future write mode\n'
printf '%s\n' "-----------------------------------------"
printf '%s\n' \
    "  1. Backup destination exists and is mounted." \
    "  2. Destination is not the root filesystem." \
    "  3. Required free space is available." \
    "  4. Inventory collection succeeds." \
    "  5. Sensitive files comply with the encryption policy." \
    "  6. Archive creation succeeds." \
    "  7. SHA-256 verification succeeds." \
    "  8. README and manifest are generated." \
    "  9. Incomplete recovery sets are deleted." \
    " 10. Retention is applied only after successful verification."

if [[ "$SHOW_README" == true ]]; then
    printf '\n\n'
    printf '%s\n' \
        "Machine README preview" \
        "======================" \
        ""
    render_readme
fi

printf '\nDRY RUN COMPLETE — no files were written.\n'
