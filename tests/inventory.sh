#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY_SCRIPT="${PROJECT_ROOT}/scripts/inventory.sh"

bash -n "$INVENTORY_SCRIPT"

dry_run_output="$("$INVENTORY_SCRIPT" --dry-run)"

grep -q "DRY RUN" <<<"$dry_run_output"
grep -q "Machine and operating-system identity" <<<"$dry_run_output"
grep -q "NVIDIA, DRM KMS and Secure Boot state" <<<"$dry_run_output"

temporary_inventory="$(mktemp)"
trap 'rm -f "$temporary_inventory"' EXIT

"$INVENTORY_SCRIPT" --output "$temporary_inventory"

[[ -s "$temporary_inventory" ]]
grep -q "# Debian GNOME Workstation Inventory" "$temporary_inventory"
grep -q "## Operating system release" "$temporary_inventory"
grep -q "## Kernel" "$temporary_inventory"
grep -q "Read-only collection: yes" "$temporary_inventory"
grep -q "Contains recovery-sensitive metadata: yes" "$temporary_inventory"
grep -q "## Linux software RAID status" "$temporary_inventory"
grep -q "## UEFI boot entries" "$temporary_inventory"
grep -Eq '^bash(:[^[:space:]]+)?[[:space:]]' "$temporary_inventory"

permissions="$(stat -c '%a' "$temporary_inventory")"
[[ "$permissions" == "600" ]]

echo "PASS: inventory dry-run and collection tests completed"
