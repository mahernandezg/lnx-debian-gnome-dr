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
        "  applications.sh --dry-run" \
        "  applications.sh --output-dir DIRECTORY" \
        "  applications.sh --help" \
        "" \
        "Options:" \
        "  --dry-run              Show the planned inventory without writing." \
        "  --output-dir DIRECTORY Write application manifests to DIRECTORY." \
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
    "Debian package inventory"
    "Manually selected and held APT packages"
    "APT repository and policy metadata"
    "Flatpak applications, runtimes, remotes and overrides"
    "Snap applications"
    "AppImage discovery"
    "Executables under local binary directories"
    "Desktop launcher discovery"
    "pip and pipx tools"
    "uv tools"
    "npm and pnpm global tools"
    "Cargo and rustup tools"
    "Go environment and binaries"
    "mise and asdf runtimes"
    "Homebrew packages"
    "RubyGems, Composer and .NET global tools"
    "System alternatives and executable search path"
)

if [[ "$MODE" == "dry-run" ]]; then
    printf '%s\n\n' \
        "APPLICATION INVENTORY — DRY RUN" \
        "NO FILES WILL BE WRITTEN."

    for item in "${PLAN[@]}"; do
        printf '  - %s\n' "$item"
    done

    printf '\nDRY RUN COMPLETE — no files were written.\n'
    exit 0
fi

[[ -n "$OUTPUT_DIR" ]] || fail "output directory is required."

