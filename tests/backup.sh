#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Manuel Alejandro Hernández Giuliani

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_SCRIPT="${PROJECT_ROOT}/scripts/backup.sh"

bash -n "$BACKUP_SCRIPT"

help_output="$("$BACKUP_SCRIPT" --help)"
grep -q "backup.sh --dry-run" <<<"$help_output"
grep -q "backup.sh --output-dir" <<<"$help_output"

set +e
no_mode_output="$("$BACKUP_SCRIPT" 2>&1)"
no_mode_status=$?
set -e

[[ "$no_mode_status" -eq 2 ]]
grep -q "Usage:" <<<"$no_mode_output"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

custom_config="${temporary_directory}/test.conf"

cat >"$custom_config" <<CONFIG
BACKUP_ROOT="${temporary_directory}/configured-sd/disaster-recovery"
RETENTION_COUNT="7"
COMPRESSION="zstd"
BACKUP_PERSONAL_FILES="false"
BACKUP_SSH_KEYS="false"
BACKUP_NETWORK_CONNECTIONS="false"
BACKUP_DOCKER_DATA="false"
ENCRYPT_SENSITIVE_DATA="false"
BACKUP_APPLICATION_MANIFESTS="true"
BACKUP_APPLICATION_CONFIG="true"
BACKUP_PORTABLE_APPLICATIONS="true"
BACKUP_EXTERNAL_INSTALLERS="true"
MAX_PORTABLE_FILE_SIZE_MIB="2048"
CONFIG

dry_run_output="$(
    "$BACKUP_SCRIPT" \
        --dry-run \
        --config "$custom_config"
)"

grep -q "MODE: DRY RUN" <<<"$dry_run_output"
grep -q "NO FILES WILL BE WRITTEN" <<<"$dry_run_output"
grep -q "applications/" <<<"$dry_run_output"
grep -q "desktop/" <<<"$dry_run_output"
grep -q "system/" <<<"$dry_run_output"
grep -q "MANIFEST.md" <<<"$dry_run_output"
grep -q "SHA256SUMS" <<<"$dry_run_output"
grep -q "DRY RUN COMPLETE" <<<"$dry_run_output"

[[ ! -e "${temporary_directory}/configured-sd" ]]

readme_output="$(
    "$BACKUP_SCRIPT" \
        --dry-run \
        --config "$custom_config" \
        --show-readme
)"

grep -q "# Debian GNOME Disaster Recovery" <<<"$readme_output"
grep -q "Manuel Alejandro Hernández Giuliani" <<<"$readme_output"
grep -q "manuelhernandezgiuliani.com" <<<"$readme_output"

output_directory="${temporary_directory}/integrated-recovery-set"

"$BACKUP_SCRIPT" \
    --output-dir "$output_directory" \
    --config "$custom_config"

required_files=(
    README.md
    MANIFEST.md
    HISTORY.md
    inventory.txt
    LICENSE
    NOTICE.md
    SHA256SUMS
    logs/backup.log
    applications/APPLICATIONS.md
    applications/SHA256SUMS
    desktop/DESKTOP.md
    system/SYSTEM.md
    system/SHA256SUMS
    system/commands/proc-cmdline.txt
    desktop/SHA256SUMS
    desktop/desktop/dconf.ini
    desktop/extensions/enabled.txt
)

for file in "${required_files[@]}"; do
    [[ -f "${output_directory}/${file}" ]] || {
        echo "FAIL: missing integrated recovery file: $file"
        exit 1
    }
done

grep -q "integrated validation" \
    "$output_directory/MANIFEST.md"

grep -q "automated restore execution" \
    "$output_directory/MANIFEST.md"

grep -q "GNU GENERAL PUBLIC LICENSE" \
    "$output_directory/LICENSE"

grep -q "No recovery-set file will be modified after checksum generation." \
    "$output_directory/logs/backup.log"

(
    cd "$output_directory"
    sha256sum --check SHA256SUMS >/dev/null
)

[[ ! -e "${temporary_directory}/configured-sd" ]]
[[ "$(stat -c '%a' "$output_directory")" == "700" ]]
[[ "$(stat -c '%a' "$output_directory/README.md")" == "600" ]]

echo "PASS: integrated recovery-set generation and integrity tests completed"
