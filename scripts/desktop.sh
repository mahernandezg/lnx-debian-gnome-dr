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
        "  desktop.sh --dry-run" \
        "  desktop.sh --output-dir DIRECTORY" \
        "  desktop.sh --help" \
        "" \
        "Options:" \
        "  --dry-run              Show the planned GNOME collection." \
        "  --output-dir DIRECTORY Write the desktop recovery set." \
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
    "Complete dconf export"
    "GNOME and GSettings configuration"
    "Installed and enabled GNOME extensions"
    "User-installed GNOME extension files"
    "GTK 3 and GTK 4 configuration"
    "User themes"
    "User icon themes"
    "User fonts"
    "GNOME Shell themes and assets"
    "Configured desktop wallpapers"
    "Autostart applications"
    "Monitor and display configuration"
    "MIME and default-application associations"
    "Ghostty, Tilix and terminal-related configuration"
)

if [[ "$MODE" == "dry-run" ]]; then
    printf '%s\n\n' \
        "GNOME DESKTOP RECOVERY — DRY RUN" \
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

PRIMARY_USER="${SUDO_USER:-$(id -un)}"
PRIMARY_HOME="$(getent passwd "$PRIMARY_USER" | cut -d: -f6)"

if [[ -z "$PRIMARY_HOME" ]]; then
    PRIMARY_HOME="${HOME:-unknown}"
fi

TOOLKIT_VERSION="unknown"
if [[ -r "$VERSION_FILE" ]]; then
    TOOLKIT_VERSION="$(<"$VERSION_FILE")"
fi

mkdir -p \
    "$OUTPUT_DIR/desktop" \
    "$OUTPUT_DIR/extensions/user" \
    "$OUTPUT_DIR/themes" \
    "$OUTPUT_DIR/icons" \
    "$OUTPUT_DIR/fonts" \
    "$OUTPUT_DIR/backgrounds" \
    "$OUTPUT_DIR/config" \
    "$OUTPUT_DIR/local-share" \
    "$OUTPUT_DIR/logs"

find "$OUTPUT_DIR" -type d -exec chmod 700 {} +

LOG_FILE="$OUTPUT_DIR/logs/desktop.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

