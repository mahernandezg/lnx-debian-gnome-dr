#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Manuel Alejandro Hernández Giuliani

set -Eeuo pipefail

umask 077

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${PROJECT_ROOT}/VERSION"

MODE=""
OUTPUT_DIR=""

usage() {
    printf '%s\n' \
        "Usage:" \
        "  system.sh --dry-run" \
        "  system.sh --output-dir DIRECTORY" \
        "  system.sh --help" \
        "" \
        "Options:" \
        "  --dry-run              Show the planned system collection." \
        "  --output-dir DIRECTORY Generate the system recovery payload." \
        "  --help                 Show this help."
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
        --output-dir)
            [[ $# -ge 2 ]] || fail "--output-dir requires a path." 2
            MODE="collect"
            OUTPUT_DIR="$2"
            shift 2
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

[[ -n "$MODE" ]] || {
    usage >&2
    exit 2
}

PLAN=(
    "Machine identity, locale and filesystem configuration"
    "GRUB and kernel command-line configuration"
    "GDM and Wayland configuration"
    "NVIDIA, DRM KMS and PRIME state"
    "Software RAID configuration and status"
    "UEFI boot entries and Debian EFI files when readable"
    "Enabled systemd services and timers"
    "Custom systemd unit files"
    "APT repositories, preferences and public keyrings"
    "Docker and Caddy system configuration"
    "SSH client and server configuration without host private keys"
    "NetworkManager policy without saved connection secrets"
    "TLP, ThinkFan, fancontrol and sensor configuration"
    "Kernel modules, sysctl and udev rules"
    "System shell and environment configuration"
)

if [[ "$MODE" == "dry-run" ]]; then
    printf '%s\n\n' \
        "SYSTEM RECOVERY PAYLOAD — DRY RUN" \
        "NO FILES WILL BE WRITTEN."

    for item in "${PLAN[@]}"; do
        printf '  - %s\n' "$item"
    done

    printf '\nExplicit exclusions:\n'
    printf '%s\n' \
        "  - /etc/shadow and /etc/gshadow" \
        "  - SSH host private keys" \
        "  - NetworkManager saved connection secrets" \
        "  - APT authentication credentials" \
        "  - sudoers policy" \
        "  - machine-id replacement" \
        "  - runtime and cache data"

    printf '\nDRY RUN COMPLETE — no files were written.\n'
    exit 0
fi

[[ -n "$OUTPUT_DIR" ]] || fail "output directory is required."

if [[ -e "$OUTPUT_DIR" ]] &&
   [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    fail "output directory already exists and is not empty: $OUTPUT_DIR"
fi

mkdir -p \
    "$OUTPUT_DIR/files" \
    "$OUTPUT_DIR/commands" \
    "$OUTPUT_DIR/logs"

chmod 700 \
    "$OUTPUT_DIR" \
    "$OUTPUT_DIR/files" \
    "$OUTPUT_DIR/commands" \
    "$OUTPUT_DIR/logs"

TOOLKIT_VERSION="unknown"

if [[ -r "$VERSION_FILE" ]]; then
    TOOLKIT_VERSION="$(<"$VERSION_FILE")"
fi

PRIMARY_USER="${SUDO_USER:-$(id -un)}"
ROOT_MODE="false"

if ((EUID == 0)); then
    ROOT_MODE="true"
fi

LOG_FILE="$OUTPUT_DIR/logs/system.log"
UNREADABLE_FILE="$OUTPUT_DIR/unreadable-paths.txt"
METADATA_FILE="$OUTPUT_DIR/files-metadata.tsv"

: >"$LOG_FILE"
: >"$UNREADABLE_FILE"

printf 'mode\tuid\tgid\ttype\tpath\n' >"$METADATA_FILE"

chmod 600 \
    "$LOG_FILE" \
    "$UNREADABLE_FILE" \
    "$METADATA_FILE"

COPIED_COUNT=0
MISSING_COUNT=0
ROOT_REQUIRED_COUNT=0
FAILED_COUNT=0

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

write_command_output() {
    local destination="$1"
    shift

    local command_name="$1"
    local status=0

    {
        printf '# Command:'
        printf ' %q' "$@"
        printf '\n\n'

        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf '[SKIPPED] Command not installed: %s\n' "$command_name"
            return 0
        fi

        "$@" 2>&1 || status=$?

        if ((status != 0)); then
            printf '\n[UNAVAILABLE] Command exited with status %s.\n' "$status"
        fi
    } >"$destination"

    chmod 600 "$destination"
}

write_shell_output() {
    local destination="$1"
    local command_text="$2"
    local status=0

    {
        printf '# Command: %s\n\n' "$command_text"

        bash -o pipefail -lc "$command_text" 2>&1 || status=$?

        if ((status != 0)); then
            printf '\n[UNAVAILABLE] Collection exited with status %s.\n' \
                "$status"
        fi
    } >"$destination"

    chmod 600 "$destination"
}

record_metadata() {
    local source="$1"

    if [[ -d "$source" && ! -L "$source" ]]; then
        while IFS= read -r -d '' item; do
            stat \
                --printf='%a\t%u\t%g\t%F\t%n\n' \
                "$item" \
                2>/dev/null || true
        done < <(
            find "$source" \
                -xdev \
                -print0 \
                2>/dev/null
        )
    else
        stat \
            --printf='%a\t%u\t%g\t%F\t%n\n' \
            "$source" \
            2>/dev/null || true
    fi
}

copy_entry() {
    local source="$1"
    local status=0

    if [[ ! -e "$source" && ! -L "$source" ]]; then
        log "SKIPPED missing path: $source"
        MISSING_COUNT=$((MISSING_COUNT + 1))
        return 0
    fi

    if [[ ! -r "$source" ]]; then
        printf '%s\t%s\n' \
            "REQUIRES_ROOT" \
            "$source" \
            >>"$UNREADABLE_FILE"

        log "REQUIRES ROOT: $source"
        ROOT_REQUIRED_COUNT=$((ROOT_REQUIRED_COUNT + 1))
        return 0
    fi

    if [[ -d "$source" && ! -x "$source" ]]; then
        printf '%s\t%s\n' \
            "REQUIRES_ROOT" \
            "$source" \
            >>"$UNREADABLE_FILE"

        log "REQUIRES ROOT: $source"
        ROOT_REQUIRED_COUNT=$((ROOT_REQUIRED_COUNT + 1))
        return 0
    fi

    record_metadata "$source" >>"$METADATA_FILE"

    cp \
        -a \
        --parents \
        --no-preserve=ownership \
        "$source" \
        "$OUTPUT_DIR/files" \
        2>>"$LOG_FILE" || status=$?

    if ((status != 0)); then
        printf '%s\t%s\n' \
            "COPY_FAILED" \
            "$source" \
            >>"$UNREADABLE_FILE"

        log "COPY FAILED: $source"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 0
    fi

    log "COPIED: $source"
    COPIED_COUNT=$((COPIED_COUNT + 1))
}

SELECTED_PATHS=(
    /etc/hostname
    /etc/hosts
    /etc/fstab
    /etc/crypttab
    /etc/os-release
    /etc/debian_version
    /etc/default/grub
    /etc/default/grub.d
    /etc/default/locale
    /etc/timezone
    /etc/localtime
    /etc/gdm3
    /etc/modprobe.d
    /etc/modules
    /etc/modules-load.d
    /etc/initramfs-tools
    /etc/mdadm
    /etc/systemd/system
    /etc/udev/rules.d
    /etc/sysctl.conf
    /etc/sysctl.d
    /etc/security/limits.conf
    /etc/security/limits.d
    /etc/apt/sources.list
    /etc/apt/sources.list.d
    /etc/apt/preferences
    /etc/apt/preferences.d
    /etc/apt/keyrings
    /etc/docker
    /etc/caddy
    /etc/ssh/ssh_config
    /etc/ssh/ssh_config.d
    /etc/ssh/sshd_config
    /etc/ssh/sshd_config.d
    /etc/NetworkManager/conf.d
    /etc/NetworkManager/dispatcher.d
    /etc/tlp.conf
    /etc/tlp.d
    /etc/thinkfan.conf
    /etc/thinkfan.d
    /etc/fancontrol
    /etc/sensors3.conf
    /etc/sensors.d
    /etc/environment
    /etc/profile
    /etc/profile.d
    /etc/bash.bashrc
    /boot/grub/grub.cfg
    /boot/efi/EFI/debian
    /var/lib/systemd/linger
)

log "Collecting selected system configuration."
log "Root mode: $ROOT_MODE"
log "Primary user: $PRIMARY_USER"

for source in "${SELECTED_PATHS[@]}"; do
    copy_entry "$source"
done

write_command_output \
    "$OUTPUT_DIR/commands/hostnamectl.txt" \
    hostnamectl

write_command_output \
    "$OUTPUT_DIR/commands/kernel.txt" \
    uname -a

write_command_output \
    "$OUTPUT_DIR/commands/proc-cmdline.txt" \
    cat /proc/cmdline

write_command_output \
    "$OUTPUT_DIR/commands/block-devices.txt" \
    lsblk \
        -e 7 \
        -o NAME,PATH,TYPE,SIZE,FSTYPE,FSVER,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL

write_command_output \
    "$OUTPUT_DIR/commands/mounts.txt" \
    findmnt --real

write_command_output \
    "$OUTPUT_DIR/commands/filesystem-capacity.txt" \
    df -hT

write_command_output \
    "$OUTPUT_DIR/commands/raid-status.txt" \
    cat /proc/mdstat

write_shell_output \
    "$OUTPUT_DIR/commands/raid-configuration.txt" \
    'if ! command -v mdadm >/dev/null 2>&1; then
        echo "[SKIPPED] Command not installed: mdadm"
     elif ((EUID != 0)); then
        echo "[REQUIRES ROOT] mdadm --detail --scan"
     else
        mdadm --detail --scan
     fi'

write_command_output \
    "$OUTPUT_DIR/commands/uefi-entries.txt" \
    efibootmgr -v

write_command_output \
    "$OUTPUT_DIR/commands/secure-boot.txt" \
    mokutil --sb-state

write_command_output \
    "$OUTPUT_DIR/commands/systemd-enabled.txt" \
    systemctl \
        list-unit-files \
        --state=enabled \
        --no-pager

write_command_output \
    "$OUTPUT_DIR/commands/systemd-timers.txt" \
    systemctl \
        list-timers \
        --all \
        --no-pager

write_command_output \
    "$OUTPUT_DIR/commands/systemd-failed.txt" \
    systemctl \
        --failed \
        --no-pager

write_shell_output \
    "$OUTPUT_DIR/commands/recovery-services.txt" \
    'for unit in \
        gdm3.service \
        docker.service \
        containerd.service \
        caddy.service \
        nvidia-suspend.service \
        nvidia-resume.service \
        nvidia-hibernate.service \
        nvidia-persistenced.service \
        switcheroo-control.service \
        tlp.service \
        fancontrol.service \
        thinkfan.service
     do
        printf "%-36s " "$unit"
        systemctl is-enabled "$unit" 2>/dev/null || echo "not-found"
     done'

write_command_output \
    "$OUTPUT_DIR/commands/nvidia-smi.txt" \
    nvidia-smi

write_shell_output \
    "$OUTPUT_DIR/commands/nvidia-kernel.txt" \
    'if [[ -r /proc/driver/nvidia/version ]]; then
        cat /proc/driver/nvidia/version
     else
        echo "[UNAVAILABLE] NVIDIA kernel information not found."
     fi'

write_shell_output \
    "$OUTPUT_DIR/commands/nvidia-drm-modeset.txt" \
    'if [[ -r /sys/module/nvidia_drm/parameters/modeset ]]; then
        cat /sys/module/nvidia_drm/parameters/modeset
     else
        echo "[UNAVAILABLE] Direct modeset parameter is not readable."
     fi

     printf "Kernel command line: "
     cat /proc/cmdline'

write_shell_output \
    "$OUTPUT_DIR/commands/kernel-modules.txt" \
    'cat /proc/modules | sort'

write_command_output \
    "$OUTPUT_DIR/commands/docker-version.txt" \
    docker version

write_command_output \
    "$OUTPUT_DIR/commands/docker-info.txt" \
    docker info

write_shell_output \
    "$OUTPUT_DIR/commands/apt-files.txt" \
    'find \
        /etc/apt/sources.list \
        /etc/apt/sources.list.d \
        /etc/apt/preferences \
        /etc/apt/preferences.d \
        /etc/apt/keyrings \
        -maxdepth 4 \
        -type f \
        -print \
        2>/dev/null |
     sort'

FORBIDDEN_PATTERNS=(
    '*/etc/shadow'
    '*/etc/gshadow'
    '*/etc/ssh/ssh_host_*'
    '*/etc/NetworkManager/system-connections/*'
    '*/etc/apt/auth.conf'
    '*/etc/apt/auth.conf.d/*'
    '*/etc/sudoers'
    '*/etc/sudoers.d/*'
    '*/etc/machine-id'
)

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if find "$OUTPUT_DIR/files" \
        -path "$pattern" \
        -print \
        -quit |
       grep -q .
    then
        fail "forbidden sensitive path entered the recovery payload: $pattern"
    fi
done

PAYLOAD_BYTES="$(
    du \
        --summarize \
        --bytes \
        "$OUTPUT_DIR/files" \
        2>/dev/null |
    awk '{print $1}'
)"

{
    printf '# Debian System Recovery Payload\n\n'

    printf '## Machine\n\n'
    printf -- '- Hostname: %s\n' "$(hostname)"
    printf -- '- Primary user: %s\n' "$PRIMARY_USER"
    printf -- '- Generated at: %s\n' "$(date --iso-8601=seconds)"
    printf -- '- Toolkit version: %s\n' "$TOOLKIT_VERSION"
    printf -- '- Collected as root: %s\n' "$ROOT_MODE"

    printf '\n## Summary\n\n'
    printf '| Category | Count |\n'
    printf '|---|---:|\n'
    printf '| Selected paths copied | %s |\n' "$COPIED_COUNT"
    printf '| Missing optional paths | %s |\n' "$MISSING_COUNT"
    printf '| Paths requiring root | %s |\n' "$ROOT_REQUIRED_COUNT"
    printf '| Copy failures | %s |\n' "$FAILED_COUNT"
    printf '| Payload bytes | %s |\n' "${PAYLOAD_BYTES:-0}"

    printf '\n## Included recovery areas\n\n'
    printf '%s\n' \
        '- Host identity, locale and filesystem configuration' \
        '- GRUB, GDM, Wayland and kernel configuration' \
        '- NVIDIA and DRM KMS state' \
        '- Software RAID and UEFI information' \
        '- Custom systemd units and enabled-service inventory' \
        '- APT repositories, preferences and public keyrings' \
        '- Docker and Caddy configuration when present' \
        '- SSH configuration without host private keys' \
        '- NetworkManager policy without saved connection secrets' \
        '- Power, fan, sensors, modules, sysctl and udev configuration'

    printf '\n## Safety exclusions\n\n'
    printf '%s\n' \
        '- Password and account hash databases' \
        '- SSH host private keys' \
        '- NetworkManager saved connection secrets' \
        '- APT authentication credentials' \
        '- sudoers policy' \
        '- machine-id replacement' \
        '- runtime state and caches'

    printf '\n## Privilege status\n\n'

    if [[ "$ROOT_MODE" == "true" ]]; then
        printf '%s\n' \
            'The payload was collected as root. Privileged selected paths were' \
            'available unless explicitly reported in `unreadable-paths.txt`.'
    else
        printf '%s\n' \
            'The payload was collected without root privileges. Review' \
            '`unreadable-paths.txt`. A future systemd service will execute the' \
            'production backup as root while preserving the primary user context.'
    fi

    printf '\n## Restore warnings\n\n'
    printf '%s\n' \
        '- Do not restore `/etc` blindly.' \
        '- Verify the Debian major version before applying configuration.' \
        '- Review disk UUIDs and PARTUUIDs before restoring `fstab` or GRUB.' \
        '- Regenerate GRUB and initramfs after approved changes.' \
        '- Verify NVIDIA hardware before applying NVIDIA-specific configuration.' \
        '- Review every custom systemd unit for obsolete paths and secrets.'

    printf '\n## Project and author\n\n'
    printf '%s\n' \
        '- Manuel Alejandro Hernández Giuliani' \
        '- https://manuelhernandezgiuliani.com' \
        '- https://thedataprofessor.com' \
        '- https://mahg.es' \
        '- https://github.com/mahernandezg' \
        '- GNU GPL v3 only (`GPL-3.0-only`)'

    printf '\n## Privacy\n\n'
    printf '%s\n' \
        'This payload contains private workstation configuration and metadata.' \
        'Keep it inside the private disaster recovery storage.'
} >"$OUTPUT_DIR/SYSTEM.md"

chmod 600 "$OUTPUT_DIR/SYSTEM.md"

chmod -R go-rwx "$OUTPUT_DIR"

(
    cd "$OUTPUT_DIR"

    find . \
        -type f \
        ! -name SHA256SUMS \
        -print0 |
    sort -z |
    xargs -0 sha256sum
) >"$OUTPUT_DIR/SHA256SUMS"

chmod 600 "$OUTPUT_DIR/SHA256SUMS"

(
    cd "$OUTPUT_DIR"
    sha256sum --check SHA256SUMS >/dev/null
)

printf 'System recovery payload written to: %s\n' "$OUTPUT_DIR"
printf 'Selected paths copied: %s\n' "$COPIED_COUNT"
printf 'Paths requiring root: %s\n' "$ROOT_REQUIRED_COUNT"
printf 'Copy failures: %s\n' "$FAILED_COUNT"
