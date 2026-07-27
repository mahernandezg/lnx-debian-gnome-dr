#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Manuel Alejandro Hernández Giuliani

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_SCRIPT="${PROJECT_ROOT}/scripts/system.sh"

bash -n "$SYSTEM_SCRIPT"

dry_run_output="$("$SYSTEM_SCRIPT" --dry-run)"

grep -q "SYSTEM RECOVERY PAYLOAD — DRY RUN" <<<"$dry_run_output"
grep -q "GRUB and kernel command-line configuration" <<<"$dry_run_output"
grep -q "GDM and Wayland configuration" <<<"$dry_run_output"
grep -q "NVIDIA, DRM KMS and PRIME state" <<<"$dry_run_output"
grep -q "Software RAID configuration and status" <<<"$dry_run_output"
grep -q "/etc/shadow" <<<"$dry_run_output"
grep -q "NO FILES WILL BE WRITTEN" <<<"$dry_run_output"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

output_directory="${temporary_directory}/system"

"$SYSTEM_SCRIPT" --output-dir "$output_directory"

required_files=(
    SYSTEM.md
    SHA256SUMS
    unreadable-paths.txt
    files-metadata.tsv
    logs/system.log
    commands/hostnamectl.txt
    commands/proc-cmdline.txt
    commands/raid-status.txt
    commands/uefi-entries.txt
    commands/systemd-enabled.txt
    commands/nvidia-drm-modeset.txt
)

for file in "${required_files[@]}"; do
    [[ -f "${output_directory}/${file}" ]] || {
        echo "FAIL: missing system recovery file: $file"
        exit 1
    }
done

[[ -f "${output_directory}/files/etc/fstab" ]] || {
    echo "FAIL: /etc/fstab was not captured"
    exit 1
}

grep -q "# Debian System Recovery Payload" \
    "$output_directory/SYSTEM.md"

grep -q "## Safety exclusions" \
    "$output_directory/SYSTEM.md"

grep -q "Collected as root:" \
    "$output_directory/SYSTEM.md"

for forbidden in \
    "files/etc/shadow" \
    "files/etc/gshadow" \
    "files/etc/machine-id" \
    "files/etc/sudoers"
do
    [[ ! -e "${output_directory}/${forbidden}" ]] || {
        echo "FAIL: forbidden path captured: $forbidden"
        exit 1
    }
done

if find "$output_directory/files" \
    -path '*/NetworkManager/system-connections/*' \
    -print \
    -quit |
   grep -q .
then
    echo "FAIL: NetworkManager connection secrets were captured"
    exit 1
fi

if find "$output_directory/files" \
    -name 'ssh_host_*_key' \
    -print \
    -quit |
   grep -q .
then
    echo "FAIL: SSH host private keys were captured"
    exit 1
fi

(
    cd "$output_directory"
    sha256sum --check SHA256SUMS >/dev/null
)

[[ "$(stat -c '%a' "$output_directory")" == "700" ]]
[[ "$(stat -c '%a' "$output_directory/SYSTEM.md")" == "600" ]]

echo "PASS: system recovery payload and integrity tests completed"
