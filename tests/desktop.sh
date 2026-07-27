#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Manuel Alejandro Hernández Giuliani

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_SCRIPT="${PROJECT_ROOT}/scripts/desktop.sh"

bash -n "$DESKTOP_SCRIPT"

dry_run_output="$("$DESKTOP_SCRIPT" --dry-run)"

grep -q "GNOME DESKTOP RECOVERY — DRY RUN" <<<"$dry_run_output"
grep -q "Complete dconf export" <<<"$dry_run_output"
grep -q "User-installed GNOME extension files" <<<"$dry_run_output"
grep -q "User themes" <<<"$dry_run_output"
grep -q "User icon themes" <<<"$dry_run_output"
grep -q "User fonts" <<<"$dry_run_output"
grep -q "Configured desktop wallpapers" <<<"$dry_run_output"
grep -q "NO FILES WILL BE WRITTEN" <<<"$dry_run_output"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

output_directory="${temporary_directory}/desktop"

"$DESKTOP_SCRIPT" --output-dir "$output_directory"

required_files=(
    DESKTOP.md
    SHA256SUMS
    desktop/dconf.ini
    desktop/gnome-version.txt
    desktop/gsettings-recursive.txt
    extensions/enabled.txt
    extensions/all.txt
    extensions/details.txt
    logs/desktop.log
)

for file in "${required_files[@]}"; do
    [[ -f "${output_directory}/${file}" ]] || {
        echo "FAIL: missing desktop recovery file: $file"
        exit 1
    }
done

grep -q "# GNOME Desktop Recovery" \
    "$output_directory/DESKTOP.md"

grep -q "## Restore requirement" \
    "$output_directory/DESKTOP.md"

grep -q "Manuel Alejandro Hernández Giuliani" \
    "$output_directory/DESKTOP.md"

expected_enabled="$(
    grep -cvE '^[[:space:]]*$|^[[:space:]]*#|^[[:space:]]*\[' \
        "$output_directory/extensions/enabled.txt" || true
)"

reported_enabled="$(
    awk -F'|' '
        $2 ~ /Enabled GNOME extensions/ {
            value=$3
            gsub(/[[:space:]]/, "", value)
            print value
        }
    ' "$output_directory/DESKTOP.md"
)"

[[ "$expected_enabled" == "$reported_enabled" ]] || {
    echo "FAIL: enabled extension count mismatch"
    exit 1
}

(
    cd "$output_directory"
    sha256sum --check SHA256SUMS >/dev/null
)

[[ "$(stat -c '%a' "$output_directory")" == "700" ]]
[[ "$(stat -c '%a' "$output_directory/DESKTOP.md")" == "600" ]]

echo "PASS: GNOME desktop recovery and integrity tests completed"
