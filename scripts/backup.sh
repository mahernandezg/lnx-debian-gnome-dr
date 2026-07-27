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

INVENTORY_SCRIPT="${PROJECT_ROOT}/scripts/inventory.sh"
APPLICATIONS_SCRIPT="${PROJECT_ROOT}/scripts/applications.sh"
DESKTOP_SCRIPT="${PROJECT_ROOT}/scripts/desktop.sh"

MODE=""
OUTPUT_DIR=""
CUSTOM_CONFIG=""
SHOW_README=false

usage() {
    printf '%s\n' \
        "Usage:" \
        "  backup.sh --dry-run [--config FILE] [--show-readme]" \
        "  backup.sh --output-dir DIRECTORY [--config FILE]" \
        "  backup.sh --help" \
        "" \
        "Options:" \
        "  --dry-run              Show the integrated recovery plan." \
        "  --output-dir DIRECTORY Generate a validation recovery set." \
        "  --config FILE          Apply an additional configuration file." \
        "  --show-readme          Render the machine README preview." \
        "  --help                 Show this help." \
        "" \
        "The configured SD destination remains blocked in this version."
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit "${2:-1}"
}

while (($# > 0)); do
    case "$1" in
        --dry-run)
            [[ -z "$MODE" ]] || fail "only one execution mode may be selected." 2
            MODE="dry-run"
            shift
            ;;
        --output-dir)
            [[ -z "$MODE" ]] || fail "only one execution mode may be selected." 2
            [[ $# -ge 2 ]] || fail "--output-dir requires a path." 2
            MODE="collect"
            OUTPUT_DIR="$2"
            shift 2
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

[[ -n "$MODE" ]] || {
    usage >&2
    exit 2
}

[[ -r "$DEFAULT_CONFIG" ]] || {
    fail "default configuration not found: $DEFAULT_CONFIG"
}

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

for script in \
    "$INVENTORY_SCRIPT" \
    "$APPLICATIONS_SCRIPT" \
    "$DESKTOP_SCRIPT"
do
    [[ -x "$script" ]] || fail "required executable not found: $script"
done

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
            2>/dev/null |
        head -n 1
    )"
fi

BACKUP_DATE="$(date --iso-8601=seconds)"
BACKUP_ID="$(date '+%Y-%m-%d_%H-%M-%S')"

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

render_manifest() {
    printf '# Recovery Set Manifest\n\n'

    printf '## Identity\n\n'
    printf -- '- Hostname: %s\n' "$HOSTNAME_VALUE"
    printf -- '- Primary user: %s\n' "$PRIMARY_USER"
    printf -- '- Generated at: %s\n' "$BACKUP_DATE"
    printf -- '- Toolkit version: %s\n' "$TOOLKIT_VERSION"
    printf -- '- Recovery-set stage: integrated validation\n'

    printf '\n## Included components\n\n'
    printf '%s\n' \
        '- `README.md`: machine-specific recovery instructions' \
        '- `HISTORY.md`: machine state at collection time' \
        '- `inventory.txt`: system and hardware inventory' \
        '- `applications/`: GUI, TUI and CLI application manifests' \
        '- `desktop/`: GNOME, extensions, themes, fonts and backgrounds' \
        '- `LICENSE`: GNU GPL version 3' \
        '- `NOTICE.md`: project attribution' \
        '- `SHA256SUMS`: recovery-set integrity verification'

    printf '\n## Not yet included\n\n'
    printf '%s\n' \
        '- selected privileged `/etc` configuration payload' \
        '- encrypted SSH private keys or NetworkManager secrets' \
        '- physical copies of portable applications' \
        '- external application installers' \
        '- compressed `tar.zst` recovery archive' \
        '- automated restore execution'

    printf '\n## Integrity\n\n'
    printf '%s\n' \
        'Run the following command from the recovery-set root:' \
        '' \
        '    sha256sum --check SHA256SUMS'

    printf '\n## Privacy\n\n'
    printf '%s\n' \
        'This recovery set contains private workstation metadata.' \
        'Do not publish it or commit it to Git.'
}

render_history() {
    printf '# Machine Recovery History\n\n'

    printf '## %s\n\n' "$BACKUP_DATE"
    printf -- '- Hostname: %s\n' "$HOSTNAME_VALUE"
    printf -- '- Operating system: %s\n' "$OPERATING_SYSTEM"
    printf -- '- Kernel: %s\n' "$KERNEL"
    printf -- '- Desktop: %s\n' "$DESKTOP"
    printf -- '- Session type: %s\n' "$SESSION_TYPE"
    printf -- '- NVIDIA driver: %s\n' "$NVIDIA_VERSION"
    printf -- '- Recovery toolkit: %s\n' "$TOOLKIT_VERSION"

    printf '\n## Relevant recovery state\n\n'
    printf '%s\n' \
        '- GNOME desktop configuration captured' \
        '- GNOME user extensions captured' \
        '- Themes, icons, fonts and backgrounds captured' \
        '- GUI, TUI and CLI application manifests captured' \
        '- Hardware, package, service, RAID and boot inventory captured'

    if grep -q 'nvidia_drm.modeset=1' /proc/cmdline 2>/dev/null; then
        printf '%s\n' '- NVIDIA DRM modeset enabled in the kernel command line'
    fi
}

print_plan() {
    local planned_root

    if [[ "$MODE" == "collect" ]]; then
        planned_root="$OUTPUT_DIR"
    else
        planned_root="${BACKUP_ROOT}/${HOSTNAME_VALUE}/${BACKUP_ID}"
    fi

    printf '%s\n' \
        "lnx-debian-gnome-dr — Integrated recovery plan" \
        "================================================" \
        ""

    if [[ "$MODE" == "dry-run" ]]; then
        printf '%s\n\n' \
            "MODE: DRY RUN" \
            "NO FILES WILL BE WRITTEN OR MODIFIED."
    else
        printf '%s\n\n' \
            "MODE: VALIDATION RECOVERY SET" \
            "THE CONFIGURED SD DESTINATION REMAINS BLOCKED."
    fi

    printf 'Toolkit version:      %s\n' "$TOOLKIT_VERSION"
    printf 'Hostname:             %s\n' "$HOSTNAME_VALUE"
    printf 'Primary user:         %s\n' "$PRIMARY_USER"
    printf 'Operating system:     %s\n' "$OPERATING_SYSTEM"
    printf 'Kernel:               %s\n' "$KERNEL"
    printf 'Desktop:              %s\n' "$DESKTOP"
    printf 'Session:              %s\n' "$SESSION_TYPE"
    printf 'Planned output:       %s\n' "$planned_root"
    printf 'Configured SD root:   %s\n' "$BACKUP_ROOT"

    printf '\nIntegrated components\n'
    printf '%s\n' "---------------------"
    printf '%s\n' \
        '  README.md' \
        '  MANIFEST.md' \
        '  HISTORY.md' \
        '  inventory.txt' \
        '  applications/' \
        '  desktop/' \
        '  LICENSE' \
        '  NOTICE.md' \
        '  logs/backup.log' \
        '  SHA256SUMS'

    printf '\nSafety boundaries\n'
    printf '%s\n' "-----------------"
    printf '%s\n' \
        '  - No personal documents' \
        '  - No unencrypted private keys' \
        '  - No NetworkManager secrets' \
        '  - No Docker runtime data' \
        '  - No direct writes to the configured SD destination' \
        '  - No restoration actions' \
        '  - No system modifications'
}

print_plan

if [[ "$MODE" == "dry-run" ]]; then
    if [[ "$SHOW_README" == true ]]; then
        printf '\n\nMachine README preview\n'
        printf '%s\n\n' "======================"
        render_readme
    fi

    printf '\nDRY RUN COMPLETE — no files were written.\n'
    exit 0
fi

[[ -n "$OUTPUT_DIR" ]] || fail "output directory is required."

FINAL_OUTPUT="$(realpath -m "$OUTPUT_DIR")"
CONFIGURED_BACKUP_ROOT="$(realpath -m "$BACKUP_ROOT")"
PROJECT_REAL="$(realpath -m "$PROJECT_ROOT")"
HOME_REAL="$(realpath -m "$PRIMARY_HOME")"

case "${FINAL_OUTPUT}/" in
    "${CONFIGURED_BACKUP_ROOT}/"*)
        fail "writes to the configured backup destination remain blocked."
        ;;