write_command_output() {
    local destination="$1"
    shift

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

copy_tree() {
    local source="$1"
    local relative_destination="$2"
    local destination="$OUTPUT_DIR/$relative_destination"

    if [[ ! -d "$source" ]]; then
        log "SKIPPED directory: $source"
        return 0
    fi

    mkdir -p "$destination"

    if command -v rsync >/dev/null 2>&1; then
        rsync -a \
            --exclude='Cache/' \
            --exclude='cache/' \
            --exclude='.cache/' \
            --exclude='*.log' \
            --exclude='*.tmp' \
            "$source/" \
            "$destination/"
    else
        cp -a "$source/." "$destination/"
    fi

    log "COPIED directory: $source"
}

copy_file() {
    local source="$1"
    local relative_destination="$2"
    local destination="$OUTPUT_DIR/$relative_destination"

    if [[ ! -f "$source" ]]; then
        log "SKIPPED file: $source"
        return 0
    fi

    mkdir -p "$(dirname "$destination")"
    cp -a "$source" "$destination"

    log "COPIED file: $source"
}

uri_to_path() {
    local uri="$1"

    python3 - "$uri" <<'PYTHON'
import sys
from urllib.parse import unquote, urlparse

value = sys.argv[1].strip().strip("'").strip('"')
parsed = urlparse(value)

if parsed.scheme == "file":
    print(unquote(parsed.path))
PYTHON
}

copy_wallpaper_from_key() {
    local schema="$1"
    local key="$2"
    local label="$3"

    if ! command -v gsettings >/dev/null 2>&1; then
        return 0
    fi

    local uri
    uri="$(gsettings get "$schema" "$key" 2>/dev/null || true)"

    [[ -n "$uri" ]] || return 0

    local wallpaper
    wallpaper="$(uri_to_path "$uri" 2>/dev/null || true)"

    [[ -n "$wallpaper" ]] || return 0
    [[ -f "$wallpaper" ]] || {
        log "UNAVAILABLE wallpaper: $wallpaper"
        return 0
    }

    local basename
    basename="$(basename "$wallpaper")"

    copy_file \
        "$wallpaper" \
        "backgrounds/${label}-${basename}"
}

log "Collecting GNOME desktop state for user: $PRIMARY_USER"

if command -v dconf >/dev/null 2>&1; then
    dconf dump / >"$OUTPUT_DIR/desktop/dconf.ini"
else
    printf '[SKIPPED] Command not installed: dconf\n' \
        >"$OUTPUT_DIR/desktop/dconf.ini"
fi

chmod 600 "$OUTPUT_DIR/desktop/dconf.ini"

write_command_output \
    "$OUTPUT_DIR/desktop/gnome-version.txt" \
    gnome-shell --version

write_command_output \
    "$OUTPUT_DIR/desktop/gsettings-recursive.txt" \
    gsettings list-recursively

write_command_output \
    "$OUTPUT_DIR/extensions/enabled.txt" \
    gnome-extensions list --enabled

write_command_output \
    "$OUTPUT_DIR/extensions/all.txt" \
    gnome-extensions list

if command -v gnome-extensions >/dev/null 2>&1; then
    : >"$OUTPUT_DIR/extensions/details.txt"

    while IFS= read -r extension; do
        [[ -n "$extension" ]] || continue

        {
            printf '\n## %s\n\n' "$extension"
            gnome-extensions info "$extension" 2>&1 || true
        } >>"$OUTPUT_DIR/extensions/details.txt"
    done < <(gnome-extensions list 2>/dev/null || true)
else
    printf '[SKIPPED] Command not installed: gnome-extensions\n' \
        >"$OUTPUT_DIR/extensions/details.txt"
fi

chmod 600 "$OUTPUT_DIR/extensions/details.txt"

copy_tree \
    "$PRIMARY_HOME/.local/share/gnome-shell/extensions" \
    "extensions/user"

copy_tree \
    "$PRIMARY_HOME/.themes" \
    "themes/home-dot-themes"

copy_tree \
    "$PRIMARY_HOME/.local/share/themes" \
    "themes/local-share-themes"

copy_tree \
    "$PRIMARY_HOME/.icons" \
    "icons/home-dot-icons"

copy_tree \
    "$PRIMARY_HOME/.local/share/icons" \
    "icons/local-share-icons"

copy_tree \
    "$PRIMARY_HOME/.fonts" \
    "fonts/home-dot-fonts"

copy_tree \
    "$PRIMARY_HOME/.local/share/fonts" \
    "fonts/local-share-fonts"

copy_tree \
    "$PRIMARY_HOME/.local/share/backgrounds" \
    "backgrounds/local-share-backgrounds"

copy_tree \
    "$PRIMARY_HOME/.config/gtk-3.0" \
    "config/gtk-3.0"

copy_tree \
    "$PRIMARY_HOME/.config/gtk-4.0" \
    "config/gtk-4.0"

copy_tree \
    "$PRIMARY_HOME/.config/fontconfig" \
    "config/fontconfig"

copy_tree \
    "$PRIMARY_HOME/.config/autostart" \
    "config/autostart"

copy_tree \
    "$PRIMARY_HOME/.config/environment.d" \
    "config/environment.d"

copy_tree \
    "$PRIMARY_HOME/.config/ghostty" \
    "config/ghostty"

copy_tree \
    "$PRIMARY_HOME/.config/tilix" \
    "config/tilix"

copy_file \
    "$PRIMARY_HOME/.config/monitors.xml" \
    "config/monitors.xml"

copy_file \
    "$PRIMARY_HOME/.config/mimeapps.list" \
    "config/mimeapps.list"

copy_file \
    "$PRIMARY_HOME/.config/user-dirs.dirs" \
    "config/user-dirs.dirs"

copy_file \
    "$PRIMARY_HOME/.config/user-dirs.locale" \
    "config/user-dirs.locale"

copy_tree \
    "$PRIMARY_HOME/.local/share/applications" \
    "local-share/applications"

copy_tree \
    "$PRIMARY_HOME/.local/share/color" \
    "local-share/color"

copy_tree \
    "$PRIMARY_HOME/.local/share/sounds" \
    "local-share/sounds"

copy_wallpaper_from_key \
    org.gnome.desktop.background \
    picture-uri \
    light

copy_wallpaper_from_key \
    org.gnome.desktop.background \
    picture-uri-dark \
    dark

copy_wallpaper_from_key \
    org.gnome.desktop.screensaver \
    picture-uri \
    screensaver

SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
DESKTOP_NAME="${XDG_CURRENT_DESKTOP:-unknown}"
GNOME_VERSION="$(gnome-shell --version 2>/dev/null || printf 'unknown')"

ENABLED_EXTENSION_COUNT="$(
    grep -cvE '^\s*$|^\[' \
        "$OUTPUT_DIR/extensions/enabled.txt" \
        2>/dev/null || true
)"