if [[ -e "$OUTPUT_DIR" ]] &&
   [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    fail "output directory already exists and is not empty: $OUTPUT_DIR"
fi

mkdir -p \
    "$OUTPUT_DIR/apt" \
    "$OUTPUT_DIR/flatpak" \
    "$OUTPUT_DIR/snap" \
    "$OUTPUT_DIR/portable" \
    "$OUTPUT_DIR/local-binaries" \
    "$OUTPUT_DIR/desktop-launchers" \
    "$OUTPUT_DIR/language-tools" \
    "$OUTPUT_DIR/system"

chmod 700 "$OUTPUT_DIR"
find "$OUTPUT_DIR" -type d -exec chmod 700 {} +

PRIMARY_USER="${SUDO_USER:-$(id -un)}"
PRIMARY_HOME="$(getent passwd "$PRIMARY_USER" | cut -d: -f6)"

if [[ -z "$PRIMARY_HOME" ]]; then
    PRIMARY_HOME="${HOME:-unknown}"
fi

export PRIMARY_USER PRIMARY_HOME

TOOLKIT_VERSION="unknown"
if [[ -r "$VERSION_FILE" ]]; then
    TOOLKIT_VERSION="$(<"$VERSION_FILE")"
fi

capture_command() {
    local relative_path="$1"
    shift

    local destination="${OUTPUT_DIR}/${relative_path}"
    local command_name="$1"
    local status=0

    mkdir -p "$(dirname "$destination")"

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

capture_shell() {
    local relative_path="$1"
    local command_text="$2"

    local destination="${OUTPUT_DIR}/${relative_path}"
    local status=0

    mkdir -p "$(dirname "$destination")"

    {
        printf '# Command: %s\n\n' "$command_text"

        bash -o pipefail -lc "$command_text" 2>&1 || status=$?

        if ((status != 0)); then
            printf '\n[UNAVAILABLE] Collection exited with status %s.\n' "$status"
        fi
    } >"$destination"

    chmod 600 "$destination"
}

capture_shell \
    "apt/dpkg-packages.tsv" \
    'dpkg-query -W -f="\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n" | sort'

capture_shell \
    "apt/manual-packages.txt" \
    'apt-mark showmanual | sort'

capture_shell \
    "apt/held-packages.txt" \
    'apt-mark showhold | sort'

capture_command \
    "apt/foreign-architectures.txt" \
    dpkg --print-foreign-architectures

capture_command \
    "apt/policy.txt" \
    apt-cache policy

capture_shell \
    "apt/repository-files.txt" \
    'for path in \
        /etc/apt/sources.list \
        /etc/apt/sources.list.d \
        /etc/apt/preferences \
        /etc/apt/preferences.d \
        /etc/apt/keyrings
     do
        if [[ -e "$path" ]]; then
            find "$path" -maxdepth 3 -type f -printf "%p\n" 2>/dev/null
        fi
     done | sort -u'

capture_command \
    "flatpak/applications.tsv" \
    flatpak list --app --columns=application,branch,origin,installation

capture_command \
    "flatpak/runtimes.tsv" \
    flatpak list --runtime --columns=application,branch,origin,installation

capture_command \
    "flatpak/remotes.txt" \
    flatpak remotes --show-details

capture_command \
    "flatpak/global-overrides.txt" \
    flatpak override --show

capture_command \
    "snap/packages.txt" \
    snap list

capture_shell \
    "portable/appimages.tsv" \
    'printf "path\tsize_bytes\tsha256\n"
     for root in "$PRIMARY_HOME/Applications" "$PRIMARY_HOME/.local/bin" /opt
     do
        [[ -d "$root" ]] || continue

        find "$root" \
            -maxdepth 5 \
            -type f \
            \( -iname "*.AppImage" -o -iname "*.appimage" \) \
            -print0 2>/dev/null
     done |
     sort -z |
     while IFS= read -r -d "" path
     do
        printf "%s\t%s\t%s\n" \
            "$path" \
            "$(stat -c "%s" "$path")" \
            "$(sha256sum "$path" | awk "{print \$1}")"
     done'

capture_shell \
    "local-binaries/files.tsv" \
    'printf "path\tsize_bytes\tsha256\n"
     for root in "$PRIMARY_HOME/.local/bin" /usr/local/bin /usr/local/sbin
     do
        [[ -d "$root" ]] || continue

        find "$root" \
            -maxdepth 2 \
            -type f \
            -perm /111 \
            -print0 2>/dev/null
     done |
     sort -z |
     while IFS= read -r -d "" path
     do
        printf "%s\t%s\t%s\n" \
            "$path" \
            "$(stat -c "%s" "$path")" \
            "$(sha256sum "$path" | awk "{print \$1}")"
     done'

capture_shell \
    "desktop-launchers/files.tsv" \
    'printf "path\tsha256\n"
     for root in \
        "$PRIMARY_HOME/.local/share/applications" \
        /usr/local/share/applications \
        /usr/share/applications
     do
        [[ -d "$root" ]] || continue

        find "$root" \
            -maxdepth 3 \
            -type f \
            -name "*.desktop" \
            -print0 2>/dev/null
     done |
     sort -z |
     while IFS= read -r -d "" path
     do
        printf "%s\t%s\n" \
            "$path" \
            "$(sha256sum "$path" | awk "{print \$1}")"
     done'

capture_command \
    "language-tools/pip-user.txt" \
    python3 -m pip list --user --format=freeze

capture_command \
    "language-tools/pipx.json" \
    pipx list --json

capture_command \
    "language-tools/uv-tools.txt" \
    uv tool list

capture_command \
    "language-tools/npm-global.json" \
    npm list --global --depth=0 --json

capture_command \
    "language-tools/pnpm-global.txt" \
    pnpm list --global --depth=0

capture_command \
    "language-tools/cargo-installed.txt" \
    cargo install --list

capture_command \
    "language-tools/rustup-toolchains.txt" \
    rustup toolchain list

capture_command \
    "language-tools/go-environment.txt" \
    go env

capture_shell \
    "language-tools/go-binaries.tsv" \
    'printf "path\tversion_information\n"

     if ! command -v go >/dev/null 2>&1; then
        echo "[SKIPPED] Command not installed: go"
        exit 0
     fi

     gobin="$(go env GOBIN)"
     gopath="$(go env GOPATH)"

     for root in "$gobin" "$gopath/bin"
     do
        [[ -n "$root" && -d "$root" ]] || continue

        find "$root" \
            -maxdepth 1 \
            -type f \
            -perm /111 \
            -print0 2>/dev/null
     done |
     sort -zu |
     while IFS= read -r -d "" path
     do
        printf "%s\t" "$path"
        go version -m "$path" 2>/dev/null | tr "\n" " "
        printf "\n"
     done'

capture_command \
    "language-tools/mise.txt" \
    mise ls

capture_command \
    "language-tools/asdf.txt" \
    asdf current

capture_command \
    "language-tools/homebrew-formulae.txt" \
    brew list --formula --versions

capture_command \
    "language-tools/homebrew-casks.txt" \
    brew list --cask --versions

capture_command \
    "language-tools/ruby-gems.txt" \
    gem list --local

capture_command \
    "language-tools/composer-global.txt" \
    composer global show

capture_command \
    "language-tools/dotnet-global-tools.txt" \
    dotnet tool list --global

capture_command \
    "system/alternatives.txt" \
    update-alternatives --get-selections

{
    printf '# Application execution environment\n\n'
    printf 'Primary user: %s\n' "$PRIMARY_USER"
    printf 'Primary home: %s\n' "$PRIMARY_HOME"
    printf 'Shell: %s\n' "${SHELL:-unknown}"
    printf 'PATH: %s\n' "${PATH:-unknown}"
} >"$OUTPUT_DIR/system/environment.txt"

chmod 600 "$OUTPUT_DIR/system/environment.txt"

count_records() {
    local file="$1"

    awk '
        NF &&
        $0 !~ /^#/ &&
        $0 !~ /^\$/ &&
        $0 !~ /^\[/ {
            count++
        }
        END {
            print count + 0
        }
    ' "$file"
}

APT_COUNT="$(count_records "$OUTPUT_DIR/apt/dpkg-packages.tsv")"
FLATPAK_COUNT="$(count_records "$OUTPUT_DIR/flatpak/applications.tsv")"
SNAP_COUNT="$(count_records "$OUTPUT_DIR/snap/packages.txt")"
APPIMAGE_COUNT="$(count_records "$OUTPUT_DIR/portable/appimages.tsv")"
LOCAL_BINARY_COUNT="$(count_records "$OUTPUT_DIR/local-binaries/files.tsv")"
DESKTOP_COUNT="$(count_records "$OUTPUT_DIR/desktop-launchers/files.tsv")"

cat >"$OUTPUT_DIR/APPLICATIONS.md" <<EOF
# Workstation Application Inventory

## Machine

- Hostname: $(hostname)
- Primary user: ${PRIMARY_USER}
- Generated at: $(date --iso-8601=seconds)
- Toolkit version: ${TOOLKIT_VERSION}

## Summary

| Category | Detected records |
|---|---:|
| Debian packages | ${APT_COUNT} |
| Flatpak applications | ${FLATPAK_COUNT} |
| Snap packages | ${SNAP_COUNT} |
| AppImage files | ${APPIMAGE_COUNT} |
| Local executable files | ${LOCAL_BINARY_COUNT} |
| Desktop launchers | ${DESKTOP_COUNT} |

## Included inventories

- APT and dpkg
- Flatpak
- Snap
- AppImage
- Local binaries
- Desktop launchers
- Language-specific tools
- System alternatives
- Executable environment

## Recovery policy

Package-managed applications should be reinstalled from their manifests.

Portable and manually installed applications may require preservation of their
original executable, installer, icon and launcher. This inventory records their
location and checksum but does not copy them yet.

Application configuration will be collected in a later cycle using a controlled
allowlist.

## Privacy

This inventory can reveal installed software, paths and workstation usage. Keep
it inside the private disaster recovery storage and do not commit it to Git.
EOF

chmod 600 "$OUTPUT_DIR/APPLICATIONS.md"

(
    cd "$OUTPUT_DIR"

    find . \
        -type f \
        ! -name SHA256SUMS \
        -print0 |
    sort -z |
    xargs -0 sha256sum
) >"$OUTPUT_DIR/SHA256SUMS"

find "$OUTPUT_DIR" -type d -exec chmod 700 {} +
find "$OUTPUT_DIR" -type f -exec chmod 600 {} +

printf 'Application inventory written to: %s\n' "$OUTPUT_DIR"
printf 'Debian packages detected: %s\n' "$APT_COUNT"
printf 'Flatpak applications detected: %s\n' "$FLATPAK_COUNT"
printf 'Snap packages detected: %s\n' "$SNAP_COUNT"
printf 'AppImage files detected: %s\n' "$APPIMAGE_COUNT"
printf 'Local executables detected: %s\n' "$LOCAL_BINARY_COUNT"
printf 'Desktop launchers detected: %s\n' "$DESKTOP_COUNT"