esac

case "$FINAL_OUTPUT" in
    /|"$PROJECT_REAL"|"$HOME_REAL")
        fail "unsafe output directory: $FINAL_OUTPUT"
        ;;
esac

if [[ -e "$FINAL_OUTPUT" ]]; then
    if [[ -n "$(find "$FINAL_OUTPUT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        fail "output directory already exists and is not empty: $FINAL_OUTPUT"
    fi

    rmdir "$FINAL_OUTPUT"
fi

mkdir -p "$(dirname "$FINAL_OUTPUT")"

PARTIAL_OUTPUT="${FINAL_OUTPUT}.partial.$$"

cleanup() {
    if [[ -d "$PARTIAL_OUTPUT" ]]; then
        rm -rf "$PARTIAL_OUTPUT"
    fi
}

trap cleanup EXIT

mkdir -p "$PARTIAL_OUTPUT/logs"
chmod 700 "$PARTIAL_OUTPUT" "$PARTIAL_OUTPUT/logs"

LOG_FILE="$PARTIAL_OUTPUT/logs/backup.log"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

log "Starting integrated recovery-set generation."
log "Hostname: $HOSTNAME_VALUE"
log "Output: $FINAL_OUTPUT"

"$INVENTORY_SCRIPT" \
    --output "$PARTIAL_OUTPUT/inventory.txt"

"$APPLICATIONS_SCRIPT" \
    --output-dir "$PARTIAL_OUTPUT/applications"

"$DESKTOP_SCRIPT" \
    --output-dir "$PARTIAL_OUTPUT/desktop"

render_readme >"$PARTIAL_OUTPUT/README.md"
render_manifest >"$PARTIAL_OUTPUT/MANIFEST.md"
render_history >"$PARTIAL_OUTPUT/HISTORY.md"

install -m 600 \
    "$PROJECT_ROOT/LICENSE" \
    "$PARTIAL_OUTPUT/LICENSE"

install -m 600 \
    "$PROJECT_ROOT/NOTICE.md" \
    "$PARTIAL_OUTPUT/NOTICE.md"

log "All recovery components were generated."
log "Generating top-level SHA-256 manifest."

(
    cd "$PARTIAL_OUTPUT"

    find . \
        -type f \
        ! -path './SHA256SUMS' \
        -print0 |
    sort -z |
    xargs -0 sha256sum
) >"$PARTIAL_OUTPUT/SHA256SUMS"

chmod 600 "$PARTIAL_OUTPUT/SHA256SUMS"

log "Verifying top-level SHA-256 manifest."

(
    cd "$PARTIAL_OUTPUT"
    sha256sum --check SHA256SUMS >/dev/null
)

find "$PARTIAL_OUTPUT" -type d -exec chmod 700 {} +
find "$PARTIAL_OUTPUT" -type f -exec chmod 600 {} +

mv "$PARTIAL_OUTPUT" "$FINAL_OUTPUT"
trap - EXIT

printf '\nIntegrated recovery set created successfully:\n'
printf '%s\n' "$FINAL_OUTPUT"

printf '\nVerification command:\n'
printf 'cd %q && sha256sum --check SHA256SUMS\n' "$FINAL_OUTPUT"
