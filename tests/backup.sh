#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_SCRIPT="${PROJECT_ROOT}/scripts/backup.sh"

bash -n "$BACKUP_SCRIPT"

help_output="$("$BACKUP_SCRIPT" --help)"
grep -q "backup.sh --dry-run" <<<"$help_output"

set +e
no_mode_output="$("$BACKUP_SCRIPT" 2>&1)"
no_mode_status=$?
set -e

[[ "$no_mode_status" -eq 2 ]]
grep -q "requires --dry-run" <<<"$no_mode_output"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

custom_config="${temporary_directory}/test.conf"

cat >"$custom_config" <<CONFIG
BACKUP_ROOT="${temporary_directory}/recovery"
RETENTION_COUNT="7"
COMPRESSION="zstd"
BACKUP_PERSONAL_FILES="false"
BACKUP_SSH_KEYS="false"
BACKUP_NETWORK_CONNECTIONS="false"
BACKUP_DOCKER_DATA="false"
ENCRYPT_SENSITIVE_DATA="false"
CONFIG

dry_run_output="$(
    "$BACKUP_SCRIPT" \
        --dry-run \
        --config "$custom_config"
)"

grep -q "MODE: DRY RUN" <<<"$dry_run_output"
grep -q "NO FILES WILL BE WRITTEN" <<<"$dry_run_output"
grep -q "Retention count:      7 recovery sets" <<<"$dry_run_output"
grep -q "README.md" <<<"$dry_run_output"
grep -q "MANIFEST.md" <<<"$dry_run_output"
grep -q "inventory.txt" <<<"$dry_run_output"
grep -q "configuration-" <<<"$dry_run_output"
grep -q "SHA256SUMS" <<<"$dry_run_output"
grep -q "Sensitive data policy" <<<"$dry_run_output"
grep -q "DRY RUN COMPLETE" <<<"$dry_run_output"

[[ ! -e "${temporary_directory}/recovery" ]]

readme_output="$(
    "$BACKUP_SCRIPT" \
        --dry-run \
        --config "$custom_config" \
        --show-readme
)"

grep -q "# Debian GNOME Disaster Recovery" <<<"$readme_output"
grep -q "| Hostname |" <<<"$readme_output"
grep -q "## Recovery procedure" <<<"$readme_output"
grep -q "Déjà Dup" <<<"$readme_output"

echo "PASS: backup dry-run and README rendering tests completed"
