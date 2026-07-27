#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Manuel Alejandro Hernández Giuliani

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLICATIONS_SCRIPT="${PROJECT_ROOT}/scripts/applications.sh"

bash -n "$APPLICATIONS_SCRIPT"

dry_run_output="$("$APPLICATIONS_SCRIPT" --dry-run)"

grep -q "APPLICATION INVENTORY — DRY RUN" <<<"$dry_run_output"
grep -q "Debian package inventory" <<<"$dry_run_output"
grep -q "AppImage discovery" <<<"$dry_run_output"
grep -q "npm and pnpm global tools" <<<"$dry_run_output"
grep -q "NO FILES WILL BE WRITTEN" <<<"$dry_run_output"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

output_directory="${temporary_directory}/applications"

"$APPLICATIONS_SCRIPT" --output-dir "$output_directory"

required_files=(
    APPLICATIONS.md
    SHA256SUMS
    apt/dpkg-packages.tsv
    apt/manual-packages.txt
    flatpak/applications.tsv
    snap/packages.txt
    portable/appimages.tsv
    local-binaries/files.tsv
    desktop-launchers/files.tsv
    language-tools/npm-global.json
    language-tools/go-environment.txt
    system/environment.txt
)

for file in "${required_files[@]}"; do
    [[ -f "${output_directory}/${file}" ]] || {
        echo "FAIL: missing application inventory file: $file"
        exit 1
    }
done

grep -q "# Workstation Application Inventory" \
    "$output_directory/APPLICATIONS.md"

grep -q "## Recovery policy" \
    "$output_directory/APPLICATIONS.md"

grep -Eq '^bash(:[^[:space:]]+)?[[:space:]]' \
    "$output_directory/apt/dpkg-packages.tsv"

(
    cd "$output_directory"
    sha256sum --check SHA256SUMS >/dev/null
)

[[ "$(stat -c '%a' "$output_directory")" == "700" ]]
[[ "$(stat -c '%a' "$output_directory/APPLICATIONS.md")" == "600" ]]

echo "PASS: application inventory and integrity tests completed"