ALL_EXTENSION_COUNT="$(
    grep -cvE '^\s*$|^\[' \
        "$OUTPUT_DIR/extensions/all.txt" \
        2>/dev/null || true
)"

THEME_FILE_COUNT="$(
    find "$OUTPUT_DIR/themes" -type f 2>/dev/null | wc -l
)"

ICON_FILE_COUNT="$(
    find "$OUTPUT_DIR/icons" -type f 2>/dev/null | wc -l
)"

FONT_FILE_COUNT="$(
    find "$OUTPUT_DIR/fonts" -type f 2>/dev/null | wc -l
)"

BACKGROUND_FILE_COUNT="$(
    find "$OUTPUT_DIR/backgrounds" -type f 2>/dev/null | wc -l
)"

{
    printf '# GNOME Desktop Recovery\n\n'

    printf '## Machine\n\n'
    printf -- '- Hostname: %s\n' "$(hostname)"
    printf -- '- Primary user: %s\n' "$PRIMARY_USER"
    printf -- '- Generated at: %s\n' "$(date --iso-8601=seconds)"
    printf -- '- Toolkit version: %s\n' "$TOOLKIT_VERSION"
    printf -- '- Desktop: %s\n' "$DESKTOP_NAME"
    printf -- '- GNOME version: %s\n' "$GNOME_VERSION"
    printf -- '- Session type: %s\n' "$SESSION_TYPE"

    printf '\n## Captured desktop state\n\n'
    printf '| Category | Detected files or records |\n'
    printf '|---|---:|\n'
    printf '| Enabled GNOME extensions | %s |\n' "$ENABLED_EXTENSION_COUNT"
    printf '| Installed GNOME extensions | %s |\n' "$ALL_EXTENSION_COUNT"
    printf '| Theme files | %s |\n' "$THEME_FILE_COUNT"
    printf '| Icon files | %s |\n' "$ICON_FILE_COUNT"
    printf '| Font files | %s |\n' "$FONT_FILE_COUNT"
    printf '| Background files | %s |\n' "$BACKGROUND_FILE_COUNT"

    printf '\n## Included configuration\n\n'
    printf '%s\n' \
        '- Complete dconf export' \
        '- GNOME and GSettings inventory' \
        '- GNOME extension inventory and user extension files' \
        '- User themes and shell themes' \
        '- User icon themes' \
        '- User fonts' \
        '- Configured wallpaper files' \
        '- GTK configuration' \
        '- Monitor configuration' \
        '- Autostart applications' \
        '- MIME associations' \
        '- Selected terminal configuration'

    printf '\n## Restore requirement\n\n'
    printf '%s\n' \
        'For the closest possible restoration, install the same Debian and' \
        'GNOME major versions before applying this desktop recovery set.' \
        '' \
        'GNOME extensions may require compatible versions after an upgrade.'

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
        'This recovery set can contain desktop paths, extension preferences,' \
        'wallpapers and workstation usage metadata. Keep it in private storage.'
} >"$OUTPUT_DIR/DESKTOP.md"

chmod 600 "$OUTPUT_DIR/DESKTOP.md"

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

printf 'GNOME desktop recovery written to: %s\n' "$OUTPUT_DIR"
printf 'Enabled GNOME extensions: %s\n' "$ENABLED_EXTENSION_COUNT"
printf 'Installed GNOME extensions: %s\n' "$ALL_EXTENSION_COUNT"
printf 'Theme files: %s\n' "$THEME_FILE_COUNT"
printf 'Icon files: %s\n' "$ICON_FILE_COUNT"
printf 'Font files: %s\n' "$FONT_FILE_COUNT"
printf 'Background files: %s\n' "$BACKGROUND_FILE_COUNT"
